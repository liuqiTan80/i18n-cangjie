#!/usr/bin/env bash
# sync-libs.sh —— 翻译众包平台规范源 → 运行时镜像同步（单向）
# libs/zh/crates/（平台规范源，PR 众包入口）→ zhc/lang-packs/zh/crates/（运行时镜像）
# 注意：
#   · 只做覆盖/新增，不删除——lang-packs 侧多余文件 = 本地 zhc translate 生成
#     未上平台，按需复制到 libs/ 或保留（check-libs.py 会提示不失败）；
#   · 同步后跑 check-libs.py 与 zhc mapping check 确认门禁；
#   · zhc translate/mapping auto 本地生成后想上平台：先把生成 .toml 复制进
#     libs/zh/crates/，再跑本脚本对齐镜像（内容一致，复制无害）。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$DIR/libs/zh/crates"
DST="$DIR/zhc/lang-packs/zh/crates"
if [ ! -d "$SRC" ]; then
    echo "错误：平台目录不存在：$SRC" >&2
    exit 1
fi
mkdir -p "$DST"
count=0
for f in "$SRC"/*.toml; do
    [ -e "$f" ] || continue
    cp "$f" "$DST/$(basename "$f")"
    count=$((count + 1))
done
echo "已同步 $count 个映射文件：libs/zh/crates/ → zhc/lang-packs/zh/crates/"
python3 "$DIR/scripts/check-libs.py"
