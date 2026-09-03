#!/usr/bin/env bash
# zhc 一键安装（建议 C9）——有网络场景的安装入口，与离线包互补
#
# 用法：
#   bash scripts/install.sh [--file <离线包.tar.gz> | --url <下载直链>]
#                           [--version <版本>] [--prefix <目录>]
#                           [--sha256 <校验和>] [--force]
#
# 行为：
#   - 默认从 GitCode Releases 下载：https://gitcode.com/<owner>/<repo>/
#     releases/download/zhc-<版本>/zhc-<版本>-<os>-<arch>.tar.gz
#     （发布 tag 约定：zhc-<版本>；直链也可用 --url 覆盖）
#   - 无网络场景：把离线包 tar.gz 用 --file 传入即可（同一安装流程）
#   - 安装到 --prefix（默认 ~/.zhc）：解压 zhc-<版本>-<os>-<arch>/ 并在
#     <prefix>/bin 下建 zhc 软链；产物自带运行时库与语言包，无需 SDK
#   - --sha256 提供时强制校验（与 scripts/release.sh 输出一致）
# 环境：ZHC_VERSION（默认版本，仓库内运行自动读 zhc/cjpm.toml）
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# 版本默认：仓库内运行读 cjpm.toml（单一来源）；单文件分发场景用 ZHC_VERSION
VERSION="${ZHC_VERSION:-}"
if [ -z "$VERSION" ] && [ -f "$REPO/zhc/cjpm.toml" ]; then
    VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$REPO/zhc/cjpm.toml" | head -1)"
fi
VERSION="${VERSION:-0.2.0}"
OWNER_REPO="tan80/zwCangjie"     # GitCode 仓库（--url 可整体覆盖下载源）

SRC_FILE=""      # 本地离线包
SRC_URL=""       # 下载直链
SHA256=""
PREFIX="${HOME}/.zhc"
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --file) SRC_FILE="$2"; shift 2 ;;
        --url) SRC_URL="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --sha256) SHA256="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "未知参数：$1（--help 查看用法）" >&2; exit 1 ;;
    esac
done

# 平台探测（离线包命名与 release.sh 一致）
OS="$(uname -s | tr 'A-Z' 'a-z')"
case "$OS" in
    linux) ;;
    darwin) ;;
    *) echo "暂不支持的系统：$OS（当前离线包仅 linux/darwin）" >&2; exit 1 ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|aarch64) ;;
    *) echo "暂不支持的架构：$ARCH" >&2; exit 1 ;;
esac

PKG_NAME="zhc-${VERSION}-${OS}-${ARCH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PKG_TGZ="$TMP/${PKG_NAME}.tar.gz"

if [ -n "$SRC_FILE" ]; then
    [ -f "$SRC_FILE" ] || { echo "错误：找不到离线包：$SRC_FILE" >&2; exit 1; }
    cp "$SRC_FILE" "$PKG_TGZ"
elif [ -n "$SRC_URL" ]; then
    echo "==> 下载：$SRC_URL"
    curl -fL --retry 3 "$SRC_URL" -o "$PKG_TGZ"
else
    SRC_URL="https://gitcode.com/${OWNER_REPO}/releases/download/zhc-${VERSION}/${PKG_NAME}.tar.gz"
    echo "==> 下载：$SRC_URL"
    curl -fL --retry 3 "$SRC_URL" -o "$PKG_TGZ"
fi

if [ -n "$SHA256" ]; then
    echo "${SHA256}  $PKG_TGZ" | sha256sum -c -
elif [ -z "$SRC_FILE" ]; then
    echo "提示：未提供 --sha256，跳过校验（发布页 sha256sum 输出可与 --sha256 配合防篡改）" >&2
fi

DEST="$PREFIX/$PKG_NAME"
if [ -d "$DEST" ] && [ "$FORCE" != "1" ]; then
    echo "已安装同版本：$DEST（--force 覆盖重装）" >&2
    exit 0
fi
mkdir -p "$PREFIX/bin"
tar xzf "$PKG_TGZ" -C "$PREFIX"
[ -x "$DEST/bin/zhc" ] || { echo "错误：解压产物缺少 bin/zhc（包结构异常）" >&2; exit 1; }
ln -sfn "$DEST/bin/zhc" "$PREFIX/bin/zhc"

echo "==> 安装完成：$DEST"
echo "==> 使用：export PATH=\"$PREFIX/bin:\$PATH\"（或直接调用 $PREFIX/bin/zhc）"
echo "==> 卸载：rm -rf $DEST $PREFIX/bin/zhc"
"$PREFIX/bin/zhc" help >/dev/null 2>&1 \
    && echo "==> 自检通过：$("$PREFIX/bin/zhc" help 2>/dev/null | head -1)" \
    || echo "==> 警告：自检失败（运行时库缺失？请检查系统 glibc 版本）" >&2
