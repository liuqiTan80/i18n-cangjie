#!/bin/bash
# 批量实测：所有非宏包代码块 zhc run（《中文仓颉程序设计》代码验证）
# 环境变量：VERIFY_ROOT（工作目录，默认脚本所在目录）、ZHC_BIN（默认 zhc）
# 运行产物：$VERIFY_ROOT/out/*.log、$VERIFY_ROOT/results.txt
set -u
VERIFY_ROOT="${VERIFY_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
ZHC_BIN="${ZHC_BIN:-zhc}"
mkdir -p "$VERIFY_ROOT/out"
rm -f "$VERIFY_ROOT/out"/*.log

printf '50\n退出\n退出\nabc\n' > "$VERIFY_ROOT/input.txt"

ls "$VERIFY_ROOT"/src/*.zc | grep -v 'macro' | while read -r f; do
  timeout 120 "$ZHC_BIN" run "$f" < "$VERIFY_ROOT/input.txt" > "$VERIFY_ROOT/out/$(basename "$f" .zc).log" 2>&1
  echo "$? $(basename "$f")"
done | sort -n > "$VERIFY_ROOT/results.txt"

echo "==== 结果汇总 ===="
echo "--- 失败（非零退出码）---"
grep -v '^0 ' "$VERIFY_ROOT/results.txt" || echo "（无）"
echo "--- 通过数 ---"
grep -c '^0 ' "$VERIFY_ROOT/results.txt"
echo "--- 总运行数 ---"
wc -l < "$VERIFY_ROOT/results.txt"
