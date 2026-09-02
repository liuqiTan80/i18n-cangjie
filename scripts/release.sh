#!/usr/bin/env bash
# zhc 离线发布包构建（设计 §14.3 / s5t9c）
# 用法：scripts/release.sh [版本] [系统] [架构]
#   - 版本默认 0.1.0（与 cjpm.toml [package].version 同步发布时显式传入）
#   - 产物：dist/zhc-<版本>-<系统>-<架构>.tar.gz（CLI + 仓颉运行时库 + 语言包）
# 离线包结构（无网络教学环境直接解压即用，无需 ZHC_LANG_PACKS）：
#   zhc-<版本>-<系统>-<架构>/
#   ├── bin/zhc            # 启动脚本（设置 LD_LIBRARY_PATH → exec zhc-core）
#   ├── bin/zhc-core       # 主二进制（resolveLangPack 探测 exeDir 及父目录）
#   ├── lib/               # 仓颉运行时动态库（ldd 实测仅需这两个）
#   ├── lang-packs/        # zh + en 语言包
#   └── README.md
set -euo pipefail
cd "$(dirname "$0")/../zhc"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    # 版本单一来源（审计修正）：默认取 cjpm.toml [package].version，避免三处漂移
    VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' cjpm.toml | head -1)"
    [ -n "$VERSION" ] || { echo "无法从 cjpm.toml 读取版本（请显式传入）" >&2; exit 1; }
fi
OS="${2:-linux}"
ARCH="${3:-x86_64}"
# 审计修正：release.sh 仅适配 Linux（运行时 .so + bash 启动器 + target/release/bin/main）；
# Windows 发布包待 SDK 渠道与产物命名（main.exe）适配后另行支持，明确拒绝避免误用
if [ "$OS" != "linux" ]; then
    echo "release.sh 仅支持 linux（当前 $OS）；Windows 发布包待适配" >&2
    exit 1
fi
CANGJIE_HOME="${CANGJIE_HOME:-/home/tan80/ruanj/cangjie}"
RUNTIME_LIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
if [ ! -d "$RUNTIME_LIB" ]; then
    echo "未找到仓颉运行时库目录：$RUNTIME_LIB（请设置 CANGJIE_HOME）" >&2
    exit 1
fi

echo "==> zhc release ${VERSION}（${OS}-${ARCH}，CANGJIE_HOME=${CANGJIE_HOME}）"

# ① release 构建（构建期需要 tools/lib 完整链，运行期只需 runtime lib）
export LD_LIBRARY_PATH="$RUNTIME_LIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
rm -rf target
cjpm build
if [ ! -x target/release/bin/main ]; then
    echo "构建失败：target/release/bin/main 不存在" >&2
    exit 1
fi

# ② 自检：help + mapping check（用仓库语言包）
export ZHC_LANG_PACKS="$(pwd)"
target/release/bin/main help >/dev/null
target/release/bin/main mapping check >/dev/null
echo "==> 自检通过（help / mapping check）"

# ③ 组装离线包
PKG="zhc-${VERSION}-${OS}-${ARCH}"
DIST="dist/${PKG}"
rm -rf "$DIST" "dist/${PKG}.tar.gz"
mkdir -p "$DIST/bin" "$DIST/lib"
cp target/release/bin/main "$DIST/bin/zhc-core"
cp "$RUNTIME_LIB/libcangjie-runtime.so" "$RUNTIME_LIB/libboundscheck.so" "$DIST/lib/"
cp -r lang-packs "$DIST/lang-packs"
rm -f "$DIST/lang-packs/"*/crates/*.toml   # 本地 crates 演示映射不进发布包

# 教学与 IDE 配套（§14.3 后续交付物）：教程 + 错误字典 + VS Code 扩展 + 生成脚本
mkdir -p "$DIST/tools"
cp -r ../docs "$DIST/docs"
cp -r ../tools/vscode-extension "$DIST/tools/vscode-extension"
cp ../tools/gen_highlight.py ../tools/gen_error_dict.py "$DIST/tools/"
rm -f "$DIST"/tools/vscode-extension/zhc-dialect-*.vsix  # 重新打包，避免残留旧版

# VS Code 扩展 .vsix（无 npx 环境自动跳过——扩展源码已在 tools/vscode-extension/）
EXT_VER="$(sed -n 's/^  "version": "\([^"]*\)",/\1/p' ../tools/vscode-extension/package.json | head -1)"
if bash ../tools/vscode-extension/build-vsix.sh "$DIST/tools" >/dev/null 2>&1; then
    echo "==> VS Code 扩展已打包：tools/zhc-dialect-${EXT_VER}.vsix"
else
    echo "==> 提示：.vsix 打包跳过（需 node/npx）——离线安装可用 build-vsix.sh 单独打包"
fi

cat > "$DIST/bin/zhc" <<'LAUNCHER'
#!/usr/bin/env bash
# zhc 启动脚本：设置仓颉运行时库路径后执行主二进制
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
export LD_LIBRARY_PATH="$DIR/lib:${LD_LIBRARY_PATH:-}"
exec "$DIR/bin/zhc-core" "$@"
LAUNCHER
chmod +x "$DIST/bin/zhc"

cat > "$DIST/README.md" <<EOF
# zhc（仓颉方言编程框架）离线发布包 ${VERSION}

无网络教学环境直接解压使用，无需安装仓颉 SDK、无需设置环境变量：

    tar xzf zhc-${VERSION}-${OS}-${ARCH}.tar.gz
    cd zhc-${VERSION}-${OS}-${ARCH}
    ./bin/zhc help

语言包随包内置（lang-packs/，自动探测可执行文件旁目录）；
用户语言包安装到 ~/.zhc/lang-packs/ 即可覆盖内置。

常用命令：

    ./bin/zhc init <项目名>                 # 新建方言项目（--native 生成 cjpm  构建钩子）
    ./bin/zhc run src/main.zc               # 转译 + 编译 + 运行
    ./bin/zhc test                          # 方言测试
    ./bin/zhc mapping check [--missing]     # 映射质量门禁 / 待翻译清单
    ./bin/zhc lint src/main.zc              # cjlint 集成

教学配套（docs/）：按章节递进教程（docs/tutorial/，全部母语示例）+
错误信息字典（docs/errors-dictionary.md，按官方错误码反查）；
IDE 配套（tools/）：VS Code 扩展（高亮/右键运行/全角转换/LSP 诊断）与
高亮、字典生成脚本。扩展也可离线安装预打包的 .vsix（VS Code 内
「从 VSIX 安装…」选择文件，或命令行）：

    code --install-extension tools/zhc-dialect-${EXT_VER}.vsix

系统要求：Linux x86_64（glibc），可执行权限（chmod +x bin/zhc）。
EOF

# ④ 打包 + 校验和（组装目录已含全部内容，打包后清理避免 dist/ 残留解压态目录）
tar -C dist -czf "dist/${PKG}.tar.gz" "$PKG"
rm -rf "$DIST"
echo "==> 产物：dist/${PKG}.tar.gz"
sha256sum "dist/${PKG}.tar.gz"
echo "==> 解压验证：tar xzf dist/${PKG}.tar.gz -C /tmp && cd /tmp/${PKG} && ./bin/zhc run <示例.zc>"
