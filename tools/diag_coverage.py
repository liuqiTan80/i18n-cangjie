#!/usr/bin/env python3
"""诊断码实战触发率报告（建议 B7）——与 zhc 的 ZHC_DIAG_STATS 埋点配套。

用法：
  python3 tools/diag_coverage.py <命中日志> [errors.toml] [--top N]

- 命中日志：ZHC_DIAG_STATS=<路径> 跑验收/教程/真实使用收集的文件（每行一个码）；
- errors.toml：语言包（默认 zhc/lang-packs/zh/errors.toml），码面 = ["诊断码"] 节键；
- 输出：码面总数 / 命中去重 / 命中率 + 0 触发清单（默认前 30，--top N 全量）；
  退出码：0（统计成功，与命中率无关）。

0 触发清单的用途（见 docs/语言包开发.md）：语料覆盖不到的码 = 要么教学用例
还没触到（补黄金样例候选），要么是死码/超低频（精翻优先级低）。注意语料
有限时 0 触发≠死码——先扩语料再下结论。
"""
import re
import sys
from pathlib import Path

def load_codes(errors_toml):
    """errors.toml 的 ["诊断码"."xxx"] 节键集合。"""
    codes = set()
    cur_section = None
    with open(errors_toml, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("["):
                m = re.match(r'^\["([^"]+)"\."([^"]+)"\]$', line)
                if m:
                    if m.group(1) == "诊断码":
                        codes.add(m.group(2))
                continue
    return codes

def main():
    args = []
    top_n = 30
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--top" and i + 1 < len(sys.argv):
            try:
                top_n = int(sys.argv[i + 1])
                i += 2
                continue
            except ValueError:
                pass
        elif a.startswith("--top="):
            try:
                top_n = int(a.split("=", 1)[1])
                i += 1
                continue
            except ValueError:
                pass
        args.append(a)
        i += 1
    if not args:
        print(__doc__)
        return 1
    stats_path, errors_toml = args[0], (args[1] if len(args) > 1 else
                                        str(Path(__file__).parent.parent / "zhc" /
                                            "lang-packs" / "zh" / "errors.toml"))

    codes = load_codes(errors_toml)
    hits = set()
    if Path(stats_path).exists():
        for line in Path(stats_path).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                hits.add(line)

    n_codes = len(codes)
    n_hits = len(hits & codes)
    outside = sorted(hits - codes)
    missing = sorted(codes - hits)

    print(f"码面总数：{n_codes}")
    print(f"实战命中（去重）：{n_hits}（{100.0 * n_hits / n_codes:.1f}%）")
    if outside:
        print(f"命中但不在码面（{len(outside)}，多为消息表兜底路径）：{', '.join(outside[:10])}")
    print(f"0 触发清单：{len(missing)} 条" + ("" if top_n == 0 else f"（显示前 {top_n}；--top 0 全量）"))
    for code in missing[:top_n] if top_n else missing:
        print(f"  - {code}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
