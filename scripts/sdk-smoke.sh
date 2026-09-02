#!/usr/bin/env bash
# SDK 版本冒烟（建议 B8）：验证 zhc 在指定仓颉 SDK 下构建 + 自检 + 端到端
# + 诊断翻译（SDK 升级最常破坏：JSON 诊断格式 / DiagKind 码面 / 编译行为）。
# 用途：官方 SDK 升级前后回归——本地换 SDK 目录跑；CI 的 sdk-canary job 调用。
#
# 用法：bash scripts/sdk-smoke.sh [SDK 根目录 | --url <下载直链> [--sha256 <hash>]]
#   - 目录：直接使用（bin/cjc 存在）
#   - --url：经 scripts/setup-cangjie.sh 下载装入临时目录（可配 --sha256）
#   - 不传：复用 CANGJIE_HOME（未设则探测常见安装位置）
# 输出：SDK 版本 + 各冒烟项 ✅/❌；任一失败 exit 1
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

SDK=""
URL=""
SHA256=""
while [ $# -gt 0 ]; do
    case "$1" in
        --url) URL="$2"; shift 2 ;;
        --sha256) SHA256="$2"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) [ -z "$SDK" ] && SDK="$1" || { echo "多余参数：$1" >&2; exit 1; }; shift ;;
    esac
done

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "    ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "    ❌ $1"; }

# ① 定位 SDK
if [ -n "$URL" ]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export CANGJIE_SDK_URL="$URL"
    [ -n "$SHA256" ] && export CANGJIE_SDK_SHA256="$SHA256"
    SDK="$(bash "$REPO/scripts/setup-cangjie.sh" "$TMP/sdk")"
    unset CANGJIE_SDK_URL CANGJIE_SDK_SHA256
elif [ -z "$SDK" ]; then
    if [ -n "${CANGJIE_HOME:-}" ] && [ -x "$CANGJIE_HOME/bin/cjc" ]; then
        SDK="$CANGJIE_HOME"
    else
        for c in "$HOME/ruanj/cangjie" /opt/cangjie; do
            [ -x "$c/bin/cjc" ] && SDK="$c" && break
        done
    fi
fi
if [ -z "$SDK" ] || [ ! -x "$SDK/bin/cjc" ]; then
    echo "错误：未找到可用仓颉 SDK（传目录或 --url；或设 CANGJIE_HOME）" >&2
    exit 1
fi

export CANGJIE_HOME="$SDK"
export LD_LIBRARY_PATH="$SDK/runtime/lib/linux_x86_64_cjnative:$SDK/tools/lib:${LD_LIBRARY_PATH:-}"
export PATH="$SDK/bin:$SDK/tools/bin:$PATH"
CJC_VER="$("$SDK/bin/cjc" --version 2>/dev/null | head -1)"
echo "==> SDK 冒烟：$SDK（$CJC_VER）"

# ② 构建 + 自检
( cd "$REPO/zhc" && rm -rf target && cjpm build ) >/tmp/zhc_sdk_build.log 2>&1 \
    && ok "cjpm build" || bad "构建失败（见 /tmp/zhc_sdk_build.log）"
ZHC_BIN="$REPO/zhc/target/release/bin/main"
[ -x "$ZHC_BIN" ] || { echo "构建产物缺失" >&2; exit 1; }
export ZHC_LANG_PACKS="$REPO/zhc"
"$ZHC_BIN" help >/dev/null 2>&1 && ok "help" || bad "help 失败"
"$ZHC_BIN" mapping check >/dev/null 2>&1 && ok "mapping check" || bad "mapping check 失败"

# ③ 端到端（方言示例转译 + 编译 + 运行——SDK 语法面回归）
OUT="$(mktemp).zc"
trap 'rm -rf "${TMP:-}" "$OUT" "$OUT.diag"' EXIT
if ( cd "$REPO/zhc/examples" && "$ZHC_BIN" run hello.zc ) >"$OUT" 2>&1 \
    && grep -q "你好，仓颉" "$OUT"; then
    ok "示例端到端（hello.zc 输出正确）"
else
    bad "示例端到端失败（$OUT 末尾）："; tail -3 "$OUT" >&2 || true
fi

# ④ 诊断翻译（SDK 升级最敏感：JSON 诊断格式 / DiagKind / 编译行为）
printf '主函数() {\n    打印行(不存在的标识符)\n}\n' >"$OUT"
# 错误源码应编译失败（exit≠0），且输出必须是中文教学诊断
if ( cd "$REPO/zhc/examples" && "$ZHC_BIN" check "$OUT" ) >"$OUT.diag" 2>&1; then
    bad "诊断样例：错误源码不应编译通过"
elif grep -q "未声明的标识符" "$OUT.diag"; then
    ok "诊断翻译黄金样例（未声明的标识符 → 中文教学诊断）"
else
    bad "诊断翻译失效（见 $OUT.diag 末尾）"; tail -3 "$OUT.diag" >&2 || true
fi

echo
echo "SDK 冒烟：通过 $PASS / $((PASS + FAIL))"
[ "$FAIL" = "0" ] && echo "✅ SDK 冒烟通过（$CJC_VER）" || echo "❌ SDK 冒烟失败（$FAIL 项）"
exit $([ "$FAIL" = "0" ] && echo 0 || echo 1)
