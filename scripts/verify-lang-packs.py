#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify-lang-packs.py —— 语言包跨语言校验（无 SDK 依赖，Python ≥3.8）。

镜像 zhc `mapping check` 的五项门禁口径（见 zhc/src/mapping.cj mappingCheck），
供无仓颉 SDK 的环境（贡献者本机 / libs-ci）快速回归；SDK 环境仍以
`zhc mapping check` 为准（本脚本通过 = 高置信，两者互为回归测试）。

检查项（逐语言包）：
  1. lang_info.toml 存在且含 [语言包] 的 代码/名称/扩展名/版本 五键之一组合
     （代码/扩展名必须有值）；
  2. TOML 子集合法 + 节内无重复键（keywords/module_paths/stdlib/ui/errors）；
  3. keywords.toml 跨节同键不同值（[宏] 节独立不合并，与 mapping.cj 口径一致）；
  4. stdlib 标识符/模块路径键不得撞关键字键（别名与关键字碰撞）；
     宏键不得撞关键字键；
  5. 跨语言一致性：keywords + 宏 的官方值去重覆盖集全仓一致（允许多对一
     同义词，如 是/属于 → is）。

用法：python3 scripts/verify-lang-packs.py
退出码：0 = 全部通过；1 = 有失败项。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKS = os.path.join(ROOT, "zhc", "lang-packs")
SECTION_RE = re.compile(r'^\[([^\]]+)\]\s*$')
KV_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
BARE_RE = re.compile(r'^([^\[#"\s][^=\[]*)\s*=\s*')  # 无引号裸键（TOML 子集禁止）


def parse_toml_subset(path):
    """按 zhc parseToml 子集解析：[节] + "k" = "v"，# 注释。

    返回 (节 → 有序 [(键, 值)], 错误列表)。"""
    tables = {}
    errors = []
    section = None
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    for i, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = SECTION_RE.match(line)
        if m:
            section = m.group(1).strip('"')
            tables.setdefault(section, [])
            continue
        if BARE_RE.match(line):
            errors.append("%s:%d 键未加引号（TOML 子集要求 \"键\" = \"值\"）：%s"
                          % (path, i, line[:50]))
            continue
        m = KV_RE.match(line)
        if not m:
            errors.append("%s:%d 无法解析：%s" % (path, i, line[:50]))
            continue
        if section is None:
            errors.append("%s:%d 键值出现在节声明之前" % (path, i))
            continue
        tables[section].append((m.group(1), m.group(2)))
    return tables, errors


def main():
    if not os.path.isdir(PACKS):
        print("未找到语言包目录：%s" % PACKS)
        return 1
    codes = sorted(d for d in os.listdir(PACKS)
                   if os.path.isdir(os.path.join(PACKS, d))
                   and not d.startswith("."))
    if not codes:
        print("语言包目录为空")
        return 1
    fails = 0
    coverage = {}   # 代码 → keywords+宏 官方值集合
    for code in codes:
        base = os.path.join(PACKS, code)
        fail = 0
        print("--- %s（lang-packs/%s）---" % (code, code))
        # 1. lang_info
        info = os.path.join(base, "lang_info.toml")
        if not os.path.exists(info):
            print("  [失败] 缺少 lang_info.toml")
            fail += 1
        else:
            tables, errors = parse_toml_subset(info)
            errs = list(errors)
            lang = dict(tables.get("语言包", []))
            for must in ("代码", "扩展名"):
                if not lang.get(must):
                    errs.append("lang_info.toml 缺少 \"%s\"" % must)
            if lang.get("代码", code) != code:
                errs.append("lang_info 代码 %s ≠ 目录名 %s" % (lang.get("代码"), code))
            if errs:
                fail += 1
                print("  [失败] lang_info.toml：")
                for e in errs:
                    print("      " + e)
        # 2. TOML 合法性 + 重复键
        tables_all = {}
        for fn in ("keywords.toml", "module_paths.toml", "stdlib.toml",
                   "ui.toml", "errors.toml"):
            p = os.path.join(base, fn)
            if not os.path.exists(p):
                continue
            tables, errors = parse_toml_subset(p)
            for sec, kvs in tables.items():
                seen = {}
                for k, _v in kvs:
                    if k in seen:
                        errors.append("%s [%s] 重复键 \"%s\"（首次见 %s）"
                                      % (fn, sec, k, seen[k]))
                    seen[k] = "已登记"
            if errors:
                fail += 1
                print("  [失败] %s：" % fn)
                for e in errors:
                    print("      " + e)
            tables_all[fn] = tables
        # 3. keywords 跨节同键不同值（宏节独立）
        kw = tables_all.get("keywords.toml", {})
        seen = {}
        for sec in sorted(kw):
            if sec == "宏":
                continue
            for k, v in kw[sec]:
                if k in seen and seen[k][1] != v:
                    print("  [失败] 跨节同键不同值：%s（%s = %s vs %s = %s）"
                          % (k, seen[k][0], seen[k][1], sec, v))
                    fail += 1
                seen[k] = (sec, v)
        # 4. 别名/宏不撞关键字
        kw_keys = set(seen)
        macro_keys = {k for k, _v in kw.get("宏", [])}
        stdlib = tables_all.get("stdlib.toml", {})
        alias_keys = set()
        for sec in ("标识符", "模块路径"):
            for k, _v in stdlib.get(sec, []):
                alias_keys.add(k)
        hits = sorted((alias_keys | macro_keys) & kw_keys)
        if hits:
            fail += 1
            print("  [失败] 别名/宏与关键字碰撞：%s" % "、".join(hits))
        # 5. 官方值覆盖集（keywords 全节 + 宏）
        vals = {v for kvs in kw.values() for _k, v in kvs}
        coverage[code] = vals
        n_kw = len(seen) + len(macro_keys)
        n_std = sum(len(stdlib.get(s, []))
                    for s in ("标识符", "模块路径"))
        n_mp = len(tables_all.get("module_paths.toml", {}).get("模块路径", []))
        if fail == 0:
            print("  通过：关键字 %d / 标准库 %d / 模块路径 %d / 官方值覆盖 %d"
                  % (n_kw, n_std, n_mp, len(vals)))
        else:
            print("  [失败] 共 %d 项" % fail)
        fails += fail
    # 跨语言覆盖集一致性
    if len({frozenset(v) for v in coverage.values()}) > 1:
        fails += 1
        print("【跨语言覆盖集不一致】各包 keywords+宏 官方值集合不同：")
        base_set = None
        for code in sorted(coverage):
            if base_set is None or len(coverage[code]) > len(base_set):
                base_set = coverage[code]
        for code in sorted(coverage):
            miss = sorted(base_set - coverage[code])
            extra = sorted(coverage[code] - base_set)
            if miss or extra:
                print("    %s：缺 %s；多 %s"
                      % (code,
                         "、".join(miss) if miss else "无",
                         "、".join(extra) if extra else "无"))
    if fails == 0:
        print("=== verify-lang-packs：%d 个语言包全部通过 ===" % len(codes))
        return 0
    print("=== verify-lang-packs：%d 项失败 ===" % fails)
    return 1


if __name__ == "__main__":
    sys.exit(main())
