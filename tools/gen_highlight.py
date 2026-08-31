#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zhc 语法高亮生成器（设计 §9.2 职责 1/5 + 阶段 4 落地要点）。

从语言包生成 VS Code TextMate 语法（tmLanguage JSON），保证高亮与映射永不漂移：
  - keywords.toml 全部节 → keyword.declaration / keyword.control
  - stdlib.toml ["标识符"] → storage.type（类型词）与 support.function（其余）
  - crates/*.toml ["宏"] → entity.name.function.macro（@ 前缀）
中文词边界用 (?<!\\p{L}) / (?!\\p{L}) 断言（\\b 对 CJK 无效）。

用法：python3 tools/gen_highlight.py [语言包目录] [输出路径]
默认：zhc/lang-packs/zh → tools/vscode-extension/syntaxes/zhc.tmLanguage.json
"""
import json
import os
import re
import sys

# ---------- 迷你 TOML 键值解析（zhc 语言包子集：节头 + "键" = "值" + # 注释） ----------

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
                if cur:
                    sections[cur][key] = val
                else:
                    pairs[key] = val
    return sections, pairs

def collect_keywords(lang_dir):
    """keywords.toml 非 [宏] 节键（[宏] 节独立为宏表，与 zhc 加载语义一致）。"""
    words = set()
    p = os.path.join(lang_dir, "keywords.toml")
    if os.path.exists(p):
        sections, _ = parse_toml(p)
        for sec_name, table in sections.items():
            if sec_name == "宏":
                continue   # @ 前缀宏专用，不当作普通关键字
            words.update(table.keys())
    return sorted(words)

def collect_stdlib(lang_dir):
    """stdlib.toml ["标识符"] 节；返回 (类型词, 其他词)。"""
    types = set()
    others = set()
    p = os.path.join(lang_dir, "stdlib.toml")
    if os.path.exists(p):
        sections, _ = parse_toml(p)
        sec = sections.get("标识符", {})
        # 类型词判定：官方值为仓颉类型名（首字母大写或内置类型小写全集）
        builtin_types = {"Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16",
                         "UInt32", "UInt64", "Float32", "Float64", "Bool",
                         "String", "Rune", "Char", "Unit", "Array", "ArrayList",
                         "HashMap", "HashSet", "Option", "Result", "Range",
                         "Pair", "Tuple", "StringBuilder", "Math", "DateTime",
                         "Duration", "Path", "File", "Directory", "Exception"}
        for k, v in sec.items():
            if v in builtin_types or re.match(r"^[A-Z][A-Za-z0-9_]*$", v):
                types.add(k)
            else:
                others.add(k)
    return sorted(types), sorted(others)

def collect_macros(lang_dir):
    """宏母语名 = keywords.toml [宏] 节 + crates/*.toml [宏] 节（@ 前缀高亮）。"""
    words = set()
    p = os.path.join(lang_dir, "keywords.toml")
    if os.path.exists(p):
        sections, _ = parse_toml(p)
        words.update(sections.get("宏", {}).keys())
    crates_dir = os.path.join(lang_dir, "crates")
    if os.path.isdir(crates_dir):
        for name in sorted(os.listdir(crates_dir)):
            if not name.endswith(".toml"):
                continue
            sections, _ = parse_toml(os.path.join(crates_dir, name))
            words.update(sections.get("宏", {}).keys())
    return sorted(words)

def boundary_pattern(word):
    """中文词边界：前后加 (?<!\\p{L}) / (?!\\p{L}) 断言（CJK 词边界）。"""
    return r"(?<!\p{L})" + re.escape(word) + r"(?!\p{L})"

def keyword_pattern(words, prefix="", suffix=""):
    return "|".join(boundary_pattern(prefix + w + suffix) for w in words)

def escape_json_word(word):
    return word.replace("\\", "\\\\").replace('"', '\\"')

def build_grammar(lang_dir):
    keywords = collect_keywords(lang_dir)
    types, funcs = collect_stdlib(lang_dir)
    macros = collect_macros(lang_dir)

    patterns = []
    if macros:
        patterns.append({
            "name": "entity.name.function.macro.zc",
            "match": r"@\s*(" + "|".join(boundary_pattern(w) for w in macros) + r")",
            "captures": {"1": {"name": "entity.name.function.macro.zc"}},
        })
    if keywords:
        patterns.append({
            "name": "keyword.control.zc",
            "match": keyword_pattern(keywords),
        })
    if types:
        patterns.append({
            "name": "storage.type.zc",
            "match": keyword_pattern(types),
        })
    if funcs:
        patterns.append({
            "name": "support.function.zc",
            "match": keyword_pattern(funcs),
        })
    # 基础词法：注释 / 字符串（含插值）/ 数字 / 反引号原始标识符
    base = [
        {"name": "comment.line.double-slash.zc", "match": r"//.*$"},
        {"name": "comment.block.zc", "begin": r"/\*", "end": r"\*/"},
        {"name": "string.quoted.single.zc", "begin": r"r?'(?:\\.|[^'\\])*'",
         "end": r"(?<=')", "patterns": []},
        {"name": "string.quoted.double.zc", "begin": r'"', "end": r'"',
         "patterns": [{"name": "constant.character.escape.zc", "match": r"\\.|\\u\{[0-9a-fA-F]+\}"},
                      {"name": "variable.other.interpolation.zc",
                       "match": r"\$\{.*?\}|\$\(.*?\)|\$[A-Za-z_][A-Za-z0-9_]*"}]},
        {"name": "constant.numeric.zc", "match": r"\b(0[xX][0-9a-fA-F_]+|\d[\d_]*(\.\d+)?([eE][+-]?\d+)?)\b"},
        {"name": "variable.other.raw-identifier.zc", "begin": r"`", "end": r"`"},
    ]
    patterns = base + patterns
    return {
        "name": "zhc 方言（仓颉）",
        "scopeName": "source.zc",
        "fileTypes": ["zc"],
        "patterns": patterns,
    }

def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    lang_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(repo, "zhc", "lang-packs", "zh")
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        repo, "tools", "vscode-extension", "syntaxes", "zhc.tmLanguage.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    grammar = build_grammar(lang_dir)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(grammar, f, ensure_ascii=False, indent=2)
    n_kw = len(collect_keywords(lang_dir))
    n_t, n_f = len(collect_stdlib(lang_dir)[0]), len(collect_stdlib(lang_dir)[1])
    n_m = len(collect_macros(lang_dir))
    print(f"高亮生成完成：关键字 {n_kw} / 类型 {n_t} / 函数 {n_f} / 宏 {n_m}")
    print(f"输出：{out_path}")

if __name__ == "__main__":
    main()
