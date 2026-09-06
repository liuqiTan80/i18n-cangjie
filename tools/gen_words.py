#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zhc 扩展词表生成器：从语言包生成 VS Code 补全/悬停词表（与 gen_highlight.py 同源）。

从语言包的 keywords.toml / stdlib.toml / crates/*.toml 生成词表 JSON —— 扩展运行时
本地加载（无需 zhc 可执行文件即可联想/释义），与高亮语法同源不漂移。
词条字段语义：zh = 方言词（如 打印行/печать），en = 官方仓颉名（println）。

词条分类（kind）推导规则：
  - keywords.toml 非 [宏] 节       → keyword（cat = 节名，如 声明/控制流/运算符）
  - keywords.toml [宏] 节          → macro（源码书写为 @派生/@测试/@期望）
  - crates/*.toml [宏] 节          → macro（cat = crate 名，演示库宏）
  - stdlib.toml [模块路径]         → module（import 语句联想）
  - stdlib.toml [标识符]：值首字母大写 → type（字符串=String）；true/false → literal；
    其余 → function（打印行=println，补全自动带 ()）

用法（P-2 批量，无参数）：python3 tools/gen_words.py
  → zhc/lang-packs/* 逐语言生成：zh → lib/zhc-words.json（历史文件名）；
    其余 → lib/words-<代码>.json

旧单语言用法兼容：python3 tools/gen_words.py [语言包目录] [输出路径]
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
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    packs_root = os.path.join(repo, "zhc", "lang-packs")
    out_dir = os.path.join(repo, "tools", "vscode-extension", "lib")
    args = sys.argv[1:]
    if len(args) >= 1:
        # 旧单语言调用（兼容）：[语言包目录] [输出路径]
        pack_dir = os.path.abspath(args[0])
        code = os.path.basename(os.path.normpath(pack_dir))
        out_path = args[1] if len(args) > 1 else os.path.join(out_dir, words_name_for(code))
        out_parent = os.path.dirname(out_path)
        if out_parent:
            os.makedirs(out_parent, exist_ok=True)
        write_words(pack_dir, code, out_path)
        return
    # 批量：zhc/lang-packs/*
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.isdir(packs_root):
        print(f"语言包根不存在：{packs_root}")
        sys.exit(1)
    langs = sorted(d for d in os.listdir(packs_root)
                   if os.path.isdir(os.path.join(packs_root, d))
                   and os.path.exists(os.path.join(packs_root, d, "keywords.toml")))
    for code in langs:
        write_words(os.path.join(packs_root, code), code, os.path.join(out_dir, words_name_for(code)))
    print(f"批量完成：{len(langs)} 个语言包 → {out_dir}")


def words_name_for(code):
    """词表文件命名：zh 沿用历史 zhc-words.json，其余 words-<code>.json。"""
    return "zhc-words.json" if code == "zh" else f"words-{code}.json"


def write_words(pack_dir, code, out_path):
    words = build_words(os.path.abspath(pack_dir))
    doc = {
        "note": f"由 gen_words.py 从语言包生成，勿手改（与 tmLanguage 同源：zhc/lang-packs/{code}；zh=方言词，en=官方名）",
        "lang": code,
        "words": words,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    from collections import Counter
    kinds = Counter(w["kind"] for w in words)
    print(f"==> 已生成 {out_path}（{code} 共 {len(words)} 词条：{dict(kinds)}）")


if __name__ == "__main__":
    main()
