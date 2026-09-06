#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""诊断教学用例库驱动（建议 D4 + P-8 多语参数化）——目录化黄金样例回归门禁。

用法：
  python3 tools/diag_cases.py --zhc <zhc 二进制> --lang-packs <语言包目录>
         [--lang <语言代码>] [--cases <用例根目录>] [--stats <命中日志路径>] [--verbose]

目录约定（tools/diag-cases/<码名>/）：
  main.zc / main.<扩展名>   刻意写错的方言源码（语言由 ZHCLANG 决定；扩展名取
                          lang-packs/<lang>/lang_info.toml 的"扩展名"字段：
                          zh→zc、en→en、ru→rc…）
  expect.txt / expect.<扩展名>.txt
                          期望输出中的母语片段（每行一个，全部须命中）；
                          该文件同时声明「错误表已覆盖此码」：expect 缺失时
                          ②③ 跳过、仅断言 ① 编译必败（zhc 只对表内码记录
                          logHit 并本地化，未覆盖码回退官方原文；随翻译补全
                          + 补 expect 文件后断言自动全量生效）
                          zh 历史约定 expect.txt；其余语言用 expect.<扩展名>.txt
                          （expect 内 "#" 开头行为注释，不参与断言）。

每个用例断言三件事：
  1. zhc check 必须失败（错误源码不应编译通过）；
  2. 输出须包含 expect 文件每一行（防英文回退/防翻译漂移）；
  3. --stats 指定时，命中的诊断码日志须含目录码名（码名 = 目录名，
     与 zhc 的 ZHC_DIAG_STATS 埋点、tools/diag_coverage.py 同源）。

某语言未提供 main.<扩展名> 的用例自动跳过（⏭，不计失败）——语言包档位未含
教学样例属正常状态（如 ja demo 档）；全部跳过时退出码 0。
任一用例失败 → 退出码 1；全部通过 → 0。设计见 zhc-design §14.1 诊断层。
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def lang_extension(lang_packs, lang):
    """读 lang-packs/<lang>/lang_info.toml 的"扩展名"字段；缺失/解析失败返回 None。"""
    info = Path(lang_packs) / "lang-packs" / lang / "lang_info.toml"
    try:
        text = info.read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r'"扩展名"\s*=\s*"([^"]+)"', text)
    return m.group(1) if m else None


def run_case(zhc, lang_packs, lang, ext, case_dir, stats_path, verbose):
    """跑一个用例，返回 (通过?, 失败原因列表)。

    expect 文件 = 该语言「错误表已覆盖此码」的教学承诺声明：
      - expect 存在 → ②母语片段 + ③码命中全量断言；
      - expect 缺失 → 该码未入 <lang> 错误表（zhc 只对表内码记录 logHit
        并本地化，未覆盖码回退官方原文），仅断言 ① 编译必败；
        ②③ 随该语言补全翻译表 + expect 文件后自动生效。
    """
    code = case_dir.name
    main_file = case_dir / f"main.{ext}"
    fails = []

    expect_txt = case_dir / f"expect.{ext}.txt"
    if not expect_txt.exists() and ext == "zc":
        expect_txt = case_dir / "expect.txt"  # zh 历史约定
    has_expect = expect_txt.exists()

    env = dict(os.environ)
    env["ZHC_LANG_PACKS"] = str(lang_packs)
    env["ZHCLANG"] = lang
    if stats_path:
        env["ZHC_DIAG_STATS"] = str(stats_path)

    # ① 错误源码必须编译失败
    proc = subprocess.run(
        [str(zhc), "check", str(main_file)],
        cwd=str(case_dir),
        env=env,
        capture_output=True,
        text=True,
    )
    output = proc.stdout + proc.stderr
    if proc.returncode == 0:
        fails.append("错误源码竟然编译通过（zhc check 退出码 0）")
    elif has_expect:
        # ② 母语片段断言（防英文回退回归）
        for line in expect_txt.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and line not in output:
                fails.append(f"输出缺母语片段：{line}")
    elif verbose:
        print(f"    [{code}] 无 expect.{ext}.txt：该码未入 {lang} 错误表，② 跳过")

    # ③ 码命中断言（目录码名须出现在 ZHC_DIAG_STATS 日志）
    if stats_path:
        stats = Path(stats_path)
        if not stats.exists():
            fails.append("命中日志未生成（ZHC_DIAG_STATS 未写入）")
        elif code not in stats.read_text(encoding="utf-8").splitlines():
            if has_expect:
                fails.append(f"未命中期望诊断码：{code}")
            elif verbose:
                print(f"    [{code}] 该码未入 {lang} 错误表，③ 跳过")

    if verbose:
        first = next((l for l in output.splitlines() if l.strip()), "")
        print(f"    [{case_dir.name}] {'PASS' if not fails else 'FAIL'}  {first}")
    return not fails, fails


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--zhc", default=str(REPO / "zhc/target/release/bin/main"))
    ap.add_argument("--lang-packs", default=str(REPO / "zhc"),
                  help="语言包根目录（含 lang-packs/{zh,en,ru}）")
    ap.add_argument("--lang", default="zh",
                  help="方言语言代码（默认 zh；决定 ZHCLANG 与源文件/断言文件扩展名）")
    ap.add_argument("--cases", default=str(REPO / "tools/diag-cases"))
    ap.add_argument("--stats", default="", help="ZHC_DIAG_STATS 命中日志路径（断言码命中）")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    # 子进程 cwd 会切到用例目录，所有路径参数先转绝对（相对路径会随 cwd 漂移）
    zhc = str(Path(args.zhc).resolve())
    lang_packs = str(Path(args.lang_packs).resolve())
    cases_root = Path(args.cases).resolve()
    stats_path = str(Path(args.stats).resolve()) if args.stats else ""

    ext = lang_extension(lang_packs, args.lang)
    if ext is None:
        print(f"无法解析语言包 {args.lang} 的扩展名"
              f"（{lang_packs}/lang-packs/{args.lang}/lang_info.toml 缺失或未声明）")
        return 1

    all_dirs = sorted(d for d in cases_root.iterdir() if d.is_dir())
    case_dirs = [d for d in all_dirs if (d / f"main.{ext}").exists()]
    skipped = [d for d in all_dirs
               if d not in case_dirs and (d / "main.zc").exists()]
    if not case_dirs:
        if skipped:
            print(f"语言 {args.lang}（.{ext}）：{len(skipped)} 个用例无 main.{ext}，"
                  f"教学样例未覆盖该语言，全部跳过")
            return 0
        print(f"未找到用例目录（{cases_root} 下无 main.{ext}）")
        return 1

    print(f"语言：{args.lang}（源文件 main.{ext}，ZHCLANG={args.lang}）")
    passed = 0
    for case_dir in case_dirs:
        ok, fails = run_case(zhc, lang_packs, args.lang, ext,
                             case_dir, stats_path, args.verbose)
        if ok:
            passed += 1
            print(f"  ✅ {case_dir.name}")
        else:
            print(f"  ❌ {case_dir.name}")
            for f in fails:
                print(f"       - {f}")
    for case_dir in skipped:
        print(f"  ⏭ {case_dir.name}（无 main.{ext}，教学样例未覆盖 {args.lang}）")

    total = len(case_dirs)
    print(f"\n诊断教学用例（{args.lang}）：{total} 个，通过 {passed}，"
          f"失败 {total - passed}，跳过 {len(skipped)}")
    if stats_path:
        stats = Path(stats_path)
        hit = sorted(set(stats.read_text(encoding="utf-8").splitlines())) \
            if stats.exists() else []
        print(f"命中日志累计 {len(hit)} 个码（可供 tools/diag_coverage.py 聚合）")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
