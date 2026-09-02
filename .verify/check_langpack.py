#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""教程代码 ↔ 词表双向一致性检查（建议 E2 重写版）。

v1 缺陷修复：
  - 硬编码绝对路径 → 脚本自定位（CI 可移植）；
  - 教程自定义标识符（变量/函数/类/参数名等）误报「缺词」→ 按 zhc 豁免语义
    收集声明名后剔除（与转译器「声明位置不替换」对齐），残留才是疑似漏词；
  - 单行正则剔注释/字符串 → 字符级状态机（多行感知，支持三引号与块注释）。

用法：python3 .verify/check_langpack.py [--gate] [--usage-top N]
输出三部分：
  ① 疑似漏词（教程非声明 token 不在词表；= 扩展方法调用等自定义成员，人工确认）
  ② 词表 0 使用（keywords 语法词 / stdlib API 词；语言包覆盖官方全集，
     0 使用 ≠ 死词——教学子集有意为之，供特性矩阵与后续章节规划参考）
  ③ 汇总（词表规模 / 教程 token 数 / 疑似漏词数）
--gate：疑似漏词非空时退出码 1（acceptance 段 16 硬门禁用）。
"""
import argparse
import pathlib
import re
import tomllib

HERE = pathlib.Path(__file__).resolve().parent
BASE = HERE.parent                      # 仓库根（本脚本位于 .verify/）
REPO_LANG = BASE / "zhc" / "lang-packs" / "zh"
VERIFY_SRC = HERE / "src"

CJK_RE = re.compile(r"[\u4e00-\u9fff][\u4e00-\u9fff0-9_]*")


# ---------- 字符级剔注释/字符串（多行感知） ----------
def strip_code(text: str) -> str:
    out = []
    i, n = 0, len(text)
    state = "code"                      # code | str | triple | line_c | block_c
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if state == "code":
            if ch == "/" and nxt == "/":
                state = "line_c"; i += 2; continue
            if ch == "/" and nxt == "*":
                state = "block_c"; i += 2; continue
            if ch == '"':
                if text[i:i + 3] == '"""':
                    state = "triple"; i += 3; out.append('"""'); continue
                state = "str"; i += 1; out.append('""'); continue
            if ch == "'":
                j = i + 1               # 字符字面量 'x' / r'x'
                while j < n:
                    if text[j] == "\\":
                        j += 2; continue
                    if text[j] == "'":
                        break
                    j += 1
                i = min(j + 1, n); out.append("''"); continue
            out.append(ch); i += 1
        elif state == "line_c":
            if ch == "\n":
                state = "code"; out.append(ch)
            i += 1
        elif state == "block_c":
            if ch == "*" and nxt == "/":
                state = "code"; i += 2
            else:
                i += 1
        elif state == "str":
            if ch == "\\":
                i += 2; continue
            if ch == '"':
                state = "code"
            i += 1
        elif state == "triple":
            if text[i:i + 3] == '"""':
                state = "code"; i += 3
            else:
                i += 1
    return "".join(out)


# ---------- 声明名收集（与 zhc 豁免语义对齐：声明位置不替换） ----------
DECL_PAT = re.compile(
    r"(?:^|[^\u4e00-\u9fffA-Za-z])(?P<kw>让|可变|常量|变量|函数|类|结构体|接口|枚举|类型|宏|macro)"
    r"\s+(?P<name>[\u4e00-\u9fff][\u4e00-\u9fff0-9_]*)")
IMPORT_PAT = re.compile(r"导入[^\n]*?\{([^}]+)\}")
PARAM_PAT = re.compile(r"([\u4e00-\u9fff][\u4e00-\u9fff0-9_]*!?)\s*:\s*[\u4e00-\u9fffA-Za-z_]")
GENERIC_PAT = re.compile(r"<([\u4e00-\u9fff][\u4e00-\u9fff0-9_]*(?:\s*,\s*[\u4e00-\u9fff][\u4e00-\u9fff0-9_]*)*)>")
ENUM_BLOCK = re.compile(r"枚举\s+[\u4e00-\u9fff0-9A-Za-z_]+\s*\{([^{}]*)\}")
FOR_BIND = re.compile(r"对于\s*\(\s*([\u4e00-\u9fff][\u4e00-\u9fff0-9_]*(?:\s*,\s*[\u4e00-\u9fff][\u4e00-\u9fff0-9_]*)*)\s+in\s")
TUPLE_BIND = re.compile(r"(?:让|可变|常量)\s*\(([^)]*)\)")
PKG_PAT = re.compile(r"包\s+([\u4e00-\u9fff][\u4e00-\u9fff0-9_]*(?:\.[\u4e00-\u9fff][\u4e00-\u9fff0-9_]*)*)")
CASE_BIND = re.compile(r"情况[^(]*\(([^)]*)\)")
LAMBDA_BIND = re.compile(r"\{([^{}]*?)\s*=>")


def _cjk_parts(text: str) -> set:
    return set(CJK_RE.findall(text))


def decl_names(code: str) -> set:
    names = set()
    for m in DECL_PAT.finditer(code):       # 声明关键字后第一个标识符
        names.add(m.group("name"))
    for m in IMPORT_PAT.finditer(code):     # 导入别名 标准集合.{向量}
        names.update(_cjk_parts(m.group(1)))
    for m in PARAM_PAT.finditer(code):      # 参数/属性声明 名[:!]: 类型
        names.add(m.group(1).rstrip("!"))
    for m in GENERIC_PAT.finditer(code):    # 类型参数 类 盒子<T>
        names.update(_cjk_parts(m.group(1)))
    for m in ENUM_BLOCK.finditer(code):     # 枚举成员 枚举 方向 { 上 | 下 }
        names.update(_cjk_parts(m.group(1)))
    for m in FOR_BIND.finditer(code):       # 循环变量 对于 (分 in 成绩)
        names.update(_cjk_parts(m.group(1)))
    for m in TUPLE_BIND.finditer(code):     # 元组解构 让 (最小, 最大) = ...
        names.update(_cjk_parts(m.group(1)))
    for m in PKG_PAT.finditer(code):        # 包名 包 图书.管理
        names.update(_cjk_parts(m.group(1)))
    for m in CASE_BIND.finditer(code):      # 模式绑定 情况 通知.文本(文字)
        names.update(_cjk_parts(m.group(1)))
    for m in LAMBDA_BIND.finditer(code):    # 闭包参数 { 累积, 分 => ... }
        names.update(_cjk_parts(m.group(1)))
    return names


def load_table() -> tuple:
    """返回 (词表全集, keywords 词, api 词)。api = stdlib + module_paths。"""
    words, kw_words, api_words = set(), set(), set()
    for fn, kind in [("keywords.toml", "kw"), ("stdlib.toml", "api"),
                     ("module_paths.toml", "api")]:
        p = REPO_LANG / fn
        if not p.exists():
            continue
        with open(p, "rb") as f:
            data = tomllib.load(f)
        for section in data.values():
            if isinstance(section, dict):
                words.update(section.keys())
                (kw_words if kind == "kw" else api_words).update(section.keys())
    return words, kw_words, api_words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", action="store_true", help="疑似漏词非空时退出码 1")
    ap.add_argument("--usage-top", type=int, default=0,
                    help="0 使用清单最多打印条数（0 = 不打印）")
    args = ap.parse_args()

    words, kw_words, api_words = load_table()
    files = sorted(VERIFY_SRC.glob("*.zc"))
    if not files:
        raise SystemExit(f"未找到教程代码块：{VERIFY_SRC}")

    declared = set()                    # 第一遍：声明名（跨文件）
    bodies = []
    for f in files:
        code = strip_code(f.read_text(encoding="utf-8"))
        bodies.append(code)
        declared |= decl_names(code)

    used = set()                        # 第二遍：全部非声明 token
    origins = {}                        # 词 → 首个出处（文件:行:原文）
    for f, code in zip(files, bodies):
        for lineno, line in enumerate(code.splitlines(), 1):
            for tok in set(CJK_RE.findall(line)):
                used.add(tok)
                origins.setdefault(tok, f"{f.name}:{lineno}: {line.strip()[:40]}")

    missing = sorted(w for w in used if w not in words and w not in declared)
    unused_kw = sorted(kw_words - used)
    unused_api = sorted(api_words - used)

    print(f"教程代码块文件：{len(files)}")
    print(f"教程 token 数（剔注释/字符串/声明名后）：{len(used)}")
    print(f"词表规模：{len(words)}（keywords {len(kw_words)} / API {len(api_words)}）")
    print(f"疑似漏词（非声明 token 不在词表）：{len(missing)}")
    for w in missing:
        print(f"  {w}  ← {origins.get(w, '?')}")
    print(f"词表 0 使用：keywords {len(unused_kw)} 个 / API {len(unused_api)} 个"
          "（词表覆盖官方全集；0 使用 = 教程子集有意为之，供规划参考）")
    if args.usage_top:
        for w in unused_kw[: args.usage_top]:
            print(f"  未用语法词: {w}")
        for w in unused_api[: args.usage_top]:
            print(f"  未用 API 词: {w}")
    if args.gate and missing:
        raise SystemExit(f"疑似漏词 {len(missing)} 个（--gate 门禁）")


if __name__ == "__main__":
    main()
