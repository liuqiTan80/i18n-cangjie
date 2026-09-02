#!/usr/bin/env bash
# 打包 VS Code 扩展 .vsix（release.sh 与 CI 共用；需要 node/npx）
# 用法：bash build-vsix.sh [输出目录]（默认本目录）
# 成功：stdout 输出 .vsix 绝对路径；退出码 3 = 无 npx（调用方可选择跳过）
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$DIR}"
EXT_VER="$(sed -n 's/^  "version": "\([^"]*\)",/\1/p' "$DIR/package.json" | head -1)"

if ! command -v npx >/dev/null 2>&1; then
    echo "未找到 npx——跳过 .vsix 打包（不影响扩展源码分发）" >&2
    exit 3
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"   # 绝对化：下方 cd 到扩展目录后相对路径不再有效
cd "$DIR"
# --baseContentUrl/--baseImagesUrl：vsce 仅自动识别 GitHub/GitLab，GitCode 仓库显式指定
if ! npx --yes @vscode/vsce@2 package -o "$OUT/zhc-dialect-${EXT_VER}.vsix" \
    --baseContentUrl https://gitcode.com/tan80/zwCangjie/blob/master \
    --baseImagesUrl https://gitcode.com/tan80/zwCangjie/raw/master 2>&1 | tail -1 | grep -q 'DONE'; then
    echo "错误：vsce 打包失败（输出目录需已存在或可创建）——见上方错误" >&2
    exit 1
fi
echo "$OUT/zhc-dialect-${EXT_VER}.vsix"
