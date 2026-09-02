#!/usr/bin/env bash
# 教程代码全量验证（《中文仓颉程序设计》150+ 代码块）——本地与 CI 共用入口
#
# 用法：bash scripts/tutorial-check.sh [--refresh]
#   --refresh：重建转译快照基线（正文代码有意修改后使用）
# 流程：① 清理并抽取全部 cangjie 代码块 → ② 串行实测（非宏块全部通过）
#       → ③ 组合验证（19.3 核心逻辑 + 19.5 重构片段）
#       → ④ 排版门禁（全部代码块 zhc lint --style）
#       → ⑤ 转译快照回归（eject 输出与基线比对，防静默漂移）
# 环境变量（均可覆盖）：
#   ZHC_BIN        zhc 可执行文件（默认 zhc/target/release/bin/main）
#   ZHC_LANG_PACKS 语言包根（默认 zhc/）
#   VERIFY_ROOT    验证工作目录（默认 .verify/；CI 建议指向临时目录避免产物入仓库）
#   ZHC_SKIP_SNAPSHOT=1  跳过快照回归（快速迭代用）
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$REPO/.verify"     # 抽取/实测/组合脚本所在目录（随仓库分发）
VERIFY_ROOT="${VERIFY_ROOT:-$REPO/.verify}"
ZHC_BIN="${ZHC_BIN:-$REPO/zhc/target/release/bin/main}"
export ZHC_LANG_PACKS="${ZHC_LANG_PACKS:-$REPO/zhc}"
export VERIFY_ROOT ZHC_BIN

REFRESH=0
for a in "$@"; do
    [ "$a" = "--refresh" ] && REFRESH=1
    [ "$a" = "--skip-snapshot" ] && ZHC_SKIP_SNAPSHOT=1
    [ "$a" = "--skip-style" ] && ZHC_SKIP_STYLE=1
done

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

echo "==> ④ 排版门禁（全部代码块 zhc lint --style）"
if [ "${ZHC_SKIP_STYLE:-}" = "1" ]; then
    echo "（已跳过：--skip-style）"
else
    STYLE_FAIL=0
    STYLE_VIOLATIONS=""
    while read -r f; do
        if ! "$ZHC_BIN" lint "$f" --style >/dev/null 2>&1; then
            STYLE_FAIL=1
            STYLE_VIOLATIONS="${STYLE_VIOLATIONS} $(basename "$f")"
        fi
    done < <(ls "$VERIFY_ROOT"/src/*.zc)
    if [ "$STYLE_FAIL" != "0" ]; then
        echo "排版违规代码块（全角标点/行长>120/CRLF/尾随空白/连续空行）：" >&2
        for b in $STYLE_VIOLATIONS; do echo "  - $b" >&2; done
        echo "请修复教程代码排版（zhc lint <文件> 查看具体位置）" >&2
        exit 1
    fi
    echo "排版门禁通过（$(ls "$VERIFY_ROOT"/src/*.zc | wc -l | tr -d ' ') 块全部无 [风格] 违规）"
fi

echo "==> ⑤ 转译快照回归（eject 输出与基线 sha256 比对）"
if [ "${ZHC_SKIP_SNAPSHOT:-}" = "1" ]; then
    echo "（已跳过：ZHC_SKIP_SNAPSHOT=1 / --skip-snapshot）"
else
    SNAP="$TOOLS/snapshots.sha256"
    SNAPDIR="$VERIFY_ROOT/snapshot"
    rm -rf "$SNAPDIR"
    mkdir -p "$SNAPDIR"
    SNAP_FAIL=0
    while read -r f; do
        b="$(basename "$f" .zc)"
        mkdir -p "$SNAPDIR/$b"
        cp "$f" "$SNAPDIR/$b/main.zc"
        if ! ( cd "$SNAPDIR/$b" && timeout 60 "$ZHC_BIN" eject main.zc >/dev/null 2>&1 && [ -s main.cj ] ); then
            echo "eject 失败：$b" >&2
            SNAP_FAIL=1
        fi
    done < <(ls "$VERIFY_ROOT"/src/*.zc)
    if [ "$SNAP_FAIL" != "0" ]; then
        echo "存在 eject 失败的代码块——转译链路异常" >&2
        exit 1
    fi
    ( cd "$SNAPDIR" && find . -name main.cj | sort | xargs sha256sum | sed 's|\./||; s|/main\.cj||' ) > "$VERIFY_ROOT/snapshots.now"
    if [ "$REFRESH" = "1" ]; then
        cp "$VERIFY_ROOT/snapshots.now" "$SNAP"
        echo "快照基线已更新（$(wc -l < "$SNAP") 块）——请随代码改动一并提交"
    elif [ -f "$SNAP" ]; then
        if diff -q "$SNAP" "$VERIFY_ROOT/snapshots.now" >/dev/null 2>&1; then
            echo "快照一致（$(wc -l < "$SNAP") 块转译输出与基线无差异）"
        else
            echo "快照漂移：转译输出与基线不一致。" >&2
            echo "  - 教程代码未改而转译输出变化 = 词表/豁免集/转译器回归，请排查；" >&2
            echo "  - 正文代码有意修改 = 运行 bash scripts/tutorial-check.sh --refresh 更新基线。" >&2
            echo "漂移块：" >&2
            diff "$SNAP" "$VERIFY_ROOT/snapshots.now" | grep -E '^[<>]' | sed 's/^[<>] [0-9a-f]\{64\}  //' | sort -u | head -20 >&2
            exit 1
        fi
    else
        echo "快照基线缺失（$SNAP）——请运行 bash scripts/tutorial-check.sh --refresh 生成" >&2
        exit 1
    fi
fi

echo "==> ✅ 教程代码全量验证通过"
