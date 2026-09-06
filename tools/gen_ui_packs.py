#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""语言包 ui.toml 生成器（档位自动发现 + 翻译表约定优于配置；P-4 新语言零脚本化）。

- key 集从 zhc/src/*.cj 的 uiText/uiTextF 实参重提取（排除 *_test.cj 与定义行），
  避免硬编码文案与语言包漂移：新增/改写 UI 串后重跑本脚本即同步各包；
- 翻译表自动发现（P-4）：tools/ui_translations_<code>.py（模块内字典 = <CODE>，
  可选 TEST_<CODE> 测试词典）——新增语言只需新建该文件，无需改动本生成器；
- 档位判定读语言包 lang_info.toml「档位」字段（schema 1，doctor/mapping check 同源）：
  - full/standard 档：校验 dict 与 key 集完全一致（无缺漏/无多余），不一致即报错退出；
  - demo 档（含未声明，向后兼容）：只允许子集（多余报错），缺失键生成时回退 EN
    （再回退 zh 原文），头部注明翻译覆盖率——补翻编辑翻译表后重跑即可；
- zh 不建 ["界面消息"] 表（key = zh 原文模板，缺键回退即原文）；
- 测试词典（["测试输出"]）机制：翻译表带 TEST_<CODE> 字典即写入（zh/ru 内置，
  官方英文锚点逐行替换；无测试词典的语言英文锚点原样）。

用法：
  python3 tools/gen_ui_packs.py [--out-dir 目录]     默认直接写 zhc/lang-packs/*/ui.toml
                                                      --out-dir 供 acceptance 段 13
                                                      防漂移 diff（重生成比较，不一致即报失败）
  python3 tools/gen_ui_packs.py --scaffold <代码>    输出 tools/ui_translations_<代码>.py
                                                      翻译表模板（键全列、值空 = 未翻译）
"""
import re, glob, sys, os, importlib.util

SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "zhc", "src"))
PACKS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "zhc", "lang-packs"))
TRANSL_DIR = os.path.dirname(os.path.abspath(__file__))

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


def pack_tier(code):
    """读语言包 lang_info.toml「档位」字段（schema 1）；未声明返回空串（按 demo 处理）。"""
    p = os.path.join(PACKS, code, "lang_info.toml")
    if not os.path.exists(p):
        return None
    for raw in open(p, encoding="utf-8"):
        m = re.match(r'^"档位"\s*=\s*"([^"]+)"', raw.strip())
        if m:
            return m.group(1)
    return ""


def load_translation_module(code):
    """P-4 约定优于配置：动态加载 tools/ui_translations_<code>.py。

    返回 (字典 <CODE>, TEST_<CODE> 字典或 None)；文件缺失返回 None。
    约定：模块内主字典名 = 代码大写（ja→JA），测试词典名 = TEST_<大写>（可选）。
    """
    path = os.path.join(TRANSL_DIR, f"ui_translations_{code}.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location(f"ui_translations_{code}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    d = getattr(mod, code.upper(), None)
    if not isinstance(d, dict):
        print(f"[FAIL] {path} 缺少模块级字典 {code.upper()} = {{…}}（翻译表约定）")
        sys.exit(1)
    test = getattr(mod, "TEST_" + code.upper(), None)
    return d, test


def discover_packs():
    """按 zhc/lang-packs/*/lang_info.toml 自动发现（P-4）；返回 code -> 档位。"""
    out = {}
    if not os.path.isdir(PACKS):
        return out
    for d in sorted(os.listdir(PACKS)):
        p = os.path.join(PACKS, d, "lang_info.toml")
        if os.path.exists(p):
            tier = pack_tier(d)
            if tier is None:
                continue
            out[d] = tier
    return out


def write_ui_pack(code, d, test, keys, tier, out_dir, en_full):
    """按档位生成单语言 ui.toml；返回错误数（full 档缺漏/任何档多余计 1，不写文件）。"""
    errs = 0
    if tier in ("full", "standard"):
        miss = keys - set(d.keys())
        extra = set(d.keys()) - keys
        if miss or extra:
            print(f"[FAIL] {code.upper()} 缺失 {len(miss)}: {sorted(miss)[:5]}")
            print(f"[FAIL] {code.upper()} 多余 {len(extra)}: {sorted(extra)[:5]}")
            return 1
        effective = d
        note = f"全覆盖（{len(d)} 条）"
    else:
        extra = set(d.keys()) - keys
        if extra:
            print(f"[FAIL] {code.upper()} 多余 {len(extra)}: {sorted(extra)[:5]}")
            return 1
        # demo 档：缺键先取 EN，EN 也没有则 zh 原文；翻译数 = 值非空的键数
        effective = {}
        for k in sorted(keys):
            effective[k] = d.get(k) or en_full.get(k) or k
        translated = sum(1 for k in keys if d.get(k))
        cov = 100.0 * translated / len(keys) if keys else 0.0
        note = f"demo 档覆盖 {cov:.1f}%（{translated}/{len(keys)} 已译，其余回退 EN）"
    os.makedirs(os.path.join(out_dir, code), exist_ok=True)
    with open(os.path.join(out_dir, code, "ui.toml"), "w", encoding="utf-8") as f:
        f.write(f"# ui.toml —— {code} 语言包界面消息（{note}；改动请跑 tools/gen_ui_packs.py 防漂移）\n")
        dump_table(f, "界面消息", effective, sorted(keys))
        if test:
            dump_table(f, "测试输出", test, sorted(test.keys()))
    print(f"{code}/ui.toml 写入 ✓（{note}）")
    return errs


def write_scaffold_template(code, keys):
    """输出 tools/ui_translations_<code>.py 翻译表模板（P-4）：键全列、值空 = 未翻译。"""
    out = os.path.join(TRANSL_DIR, f"ui_translations_{code}.py")
    if os.path.exists(out):
        print(f"[FAIL] 翻译表已存在：{out}（编辑它，勿覆盖）")
        return 1
    upper = code.upper()
    with open(out, "w", encoding="utf-8") as f:
        f.write(f"#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n"
                f'"""{code} 界面消息翻译表（python3 tools/gen_ui_packs.py --scaffold {code} 生成模板）。\n\n'
                f"键 = zh 中文界面模板串（运行时形态，含 {{n}} 占位，位置须与键一致）；\n"
                f"值 = {code} 翻译；空串 = 未翻译（生成 ui.toml 时回退 EN，再回退 zh 原文）。\n"
                f"填好后运行 python3 tools/gen_ui_packs.py：自动发现本文件并同步\n"
                f"zhc/lang-packs/{code}/ui.toml——无需改动生成器（P-4 新语言零脚本化）。\n"
                f'"""\n'
                f"# 已翻译键数：0/{len(keys)}（自动统计，勿手改；值非空即已翻译）\n"
                f"{upper} = {{\n")
        for k in sorted(keys):
            f.write(f'    "{toml_escape(k)}": "",\n')
        f.write("}\n")
    print(f"翻译表模板已生成：{out}（{len(keys)} 键待翻译）")
    print(f"下一步：① zhc mapping scaffold <源> {code} 建语言包骨架（含 lang_info.toml 档位）")
    print(f"       ② 编辑 {os.path.basename(out)} 填翻译（空串自动回退 EN）")
    print(f"       ③ 运行 python3 tools/gen_ui_packs.py 生成 {code}/ui.toml")
    return 0


def main():
    args = sys.argv[1:]
    if args and args[0] == "--scaffold":
        if len(args) < 2 or not re.match(r"^[a-z]{2,8}$", args[1]):
            print("用法：python3 tools/gen_ui_packs.py --scaffold <代码>（如 vi）")
            return 1
        code = args[1]
        keys = extract_keys()
        return write_scaffold_template(code, keys)
    out_dir = PACKS
    if len(args) >= 2 and args[0] == "--out-dir":
        out_dir = args[1]
    keys = extract_keys()
    print("代码提取 key 数:", len(keys))

    # zh 特殊：界面消息不建表 + 测试词典（独立处理，不走档位循环）
    os.makedirs(os.path.join(out_dir, "zh"), exist_ok=True)
    with open(os.path.join(out_dir, "zh", "ui.toml"), "w", encoding="utf-8") as f:
        f.write("# ui.toml —— zh 语言包：界面消息不建表（key = 中文模板串本身，缺键回退即原文）。\n")
        f.write('# ["测试输出"] 词典把 cjpm test 的官方英文锚点替换为中文（printTestOutput）。\n')
        dump_table(f, "测试输出", TEST_ZH, sorted(TEST_ZH.keys()))
    print("zh/ui.toml 写入 ✓（界面消息不建表，测试词典 10 条）")

    errs = 0
    tiers = discover_packs()
    # 先全量加载翻译表（demo 回退依赖 EN 全表）
    loaded = {}
    for code in sorted(tiers):
        if code == "zh":
            continue
        mod = load_translation_module(code)
        if mod is None:
            # 新语言包尚未建翻译表：跳过并提示（不失败，防第三方包拖垮主链）
            print(f"[跳过] {code} 无 tools/ui_translations_{code}.py——"
                  f"先 python3 tools/gen_ui_packs.py --scaffold {code} 生成模板")
            continue
        loaded[code] = mod
    en_full = loaded.get("en", ({}, None))[0]
    for code in sorted(tiers):
        if code == "zh" or code not in loaded:
            continue
        d, test = loaded[code]
        tier = tiers[code]
        if tier not in ("full", "standard", "demo"):
            print(f"[警告] {code} lang_info 档位未声明（schema 1 建议 full/standard/demo），按 demo 档处理")
            tier = "demo"
        errs += write_ui_pack(code, d, test, keys, tier, out_dir, en_full)
    if errs:
        sys.exit(1)
    print("全部完成")


if __name__ == "__main__":
    sys.exit(main())
