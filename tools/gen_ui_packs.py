#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""语言包 ui.toml 生成器（en/ru 全量档 + zh 特殊 + ja/de/es/fr/ko demo 档）。

- key 集从 zhc/src/*.cj 的 uiText/uiTextF 实参重提取（排除 *_test.cj 与定义行），
  避免硬编码文案与语言包漂移：新增/改写 UI 串后重跑本脚本即同步各包；
- 全量档（en/ru）：校验 dict 与 key 集完全一致（无缺漏/无多余），不一致即报错退出；
- demo 档（ja/de/es/fr/ko）：只允许子集（多余报错），缺失键生成时回退 EN（再回退
  zh 原文），头部注明覆盖率——补翻编辑 ui_translations_<code>.py 后重跑即可；
- zh 不建 ["界面消息"] 表（key = zh 原文模板，缺键回退即原文）；
- zh/ru 提供 ["测试输出"] 词典（键 = cjpm test 官方英文锚点，printTestOutput 逐行替换）；
  en 及 demo 档无测试词典（英文锚点原样）。

用法：python3 tools/gen_ui_packs.py [--out-dir 目录]
默认直接写 zhc/lang-packs/{en,ru,zh}/ui.toml；--out-dir 供 acceptance 段 13
防漂移 diff（重生成到临时目录比较，不一致即报失败）。
"""
import re, glob, sys, os, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui_translations_en import EN
from ui_translations_ru import RU, TEST_RU
from ui_translations_ja import JA
from ui_translations_de import DE
from ui_translations_es import ES
from ui_translations_fr import FR
from ui_translations_ko import KO

# demo 档语言包：部分覆盖（缺键生成时回退 EN，再回退 zh 原文）。
# 校验规则：demo 表只允许“子集”（多余键报错），缺失键不报错但输出覆盖率——
# 补翻后重跑本脚本，覆盖率与生成物同步更新。
DEMO_PACKS = (("ja", JA), ("de", DE), ("es", ES), ("fr", FR), ("ko", KO))

TEST_ZH = {
    # 值统一中文全角标点（与 zhc 界面消息/验收断言基线一致）
    "[ FAILED ] CASE:": "[ 失败 ] 用例：",
    "[ PASSED ] CASE:": "[ 通过 ] 用例：",
    "Project tests finished": "项目测试完成",
    "Summary: TOTAL:": "汇总：总计：",
    "PASSED:": "通过：",
    "SKIPPED:": "跳过：",
    "ERROR:": "错误：",
    "FAILED:": "失败：",
    "Error: cjpm test failed": "错误：cjpm test 失败",
    "cjpm test success": "cjpm test 成功",
}

SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "zhc", "src"))
PACKS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "zhc", "lang-packs"))


def extract_keys():
    pat = re.compile(r'(?<![\w.])uiText(?:F)?\("((?:[^"\\]|\\.)*)"')
    keys = set()
    # 间接键：let ERR_X = "…" 声明 + 被 uiText/uiTextF(<IDENT>) 变量引用
    decl_pat = re.compile(r'^let ([A-Za-z_][A-Za-z0-9_]*) = "((?:[^"\\]|\\.)*)"')
    ref_pat = re.compile(r'(?<![\w.])uiText(?:F)?\(([A-Za-z_][A-Za-z0-9_]*)\)')
    for f in glob.glob(os.path.join(SRC, "*.cj")):
        if f.endswith("_test.cj"):
            continue
        text = open(f, encoding="utf-8").read()
        decls = {}
        for ln in text.split("\n"):
            m = decl_pat.match(ln)
            if m:
                decls[m.group(1)] = m.group(2)
        for m in pat.finditer(text):
            line_start = text.rfind("\n", 0, m.start()) + 1
            line = text[line_start:m.start()]
            if "func uiText" in line:
                continue
            keys.add(unescape_cj(m.group(1)))
        for m in ref_pat.finditer(text):
            if m.group(1) in decls:
                keys.add(unescape_cj(decls[m.group(1)]))
    return keys


def unescape_cj(s):
    """把 Cangjie 源码字面量的转义序列反解为运行时实际值（键须与 uiText
    实参的运行时值一致，否则 ui.toml 键永不命中；实测覆盖 \\" 与 \\\\）。"""
    return re.sub(r"\\(.)", r"\1", s)


def toml_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def dump_table(f, title, d, sorted_keys):
    f.write(f'["{toml_escape(title)}"]\n')
    for k in sorted_keys:
        v = d[k]
        f.write(f'"{toml_escape(k)}" = "{toml_escape(v)}"\n')


def main():
    out_dir = PACKS
    if len(sys.argv) > 2 and sys.argv[1] == "--out-dir":
        out_dir = sys.argv[2]
    keys = extract_keys()
    print("代码提取 key 数:", len(keys))
    errs = 0
    for name, d in (("EN", EN), ("RU", RU)):
        miss = keys - set(d.keys())
        extra = set(d.keys()) - keys
        if miss or extra:
            print(f"[FAIL] {name} 缺失 {len(miss)}: {sorted(miss)[:5]}")
            print(f"[FAIL] {name} 多余 {len(extra)}: {sorted(extra)[:5]}")
            errs += 1
        else:
            print(f"{name} 全覆盖 ✓（{len(d)} 条）")
    if errs:
        sys.exit(1)

    os.makedirs(os.path.join(out_dir, "en"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "ru"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "zh"), exist_ok=True)

    # en：["界面消息"] 全表（182）；无测试词典（英文锚点原样）
    with open(os.path.join(out_dir, "en", "ui.toml"), "w", encoding="utf-8") as f:
        f.write("# ui.toml —— en 语言包界面消息（引擎自国际化完整表；改动请跑 tools/gen_ui_packs.py 防漂移）\n")
        f.write("# 键 = zh 中文模板串（含 {n} 占位，位置须与键一致）；缺键回退为键本身。\n")
        dump_table(f, "界面消息", EN, sorted(keys))
    print("en/ui.toml 写入 ✓")

    # ru：["界面消息"] 全表 + ["测试输出"] 演示级词典
    with open(os.path.join(out_dir, "ru", "ui.toml"), "w", encoding="utf-8") as f:
        f.write("# ui.toml —— ru 语言包 v0.2（演示级界面消息全表；改动请跑 tools/gen_ui_packs.py 防漂移）\n")
        dump_table(f, "界面消息", RU, sorted(keys))
        dump_table(f, "测试输出", TEST_RU, sorted(TEST_RU.keys()))
    print("ru/ui.toml 写入 ✓")

    # zh：不建 ["界面消息"]（key = 中文模板，缺键回退即原文）；仅 ["测试输出"] 词典
    with open(os.path.join(out_dir, "zh", "ui.toml"), "w", encoding="utf-8") as f:
        f.write("# ui.toml —— zh 语言包：界面消息不建表（key = 中文模板串本身，缺键回退即原文）。\n")
        f.write('# ["测试输出"] 词典把 cjpm test 的官方英文锚点替换为中文（printTestOutput）。\n')
        dump_table(f, "测试输出", TEST_ZH, sorted(TEST_ZH.keys()))
    print("zh/ui.toml 写入 ✓")

    # demo 档语言包：部分覆盖 + EN 回退填充（缺键先取 EN，EN 也没有则 zh 原文）
    for code, d in DEMO_PACKS:
        miss = keys - set(d.keys())
        extra = set(d.keys()) - keys
        if extra:
            print(f"[FAIL] {code.upper()} 多余 {len(extra)}: {sorted(extra)[:5]}")
            errs += 1
            continue
        effective = {}
        for k in sorted(keys):
            effective[k] = d.get(k) or EN.get(k) or k
        cov = 100.0 * len(d) / len(keys) if keys else 0.0
        os.makedirs(os.path.join(out_dir, code), exist_ok=True)
        with open(os.path.join(out_dir, code, "ui.toml"), "w", encoding="utf-8") as f:
            f.write(f"# ui.toml —— {code} 语言包界面消息（demo 档：部分覆盖 {cov:.0f}%，"
                    f"缺键已回退 EN；补翻编辑 ui_translations_{code}.py 后重跑本脚本）\n")
            dump_table(f, "界面消息", effective, sorted(keys))
        print(f"{code}/ui.toml 写入 ✓（demo 档覆盖 {cov:.0f}%：{len(d)}/{len(keys)}，其余回退 EN）")
    print("全部完成")


if __name__ == "__main__":
    main()
