#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zhc 语法高亮生成器（设计 §9.2 职责 1/5 + 阶段 4 落地要点 + P-2 多语言化）。

从语言包生成 VS Code TextMate 语法（tmLanguage JSON），保证高亮与映射永不漂移：
  - keywords.toml 全部节 → keyword.declaration / keyword.control
  - stdlib.toml ["标识符"] → storage.type（类型词）与 support.function（其余）
  - crates/*.toml ["宏"] → entity.name.function.macro（@ 前缀）
中文词边界用 (?<!\\p{L}) / (?!\\p{L}) 断言（\\b 对 CJK 无效）。

用法（P-2 批量，无参数）：python3 tools/gen_highlight.py
  → zhc/lang-packs/*（含 lang_info.toml）逐语言生成语法文件：
    zh → tools/vscode-extension/syntaxes/zhc.tmLanguage.json（历史文件名）
    其余 → syntaxes/zhc-<代码>.tmLanguage.json（fileTypes = 语言包声明的扩展名）
    scopeName 按语言唯一（zh=source.zc，其余 source.zc.<代码>）：VS Code 语法表
    按 scopeName 全局去重，共用会互相覆盖导致全部语言按同一词表着色。

旧单语言用法兼容：python3 tools/gen_highlight.py [语言包目录] [输出路径]
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
    esc = re.escape(word)
    # re.escape 会把空格转义为 \x20 风格之外的 \ 空格：正则里空格本身即字面量，
    # 且 TextMate（Oniguruma）对「反斜杠 + 空格」转义的兼容性存疑——还原为字面空格
    # （空格键实测可用，如 ar「وإلا إذا」/ en“else if”）；其余转义保留
    esc = esc.replace("\\ ", " ")
    return r"(?<!\p{L})" + esc + r"(?!\p{L})"

def keyword_pattern(words, prefix="", suffix=""):
    return "|".join(boundary_pattern(prefix + w + suffix) for w in words)

def escape_json_word(word):
    return word.replace("\\", "\\\\").replace('"', '\\"')

def scope_name_for(code):
    """scopeName 按语言唯一：zh 沿用 source.zc（历史），其余 source.zc.<code>。

    VS Code TextMate 注册表按 scopeName 全局去重——8 语言若共用 source.zc，
    后加载的语法文件会覆盖先加载者，全部语言将按同一份词表着色。
    """
    return "source.zc" if code == "zh" else f"source.zc.{code}"


def build_grammar(lang_dir, ext="zc", code="zh"):
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
        "name": "zhc 方言（仓颉）" if code == "zh" else f"zhc 方言（{code}）",
        "scopeName": scope_name_for(code),
        "fileTypes": [ext],
        "patterns": patterns,
    }


def lang_info_ext(lang_dir):
    """语言包 lang_info.toml 的扩展名字段（P-2：方言源码扩展名）；解析失败返回 None。"""
    p = os.path.join(lang_dir, "lang_info.toml")
    if not os.path.exists(p):
        return None
    sections, _ = parse_toml(p)
    sec = sections.get("语言包", {})
    ext = sec.get("扩展名", "").strip()
    if not ext:
        return None
    return ext.split(",")[0].strip()


def out_name_for(code):
    """语法文件命名：zh 沿用历史 zhc.tmLanguage.json，其余 zhc-<code>.tmLanguage.json。"""
    return "zhc.tmLanguage.json" if code == "zh" else f"zhc-{code}.tmLanguage.json"


def generate_one(lang_dir, code, out_path):
    ext = lang_info_ext(lang_dir)
    if ext is None:
        ext = code
    grammar = build_grammar(lang_dir, ext=ext, code=code)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(grammar, f, ensure_ascii=False, indent=2)
    n_kw = len(collect_keywords(lang_dir))
    n_t, n_f = len(collect_stdlib(lang_dir)[0]), len(collect_stdlib(lang_dir)[1])
    n_m = len(collect_macros(lang_dir))
    print(f"高亮生成完成 [{code}](.{ext})：关键字 {n_kw} / 类型 {n_t} / 函数 {n_f} / 宏 {n_m}")
    print(f"输出：{out_path}")


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    packs_root = os.path.join(repo, "zhc", "lang-packs")
    out_dir = os.path.join(repo, "tools", "vscode-extension", "syntaxes")
    args = sys.argv[1:]
    if len(args) >= 2:
        # 旧单语言调用（兼容）：lang_dir out_path，文件名按 code 规则
        lang_dir, out_path = args[0], args[1]
        code = os.path.basename(os.path.normpath(lang_dir))
        if not out_path.endswith(".json"):
            os.makedirs(out_path, exist_ok=True)
            out_path = os.path.join(out_path, out_name_for(code))
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        generate_one(lang_dir, code, out_path)
        return
    if len(args) == 1:
        # 单语言目录：输出到同目录规则文件名（在给定输出路径的父目录语境少见，按语法目录输出）
        lang_dir = args[0]
        code = os.path.basename(os.path.normpath(lang_dir))
        os.makedirs(out_dir, exist_ok=True)
        generate_one(lang_dir, code, os.path.join(out_dir, out_name_for(code)))
        return
    # 批量：zhc/lang-packs/*（含 lang_info.toml 者）
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.isdir(packs_root):
        print(f"语言包根不存在：{packs_root}")
        sys.exit(1)
    langs = sorted(d for d in os.listdir(packs_root)
                   if os.path.isdir(os.path.join(packs_root, d)))
    done = 0
    for code in langs:
        lang_dir = os.path.join(packs_root, code)
        if lang_info_ext(lang_dir) is None:
            continue
        generate_one(lang_dir, code, os.path.join(out_dir, out_name_for(code)))
        done += 1
    print(f"批量完成：{done} 个语言包 → {out_dir}")


if __name__ == "__main__":
    main()
