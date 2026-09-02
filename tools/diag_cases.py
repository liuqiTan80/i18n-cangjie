#!/usr/bin/env python3
"""诊断教学用例库驱动（建议 D4）——目录化黄金样例回归门禁。

用法：
  python3 tools/diag_cases.py --zhc <zhc 二进制> --lang-packs <语言包目录>
         [--cases <用例根目录>] [--stats <命中日志路径>] [--verbose]

目录约定（tools/diag-cases/<码名>/）：
  main.zc      刻意写错的方言源码（教学场景，可带 // 教学注释说明出处章节）
  expect.txt   期望输出中的母语片段（每行一个，全部须命中）

每个用例断言三件事：
  1. zhc check 必须失败（错误源码不应编译通过）；
  2. 输出须包含 expect.txt 每一行（防英文回退/防翻译漂移）；
  3. --stats 指定时，命中的诊断码日志须含目录码名（码名 = 目录名，
     与 zhc 的 ZHC_DIAG_STATS 埋点、tools/diag_coverage.py 同源）。

任一用例失败 → 退出码 1；全部通过 → 0。设计见 zhc-design §14.1 诊断层。
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def run_case(zhc, lang_packs, case_dir, stats_path, verbose):
    """跑一个用例，返回 (通过?, 失败原因列表)。"""
    code = case_dir.name
    main_zc = case_dir / "main.zc"
    expect_txt = case_dir / "expect.txt"
    fails = []

    env = dict(os.environ)
    env["ZHC_LANG_PACKS"] = str(lang_packs)
    if stats_path:
        env["ZHC_DIAG_STATS"] = str(stats_path)

    # ① 错误源码必须编译失败
    proc = subprocess.run(
        [str(zhc), "check", str(main_zc)],
        cwd=str(case_dir),
        env=env,
        capture_output=True,
        text=True,
    )
    output = proc.stdout + proc.stderr
    if proc.returncode == 0:
        fails.append("错误源码竟然编译通过（zhc check 退出码 0）")
    else:
        # ② 母语片段断言（防英文回退回归）
        for line in expect_txt.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and line not in output:
                fails.append(f"输出缺母语片段：{line}")

    # ③ 码命中断言（目录码名须出现在 ZHC_DIAG_STATS 日志）
    if stats_path:
        stats = Path(stats_path)
        if not stats.exists():
            fails.append("命中日志未生成（ZHC_DIAG_STATS 未写入）")
        elif code not in stats.read_text(encoding="utf-8").splitlines():
            fails.append(f"未命中期望诊断码：{code}")

    if verbose:
        first = next((l for l in output.splitlines() if l.strip()), "")
        print(f"    [{case_dir.name}] {'PASS' if not fails else 'FAIL'}  {first}")
    return not fails, fails


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--zhc", default=str(REPO / "zhc/target/release/bin/main"))
    ap.add_argument("--lang-packs", default=str(REPO / "zhc"),
                  help="语言包根目录（含 lang-packs/{zh,en,ru}）")
    ap.add_argument("--cases", default=str(REPO / "tools/diag-cases"))
    ap.add_argument("--stats", default="", help="ZHC_DIAG_STATS 命中日志路径（断言码命中）")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    cases_root = Path(args.cases)
    case_dirs = sorted(d for d in cases_root.iterdir() if (d / "main.zc").exists())
    if not case_dirs:
        print(f"未找到用例目录（{cases_root} 下无 main.zc）")
        return 1

    passed = 0
    for case_dir in case_dirs:
        ok, fails = run_case(args.zhc, args.lang_packs, case_dir,
                             args.stats, args.verbose)
        if ok:
            passed += 1
            print(f"  ✅ {case_dir.name}")
        else:
            print(f"  ❌ {case_dir.name}")
            for f in fails:
                print(f"       - {f}")

    total = len(case_dirs)
    print(f"\n诊断教学用例：{total} 个，通过 {passed}，失败 {total - passed}")
    if args.stats:
        stats = Path(args.stats)
        hit = sorted(set(stats.read_text(encoding="utf-8").splitlines())) \
            if stats.exists() else []
        print(f"命中日志累计 {len(hit)} 个码（可供 tools/diag_coverage.py 聚合）")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
