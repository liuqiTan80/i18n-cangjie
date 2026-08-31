#!/usr/bin/env python3
"""zhc 语法高亮生成脚本（设计 §9.1）：语言包 → tmLanguage JSON。

原则：关键字/宏/类型/内置分节注入正则，映射表与高亮永不漂移——
每次语言包改动后重跑本脚本即可（扩展构建时自动调用）。

关键实现点：
- 中文词边界不能用 \\b（\\w 仅 ASCII）：用 `(?<![\\p{L}\\p{N}_])` 前后断言，
  使 `让年龄` 中的 `让` 不匹配、独立 `让 ` 匹配；
- 宏（[宏] 节）以 @ 前缀匹配（@ 后只查宏表，与转译器一致）；
- 多词键（"否则如果"）按长度降序合并，长词优先；
- 字符串/注释模式前置，避免其中关键字被误高亮。
"""
import json
import os
import re
import sys

# ---- 语言包 TOML 极简解析（结构固定：节 + "键" = "值"）----

def parse_pack_toml(path):
    """返回 {节名: [(母语键, 官方值), ...]}；# 注释与空行忽略。"""
    sections = {}
    cur = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r'^\["(.+)"\]$', line)
            if m:
                cur = m.group(1)
                sections.setdefault(cur, [])
                continue
            m = re.match(r'^"(.+)"\s*=\s*"(.+)"$', line)
            if m and cur is not None:
                sections[cur].append((m.group(1), m.group(2)))
    return sections


# ---- 正则生成 ----

def esc_re(word):
    """正则转义 + 丢弃危险片段（词内不应有未转义特殊字符）。"""
    return re.escape(word)


def word_class(names):
    """词列表 → 交替正则（长词优先；中文边界断言）。"""
    if not names:
        return None
    ordered = sorted(names, key=len, reverse=True)
    body = "|".join(esc_re(w) for w in ordered)
    return r"(?<![\p{L}\p{N}_])(?:%s)(?![\p{L}\p{N}_])" % body


def macro_class(names):
    """宏列表 → @ 前缀交替正则。"""
    if not names:
        return None
    ordered = sorted(names, key=len, reverse=True)
    body = "|".join(esc_re(w) for w in ordered)
    return r"@(?:%s)(?![\p{L}\p{N}_])" % body


# ---- tmLanguage 组装 ----

def build_tm(lang_pack_dir):
    kw = parse_pack_toml(os.path.join(lang_pack_dir, "keywords.toml"))
    st = parse_pack_toml(os.path.join(lang_pack_dir, "stdlib.toml"))

    # 关键字节 → 作用域名（[宏] 独立为 @ 宏；其余节合并为关键字）
    section_scope = {
        "声明": "keyword.declaration",
        "控制流": "keyword.control",
        "运算符": "keyword.operator",
        "修饰": "keyword.modifier",
        "属性访问器": "keyword.other",
        "宏定义": "keyword.macro",
    }
    key_patterns = []
    for section, scope in section_scope.items():
        names = [k for (k, _) in kw.get(section, [])]
        rx = word_class(names)
        if rx:
            key_patterns.append({"name": scope, "match": rx})

    # [宏] 节 → @ 前缀宏
    macro_patterns = []
    macro_names = [k for (k, _) in kw.get("宏", [])]
    rx = macro_class(macro_names)
    if rx:
        macro_patterns.append({"name": "keyword.macro", "match": rx})

    # stdlib 标识符：官方值首字母大写 → 类型；真/假 → 常量；其余 → 内置函数
    ids = st.get("标识符", [])
    types = [k for (k, v) in ids if v and v[0].isupper()]
    constants = [k for (k, v) in ids if v in ("true", "false")]
    builtins = [k for (k, v) in ids if k not in types and k not in constants]
    type_patterns = []
    rx = word_class(types)
    if rx:
        type_patterns.append({"name": "support.type", "match": rx})
    rx = word_class(constants)
    if rx:
        type_patterns.append({"name": "constant.language", "match": rx})
    rx = word_class(builtins)
    if rx:
        type_patterns.append({"name": "support.function", "match": rx})

    repo = {
        "comments": {
            "patterns": [
                {"name": "comment.line.double-slash", "match": r"//.*$"},
                {"name": "comment.block", "begin": r"/\*", "end": r"\*/"},
            ]
        },
        "strings": {
            "patterns": [
                {"name": "string.quoted.double", "begin": r'"', "end": r'"',
                 "patterns": [{"name": "constant.character.escape", "match": r'\\.'}]},
                {"name": "string.quoted.single", "begin": r"r'", "end": r"'"},  # 原生字符
            ]
        },
        "numbers": {
            "patterns": [
                {"name": "constant.numeric", "match": r"\b(?:0[xX][0-9a-fA-F_]+|\d[\d_]*)\b"},
            ]
        },
        "keywords": {"patterns": key_patterns} if key_patterns else {"patterns": []},
        "macros": {"patterns": macro_patterns} if macro_patterns else {"patterns": []},
        "types": {"patterns": type_patterns} if type_patterns else {"patterns": []},
    }

    tm = {
        "name": "中文仓颉（zhc 方言）",
        "scopeName": "source.zc",
        "fileTypes": ["zc"],
        "patterns": [
            {"include": "#comments"},
            {"include": "#strings"},
            {"include": "#numbers"},
            {"include": "#macros"},
            {"include": "#keywords"},
            {"include": "#types"},
        ],
        "repository": repo,
    }
    return tm


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    lang_pack = os.environ.get("ZHC_LANG_PACKS", os.path.join(here, "..", "lang-packs"))
    pack_dir = os.path.join(lang_pack, "zh")
    out = os.path.join(here, "vscode-extension", "syntaxes", "cangjie-zh.tmLanguage.json")
    if len(sys.argv) > 1:
        pack_dir = sys.argv[1]
    if len(sys.argv) > 2:
        out = sys.argv[2]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    kw = parse_pack_toml(os.path.join(pack_dir, "keywords.toml"))
    st = parse_pack_toml(os.path.join(pack_dir, "stdlib.toml"))
    tm = build_tm(pack_dir)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(tm, f, ensure_ascii=False, indent=2)
    n_key = sum(len(v) for s, v in kw.items() if s != "宏")
    n_mac = len(kw.get("宏", []))
    ids = st.get("标识符", [])
    n_type = len([1 for (k, v) in ids if v and v[0].isupper()])
    print(f"生成 {out}")
    print(f"  关键字 {n_key} 条；@宏 {n_mac} 条；类型 {n_type} 条（来自语言包，与映射同步）")
    print("  完成：运行扩展即可加载语法高亮（TextMate/Oniguruma 支持 \\p{L} 边界）。")


if __name__ == "__main__":
    main()
