#!/usr/bin/env bash
# 教程代码全量验证（《中文仓颉程序设计》150+ 代码块）——本地与 CI 共用入口
#
# 用法：bash scripts/tutorial-check.sh
# 流程：① 清理并抽取全部 cangjie 代码块 → ② 串行实测（非宏块全部通过）
#       → ③ 组合验证（19.3 核心逻辑 + 19.5 重构片段）
# 环境变量（均可覆盖）：
#   ZHC_BIN        zhc 可执行文件（默认 zhc/target/release/bin/main）
#   ZHC_LANG_PACKS 语言包根（默认 zhc/）
#   VERIFY_ROOT    验证工作目录（默认 .verify/；CI 建议指向临时目录避免产物入仓库）
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$REPO/.verify"     # 抽取/实测/组合脚本所在目录（随仓库分发）
VERIFY_ROOT="${VERIFY_ROOT:-$REPO/.verify}"
ZHC_BIN="${ZHC_BIN:-$REPO/zhc/target/release/bin/main}"
export ZHC_LANG_PACKS="${ZHC_LANG_PACKS:-$REPO/zhc}"
export VERIFY_ROOT ZHC_BIN

if [ ! -x "$ZHC_BIN" ]; then
    echo "错误：找不到 zhc 可执行文件：$ZHC_BIN（请先 cd zhc && cjpm build）" >&2
    exit 1
fi

# 开发构建的 zhc 需要仓颉运行时库（发布包自带 lib/ 无此问题）：
# 探测 CANGJIE_HOME（环境变量 → 常见安装位置），把 runtime/tools lib 前置到
# LD_LIBRARY_PATH（用户已配置时不覆盖，仅补充）
if [ -z "${CANGJIE_HOME:-}" ]; then
    for c in "$HOME/ruanj/cangjie" /opt/cangjie; do
        if [ -x "$c/bin/cjc" ]; then CANGJIE_HOME="$c"; break; fi
    done
fi
if [ -n "${CANGJIE_HOME:-}" ]; then
    export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
fi

echo "==> 教程代码全量验证（VERIFY_ROOT=$VERIFY_ROOT）"

echo "==> ① 清理并抽取代码块"
rm -rf "$VERIFY_ROOT"/src "$VERIFY_ROOT"/out "$VERIFY_ROOT"/exp \
       "$VERIFY_ROOT"/exp2 "$VERIFY_ROOT"/results.txt "$VERIFY_ROOT"/input.txt
python3 "$TOOLS/extract.py" || { echo "抽取失败" >&2; exit 1; }

echo "==> ② 串行实测（非宏代码块 zhc run）"
bash "$TOOLS/run_all.sh" > "$VERIFY_ROOT/run_all.log" 2>&1
TOTAL="$(wc -l < "$VERIFY_ROOT/results.txt")"
FAILS="$(grep -vc '^0 ' "$VERIFY_ROOT/results.txt" || true)"
# 唯一允许的失败：19.5 组合片段（引用 19.3 的 玩一局，由 ③ 组合验证把关）
COMBO_FAIL="$(grep -v '^0 ' "$VERIFY_ROOT/results.txt" | grep -c '19-综合实战-3' || true)"
OTHER_FAIL=$((FAILS - COMBO_FAIL))
echo "实测：共 ${TOTAL} 块，直接失败 ${FAILS}（其中组合片段 ${COMBO_FAIL} 待 ③ 验证，其余 ${OTHER_FAIL}）"
if [ "$OTHER_FAIL" != "0" ]; then
    echo "非预期失败清单：" >&2
    grep -v '^0 ' "$VERIFY_ROOT/results.txt" | grep -v '19-综合实战-3' >&2
    exit 1
fi

echo "==> ③ 组合验证（19.3 + 19.5）"
python3 "$TOOLS/combo_check.py" || { echo "组合生成失败" >&2; exit 1; }
printf 'a1\n50\n退出\n退出\n退出\n' > "$VERIFY_ROOT/exp2/input.txt"
( cd "$VERIFY_ROOT/exp2" && timeout 120 "$ZHC_BIN" run combo.zc < input.txt ) > "$VERIFY_ROOT/exp2/combo.log" 2>&1
if grep -q "再见！" "$VERIFY_ROOT/exp2/combo.log"; then
    echo "组合验证通过（含边界输入 a1 → 友好提示，完整对局 + 退出）"
else
    echo "组合验证失败（combo.log 末尾）：" >&2
    tail -5 "$VERIFY_ROOT/exp2/combo.log" >&2
    exit 1
fi

echo "==> ✅ 教程代码全量验证通过"
