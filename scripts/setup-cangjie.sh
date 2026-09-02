#!/usr/bin/env bash
# 仓颉 SDK 定位/安装（本地与 CI 共用，替代原占位步骤）
#
# 用法：bash scripts/setup-cangjie.sh [目标目录]
#   目标目录默认 /opt/cangjie（CI 建议传 $RUNNER_TEMP/cangjie-sdk 或固定路径配缓存）
#
# 逻辑（按序）：
#   1) CANGJIE_HOME 已指向可用 SDK（bin/cjc 存在）→ 直接复用并输出；
#   2) 目标目录已装好（bin/cjc 存在）→ 复用并输出；
#   3) 配置了 CANGJIE_SDK_URL → 下载 tar.gz（可选 CANGJIE_SDK_SHA256 校验）→
#      解压定位 SDK 根 → 装入目标目录 → 输出；
#   4) 都没有 → 报错并给出配置指引（exit 2，不再静默占位）。
#
# 环境变量：CANGJIE_SDK_URL（镜像/Release 附件下载地址）、CANGJIE_SDK_SHA256（可选）、
#           CANGJIE_SDK_DIR（目标目录，等价于位置参数）
# 输出：stdout 最后一行 = SDK 根目录（调用方写入 GITHUB_ENV/PATH）
set -euo pipefail

DEST="${1:-${CANGJIE_SDK_DIR:-/opt/cangjie}}"

have_cjc() { [ -x "$1/bin/cjc" ] && [ -x "$1/bin/cjpm" ]; }

# ① 环境变量已指向可用 SDK
if [ -n "${CANGJIE_HOME:-}" ] && have_cjc "$CANGJIE_HOME"; then
    echo "==> 复用 CANGJIE_HOME：$CANGJIE_HOME" >&2
    echo "$CANGJIE_HOME"
    exit 0
fi

# ② 目标目录已装好
if have_cjc "$DEST"; then
    echo "==> 复用已安装 SDK：$DEST" >&2
    echo "$DEST"
    exit 0
fi

# ③ 需要下载
if [ -z "${CANGJIE_SDK_URL:-}" ]; then
    echo "错误：未找到可用仓颉 SDK，也未配置 CANGJIE_SDK_URL。" >&2
    echo "配置方式（任选）：" >&2
    echo "  - 本地/自托管：export CANGJIE_HOME=/path/to/cangjie（含 bin/cjc）" >&2
    echo "  - CI：在仓库 Secrets 配置 CANGJIE_SDK_URL（镜像或 Release 附件直链）" >&2
    echo "        与可选 CANGJIE_SDK_SHA256（防篡改），或在 workflow 中直接写入 URL。" >&2
    exit 2
fi

echo "==> 下载仓颉 SDK：$CANGJIE_SDK_URL" >&2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PKG="$TMP/cangjie-sdk.tar.gz"
curl -fL --retry 3 "$CANGJIE_SDK_URL" -o "$PKG"

if [ -n "${CANGJIE_SDK_SHA256:-}" ]; then
    echo "${CANGJIE_SDK_SHA256}  $PKG" | sha256sum -c - >&2
fi

mkdir -p "$TMP/x"
tar xzf "$PKG" -C "$TMP/x"

# 包内结构未知：定位 bin/cjc 所在目录的父目录作为 SDK 根
CJC="$(find "$TMP/x" -type f -name cjc -path '*/bin/cjc' | head -1)"
if [ -z "$CJC" ]; then
    echo "错误：下载的包内未找到 bin/cjc（包结构不符合预期）" >&2
    exit 1
fi
SRC_ROOT="$(cd "$(dirname "$CJC")/.." && pwd)"

# 装入目标目录（CI runner 的 /opt 需 sudo；脚本自动降级处理）
mkdir -p "$DEST"
if [ ! -w "$DEST" ]; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo cp -r "$SRC_ROOT/." "$DEST/"
    else
        echo "错误：目标目录不可写且无 sudo：$DEST（请传可写路径）" >&2
        exit 1
    fi
else
    cp -r "$SRC_ROOT/." "$DEST/"
fi

if ! have_cjc "$DEST"; then
    echo "错误：装入后仍找不到 bin/cjc（$DEST）" >&2
    exit 1
fi

echo "==> SDK 就绪：$DEST" >&2
echo "$DEST"
