#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zhc 扩展词表生成器：从语言包生成 VS Code 补全/悬停词表（与 gen_highlight.py 同源）。

从 zhc/lang-packs/zh 的 keywords.toml / stdlib.toml / crates/*.toml 生成
tools/vscode-extension/lib/zhc-words.json —— 扩展运行时本地加载（无需 zhc 可执行
文件即可联想/释义），与高亮语法同源不漂移。

词条分类（kind）推导规则：
  - keywords.toml 非 [宏] 节       → keyword（cat = 节名，如 声明/控制流/运算符）
  - keywords.toml [宏] 节          → macro（源码书写为 @派生/@测试/@期望）
  - crates/*.toml [宏] 节          → macro（cat = crate 名，演示库宏）
  - stdlib.toml [模块路径]         → module（import 语句联想）
  - stdlib.toml [标识符]：值首字母大写 → type（字符串=String）；true/false → literal；
    其余 → function（打印行=println，补全自动带 ()）

用法：python3 tools/gen_words.py [语言包目录] [输出路径]
默认：zhc/lang-packs/zh → tools/vscode-extension/lib/zhc-words.json
"""
import json
import os
import re
import sys

# ---------- 迷你 TOML 键值解析（与 gen_highlight.py 同款：节头 + "键" = "值"） ----------

def parse_toml(path):
    """返回 (sections, pairs)：sections 为节名 -> {键: 值}，pairs 为顶层键值。"""
    sections = {}
    pairs = {}
    cur = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("["):
                m = re.match(r'^\["?([^"\]]+)"?\]$', line)
                if m:
                    cur = m.group(1).strip()
                    sections.setdefault(cur, {})
                continue
            m = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"', line)
            if m:
                key = m.group(1).replace('\\"', '"').replace("\\\\", "\\")
                val = m.group(2).replace('\\"', '"').replace("\\\\", "\\")
                if cur is None:
                    pairs[key] = val
                else:
                    sections[cur][key] = val
    return sections, pairs


def kind_of(en):
    """stdlib 标识符分类：类型（首字母大写）/ 字面量 / 函数。"""
    if re.match(r"^[A-Z]", en):
        return "type"
    if en in ("true", "false"):
        return "literal"
    return "function"


def build_words(pack_dir):
    words = []
    # 1) keywords.toml：keyword + 宏节独立为 macro
    sections, _ = parse_toml(os.path.join(pack_dir, "keywords.toml"))
    for cat, kv in sections.items():
        kind = "macro" if cat == "宏" else "keyword"
        for zh, en in kv.items():
            words.append({"zh": zh, "en": en, "kind": kind, "cat": cat})
    # 2) stdlib.toml：模块路径（import 联想）+ 标识符分类
    sections, _ = parse_toml(os.path.join(pack_dir, "stdlib.toml"))
    for zh, en in sections.get("模块路径", {}).items():
        words.append({"zh": zh, "en": en, "kind": "module", "cat": "模块路径"})
    for zh, en in sections.get("标识符", {}).items():
        words.append({"zh": zh, "en": en, "kind": kind_of(en), "cat": "标识符"})
    # 3) crates/*.toml：演示库宏（@ 前缀）
    crates_dir = os.path.join(pack_dir, "crates")
    if os.path.isdir(crates_dir):
        for name in sorted(os.listdir(crates_dir)):
            if not name.endswith(".toml"):
                continue
            secs, _ = parse_toml(os.path.join(crates_dir, name))
            crate = name[:-5]
            for zh, en in secs.get("宏", {}).items():
                words.append({"zh": zh, "en": en, "kind": "macro", "cat": crate})
    return words


def main():
    pack_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "zhc", "lang-packs", "zh")
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(__file__), "vscode-extension", "lib", "zhc-words.json")
    words = build_words(os.path.abspath(pack_dir))
    doc = {
        "note": "由 gen_words.py 从语言包生成，勿手改（与 zhc.tmLanguage.json 同源：zhc/lang-packs/zh）",
        "words": words,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    from collections import Counter
    kinds = Counter(w["kind"] for w in words)
    print(f"==> 已生成 {out_path}（共 {len(words)} 词条：{dict(kinds)}）")


if __name__ == "__main__":
    main()
