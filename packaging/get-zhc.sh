#!/usr/bin/env bash
# zhc 一行安装入口：curl -fsSL <本脚本的网络直链> | bash
# 原理：经 jsDelivr 拉取仓库内 scripts/install.sh 并执行（GitCode raw 匿名
# 返回 HTML 预览页不可用，实测矩阵见 docs/全球化路线图.md）。
set -euo pipefail
REPO_RAW="https://cdn.jsdelivr.net/gh/liuqiTan80/i18n-cangjie@main"
echo "==> 拉取 zhc 安装器（jsDelivr 直读 GitHub 镜像）"
install_sh="$(mktemp /tmp/zhc-install-XXXXXX.sh)"
trap 'rm -f "$install_sh"' EXIT
curl -fsSL --retry 3 "$REPO_RAW/scripts/install.sh" -o "$install_sh"
bash "$install_sh" "$@"
