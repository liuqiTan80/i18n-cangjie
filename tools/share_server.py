#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
share_server.py —— zhc 翻译资源共享仓库服务端（零第三方依赖，Python ≥3.8）。

配合 `zhc share`（设计 §18）：团队/个人可自建共享端点，也可直接把 libs/ 目录
托管为静态站点（GET 部分任何静态服务器都能替代本脚本）。

端点：
  GET  /index.json                    共享索引（元数据清单）
  GET  /crates/<语言>/<库名>.toml     单个映射文件（按需下载）
  POST /share-publish                 上传映射（JSON：名称/语言/描述/作者/
                                      键数/校验和/时间/内容）

上传校验（与 zhc 端同口径，防脏数据入库）：
  1. 必填字段齐全（描述/作者可空）；名称净化（禁 / \\ .. 空白）；
  2. 内容过行级门禁：节名合法（标识符/模块路径/宏）、键值带引号、无重复键、
     标识符值为官方名格式、无行内注释；
  3. 校验和重算比对（客户端 hash64 同款算法：FNV 变体 rol7 + 黄金比例异或）；
  4. 覆盖同名同语言 = 更新（index 幂等 upsert），跨语言同名允许并存。

用法：
  python3 tools/share_server.py --port 8000 --registry <共享仓库目录>
  共享仓库目录缺省 ./share-registry（不存在自动创建）。Ctrl-C 停止。
"""

import argparse
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SECTION_RE = re.compile(r'^\[["]([^"]+)["]\]\s*$')
KV_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
ID_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
VALID_SECTIONS = ("标识符", "模块路径", "宏")


def zhc_hash64(data: bytes) -> str:
    """与 zhc/src/cache.cj hash64 完全一致：FNV 初值 + 循环左移 7 + 黄金比例异或。"""
    h = 0xCBF29CE484222325
    for b in data:
        h ^= b
        h = ((h << 7) | (h >> 57)) & 0xFFFFFFFFFFFFFFFF
        h ^= 0x9E3779B97F4A7C15
    return "%016x" % h


def sanitize_name(name):
    """名称净化：与 zhc share 的 sanitizeShareName 同口径。"""
    if not isinstance(name, str):
        return ""
    t = name.strip()
    if not t or any(ch in t for ch in ("/", "\\", "..")) or re.search(r"\s", t):
        return ""
    return t


def validate_toml(text):
    """映射内容行级门禁；返回错误清单（空 = 通过）。"""
    errors = []
    seen = {}
    section = None
    for i, raw in enumerate(text.split("\n"), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = SECTION_RE.match(line)
        if m:
            section = m.group(1)
            if section not in VALID_SECTIONS:
                errors.append("第 %d 行非法节名 [%s]" % (i, section))
            continue
        m = KV_RE.match(line)
        if not m:
            errors.append("第 %d 行无法解析（键/值须引号包裹且无行内注释）" % i)
            continue
        k, v = m.group(1), m.group(2)
        if section is None:
            errors.append("第 %d 行键值出现在节声明之前" % i)
            continue
        if k in seen:
            errors.append("第 %d 行重复键 \"%s\"" % (i, k))
            continue
        seen[k] = section
        if not v:
            errors.append("第 %d 行键 \"%s\" 的值为空" % (i, k))
        elif section == "标识符" and not ID_RE.match(v):
            errors.append("第 %d 行键 \"%s\" 的值非官方标识符：%s" % (i, k, v))
    return errors


class Registry:
    """共享仓库目录的读写封装（index.json + crates/<语言>/<名>.toml）。"""

    def __init__(self, root):
        self.root = root
        os.makedirs(os.path.join(root, "crates"), exist_ok=True)

    def index_path(self):
        return os.path.join(self.root, "index.json")

    def read_index(self):
        p = self.index_path()
        if not os.path.exists(p):
            return {"版本": 1, "库": []}
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
            if not isinstance(data.get("库"), list):
                data["库"] = []
            return data
        except (OSError, ValueError) as e:
            raise RuntimeError("index.json 损坏（%s），请先修复或删除" % e)

    def write_index(self, data):
        data["版本"] = 1
        data["库"].sort(key=lambda e: (e.get("语言", ""), e.get("名称", "")))
        tmp = self.index_path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
            f.write("\n")
        os.replace(tmp, self.index_path())

    def serve_file(self, rel):
        """读取 index.json / crates/**；拒绝穿越与越权路径。返回 bytes 或 None。"""
        norm = os.path.normpath(rel)
        if norm.startswith("..") or os.path.isabs(norm):
            return None
        if norm != "index.json" and not norm.startswith("crates" + os.sep):
            return None
        p = os.path.join(self.root, norm)
        if not os.path.isfile(p):
            return None
        with open(p, "rb") as f:
            return f.read()

    def publish(self, payload):
        """处理 /share-publish：校验 → 写文件 → upsert index。返回 (msg, 状态)。"""
        for field in ("名称", "语言", "校验和", "内容"):
            if not isinstance(payload.get(field), str) or not payload.get(field):
                return "缺少必填字段：%s" % field, 400
        name = sanitize_name(payload["名称"])
        lang = sanitize_name(payload["语言"])
        if not name or not lang:
            return "名称/语言含非法字符（禁 / \\ .. 空白）", 400
        content = payload["内容"]
        errors = validate_toml(content)
        if errors:
            return "内容未通过门禁：%s" % "；".join(errors[:3]), 400
        checksum = zhc_hash64(content.encode("utf-8"))
        if checksum != payload["校验和"]:
            return "校验和不符：客户端 %s ≠ 服务端 %s" % (payload["校验和"], checksum), 400
        entry = {
            "名称": name, "语言": lang,
            "描述": payload.get("描述", "") if isinstance(payload.get("描述"), str) else "",
            "作者": payload.get("作者", "") if isinstance(payload.get("作者"), str) else "",
            "键数": payload.get("键数", 0) if isinstance(payload.get("键数"), int) else 0,
            "校验和": checksum,
            "时间": payload.get("时间", "") if isinstance(payload.get("时间"), str) else "",
        }
        index = self.read_index()
        index["库"] = [e for e in index["库"]
                       if not (e.get("名称") == name and e.get("语言") == lang)]
        index["库"].append(entry)
        crate_path = os.path.join(self.root, "crates", lang, "%s.toml" % name)
        os.makedirs(os.path.dirname(crate_path), exist_ok=True)
        with open(crate_path, "w", encoding="utf-8") as f:
            f.write(content)
        self.write_index(index)
        return "已收录 %s（%s 方言，键 %d，校验和 %s）" % (name, lang, entry["键数"], checksum), 200


REGISTRY = None  # 由 main 装配


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body=b"", mime="application/json; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0].lstrip("/")
        data = REGISTRY.serve_file(path) if path else None
        if data is None:
            self._send(404, json.dumps({"ok": False, "message": "不存在：%s" % path},
                                       ensure_ascii=False).encode("utf-8"))
            return
        mime = "application/json; charset=utf-8" if path.endswith(".json") \
            else "text/plain; charset=utf-8"
        self._send(200, data, mime)

    def do_POST(self):
        if self.path.split("?")[0].lstrip("/") != "share-publish":
            self._send(404, json.dumps({"ok": False, "message": "未知端点"},
                                       ensure_ascii=False).encode("utf-8"))
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as e:
            self._send(400, json.dumps({"ok": False, "message": "请求体非法：%s" % e},
                                       ensure_ascii=False).encode("utf-8"))
            return
        try:
            msg, code = REGISTRY.publish(payload)
        except RuntimeError as e:
            self._send(500, json.dumps({"ok": False, "message": str(e)},
                                       ensure_ascii=False).encode("utf-8"))
            return
        self._send(code, json.dumps({"ok": code == 200, "message": msg},
                                    ensure_ascii=False).encode("utf-8"))

    def log_message(self, fmt, *args):  # 静默默认访问日志（验收走 stdout 断言）
        sys.stderr.write("[share-server] " + (fmt % args) + "\n")


def main():
    global REGISTRY
    ap = argparse.ArgumentParser(description="zhc 翻译资源共享仓库服务端")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--registry", default="./share-registry")
    args = ap.parse_args()
    REGISTRY = Registry(args.registry)
    print("[share-server] 仓库目录：%s  端点：http://127.0.0.1:%d（GET index.json / "
          "crates/*；POST share-publish）" % (os.path.abspath(args.registry), args.port),
          flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
