#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify-libs-api.py —— 翻译映射 API 存在性测试（无 SDK 依赖，Python ≥3.8）。

目的：libs/zh/crates/*.toml 中每个 ["标识符"] 的值必须是三方库源码中真实存在的
官方原名。手写/AI 翻译最常见的事故是「杜撰不存在的 API 名」——转译后 cjc 才报
错，排查成本高。本测试把事故前移：直接对三方库源码做全词校验。

用法：
  python3 scripts/verify-libs-api.py [三方库源码根目录]
    三方库源码根目录缺省依次探测：环境变量 ZHC_LIBS_API_SRC、
    仓库同级 _3rdparty/、/tmp/3rdlibs/。根目录下按「库名/src」定位各库源码
    （如 <根>/csv4cj/src）。找不到源码时跳过存在性校验，仅做结构断言。

检查项：
  1. 键冲突：跨库同节键不得重复；标识符/宏键不得撞 zh 语言包词表
     （与 scripts/check-libs.py 独立实现，互为回归测试）。
  2. API 存在性（有源码时）：每个 ["标识符"] 值必须在对应库 src/ 下以
     全词形式出现（声明或调用处均可）；["模块路径"] 值末段须与库名一致。
  3. 恒等映射：值与键完全相同（如 "sum" = "sum"）视为恒等保留，跳过 2。

退出码：0 = 全部通过；1 = 有失败项。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBS_CRATES = os.path.join(ROOT, "libs", "zh", "crates")
ZH_PACK = os.path.join(ROOT, "zhc", "lang-packs", "zh")
VALID_SECTIONS = ("标识符", "模块路径", "宏")
SECTION_RE = re.compile(r'^\["([^"]+)"\]\s*$')
KV_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
WORD_RE = re.compile(r"\b")


def parse_toml(path):
    """与平台一致的逐行解析：返回 [(节, 键, 值)]。"""
    items = []
    section = None
    with open(path, encoding="utf-8") as f:
        for raw in f.read().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = SECTION_RE.match(line)
            if m:
                section = m.group(1)
                continue
            m = KV_RE.match(line)
            if m and section is not None:
                items.append((section, m.group(1), m.group(2)))
    return items


def collect_pack_keys():
    keys = set()
    for name in ("keywords.toml", "stdlib.toml", "module_paths.toml"):
        path = os.path.join(ZH_PACK, name)
        if os.path.exists(path):
            keys |= {k for _, k, _ in parse_toml(path)}
    return keys


def find_source_root():
    env = os.environ.get("ZHC_LIBS_API_SRC")
    if env and os.path.isdir(env):
        return env
    for cand in (os.path.join(os.path.dirname(ROOT), "_3rdparty"),
                 "/tmp/3rdlibs"):
        if os.path.isdir(cand):
            return cand
    return None


def load_source_text(src_dir):
    chunks = []
    for dirpath, _dirs, files in os.walk(src_dir):
        for name in files:
            if name.endswith(".cj"):
                with open(os.path.join(dirpath, name),
                          encoding="utf-8", errors="ignore") as f:
                    chunks.append(f.read())
    return "\n".join(chunks)


def main():
    args = sys.argv[1:]
    src_root = args[0] if args else find_source_root()
    fails = 0
    owner = {}            # (节, 键) → 库文件
    pack_keys = collect_pack_keys()
    tomls = sorted(f for f in os.listdir(LIBS_CRATES)
                   if f.endswith(".toml") and f != "libdemo.toml")
    if not tomls:
        print("libs/zh/crates/ 下无待测映射（只有 libdemo？）")
        return 1
    print("三方库源码根：%s" % (src_root if src_root else "未找到（跳过存在性校验）"))
    for name in tomls:
        lib = name[:-len(".toml")]
        path = os.path.join(LIBS_CRATES, name)
        items = parse_toml(path)
        src_dir = os.path.join(src_root, lib, "src") if src_root else None
        source = load_source_text(src_dir) if src_dir and os.path.isdir(src_dir) else None
        ids = [(k, v) for sec, k, v in items if sec == "标识符"]
        paths = {k: v for sec, k, v in items if sec == "模块路径"}
        # 检查 1：跨库键冲突 + 撞词表
        for sec, k, _v in items:
            if k in pack_keys:
                fails += 1
                print("【撞词表】%s：[%s] \"%s\" 与 zh 语言包键集冲突" % (name, sec, k))
            if (sec, k) in owner:
                fails += 1
                print("【跨库重复】%s：[%s] \"%s\" 已见于 %s"
                      % (name, sec, k, owner[(sec, k)]))
            else:
                owner[(sec, k)] = name
        # 检查 2：模块路径末段须为库本名
        for k, v in paths.items():
            if v.split(".")[-1] != lib:
                fails += 1
                print("【路径不符】%s：\"%s\" = \"%s\" 末段 ≠ 库名 %s"
                      % (name, k, v, lib))
        # 检查 3：标识符值在源码中全词存在（恒等映射跳过）
        if source:
            missing = []
            for k, v in ids:
                if k == v:
                    continue
                if not re.search(r"\b%s\b" % re.escape(v), source):
                    missing.append((k, v))
            if missing:
                fails += 1
                print("【API 不存在】%s：以下值在 %s/src/ 源码中未找到：" % (name, lib))
                for k, v in missing:
                    print("    \"%s\" = \"%s\"" % (k, v))
            else:
                print("通过：%s（标识符 %d 个全部命中源码；模块路径 %d 条）"
                      % (name, len(ids), len(paths)))
        else:
            print("跳过存在性校验：%s（未找到 %s 源码；标识符 %d 个）"
                  % (name, lib, len(ids)))
    if fails == 0:
        print("=== verify-libs-api：全部通过 ===")
        return 0
    print("=== verify-libs-api：%d 项失败 ===" % fails)
    return 1


if __name__ == "__main__":
    sys.exit(main())
