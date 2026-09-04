#!/usr/bin/env bash
# zhc 离线发布包构建（设计 §14.3 / s5t9c）
# 用法：scripts/release.sh [版本] [系统] [架构]
#   - 版本默认取 cjpm.toml [package].version（版本单一来源，发布时显式传入亦可）
#   - 产物：dist/zhc-<版本>-<系统>-<架构>.tar.gz（zhc CLI + 仓颉运行时库 + 语言包 + 教程 + VS Code 扩展）
#   - 支持系统：linux（bin/zhc bash 启动器 + lib/*.so）；windows（bin/zhc.bat + bin/*.dll，
#     在 Windows 的 Git Bash 中执行本脚本，需先设置 CANGJIE_HOME 指向解压的 Windows SDK）
# 离线包结构（无网络教学环境直接解压即用，无需 ZHC_LANG_PACKS）：
#   zhc-<版本>-<系统>-<架构>/
#   ├── bin/zhc(.bat)      # 启动器（linux：设 LD_LIBRARY_PATH → exec；windows：预设 ZHC_SELF_EXE）
#   ├── bin/zhc-core(.exe) # 主二进制（resolveLangPack 探测 exeDir 及父目录）
#   ├── bin/ 或 lib/       # 仓颉运行时动态库（linux .so 于 lib/；windows .dll 与 exe 同目录）
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
case "$OS" in
    linux)
        EXE_SUF=""
        RT_SUBDIR="linux_x86_64_cjnative"
        ;;
    windows)
        EXE_SUF=".exe"
        RT_SUBDIR="windows_x86_64_cjnative"
        ;;
    *)
        echo "release.sh 支持 linux / windows（当前 $OS）；其余平台待适配" >&2
        exit 1
        ;;
esac
# CANGJIE_HOME：Linux 默认本机 SDK；Windows 无默认值（在 Windows 上执行时必设，指向解压的 SDK）
if [ "$OS" = "linux" ]; then
    CANGJIE_HOME="${CANGJIE_HOME:-/home/tan80/ruanj/cangjie}"
fi
if [ -z "${CANGJIE_HOME:-}" ] || [ ! -d "$CANGJIE_HOME" ]; then
    echo "请设置 CANGJIE_HOME 指向仓颉 SDK 根目录（含 bin/、runtime/、tools/）" >&2
    exit 1
fi
RUNTIME_LIB="$CANGJIE_HOME/runtime/lib/$RT_SUBDIR"
if [ ! -d "$RUNTIME_LIB" ]; then
    # Windows SDK 架构目录名可能有差异：探测 runtime/lib 下含系统名的子目录兜底
    ALT="$(ls -d "$CANGJIE_HOME"/runtime/lib/*"$OS"* 2>/dev/null | head -1 || true)"
    [ -n "$ALT" ] && [ -d "$ALT" ] && RUNTIME_LIB="$ALT"
fi
if [ ! -d "$RUNTIME_LIB" ]; then
    echo "未找到仓颉运行时库目录：$RUNTIME_LIB（请检查 CANGJIE_HOME 或 SDK 目录结构）" >&2
    exit 1
fi
MAIN="target/release/bin/main${EXE_SUF}"

echo "==> zhc release ${VERSION}（${OS}-${ARCH}，CANGJIE_HOME=${CANGJIE_HOME}）"

# ① release 构建（构建期需要 tools 链，运行期只需 runtime 库）
if [ "$OS" = "linux" ]; then
    export LD_LIBRARY_PATH="$RUNTIME_LIB:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
else
    # Windows：DLL 由系统按 exe 目录/PATH 搜索，构建期自检需 runtime 目录在 PATH
    export PATH="$RUNTIME_LIB:$PATH"
fi
rm -rf target
cjpm build
if [ ! -x "$MAIN" ]; then
    echo "构建失败：$MAIN 不存在" >&2
    exit 1
fi

# ② 自检：help + mapping check（用仓库语言包）
export ZHC_LANG_PACKS="$(pwd)"
"$MAIN" help >/dev/null
"$MAIN" mapping check >/dev/null
echo "==> 自检通过（help / mapping check）"

# ③ 组装离线包
PKG="zhc-${VERSION}-${OS}-${ARCH}"
DIST="dist/${PKG}"
rm -rf "$DIST" "dist/${PKG}.tar.gz"
mkdir -p "$DIST/bin"
cp "$MAIN" "$DIST/bin/zhc-core${EXE_SUF}"
if [ "$OS" = "linux" ]; then
    mkdir -p "$DIST/lib"
    cp "$RUNTIME_LIB/libcangjie-runtime.so" "$RUNTIME_LIB/libboundscheck.so" "$DIST/lib/"
else
    # Windows：DLL 与主程序同目录（exe 目录原生搜索优先，zhc-core.exe 可直接运行）
    cp "$RUNTIME_LIB"/*.dll "$DIST/bin/"
fi
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

if [ "$OS" = "linux" ]; then
    cat > "$DIST/bin/zhc" <<'LAUNCHER'
#!/usr/bin/env bash
# zhc 启动脚本：设置仓颉运行时库路径后执行主二进制
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
export LD_LIBRARY_PATH="$DIR/lib:${LD_LIBRARY_PATH:-}"
exec "$DIR/bin/zhc-core" "$@"
LAUNCHER
    chmod +x "$DIST/bin/zhc"
else
    # Windows 启动器：预设 ZHC_SELF_EXE（Windows 无 /proc/self/exe，语言包 exe 旁探测依赖它）
    cat > "$DIST/bin/zhc.bat" <<'LAUNCHER'
@echo off
rem zhc launcher (Windows): runtime DLLs live next to zhc-core.exe
setlocal
set "ZHC_SELF_EXE=%~dp0zhc-core.exe"
"%~dp0zhc-core.exe" %*
exit /b %ERRORLEVEL%
LAUNCHER
    sed -i 's/$/\r/' "$DIST/bin/zhc.bat"   # CRLF：cmd 对注释/label 更友好
fi

# 平台使用说明（包内 README 分平台生成）
if [ "$OS" = "linux" ]; then
    RUN_STEPS="    tar xzf ${PKG}.tar.gz
    cd ${PKG}
    ./bin/zhc help"
    RUN_BIN="./bin/zhc"
    REQ_LINE="系统要求：Linux x86_64（glibc），可执行权限（chmod +x bin/zhc）。"
else
    RUN_STEPS="    解压 ${PKG}.tar.gz（Windows 10+ 自带 tar：tar xzf ${PKG}.tar.gz；或 7-Zip 等）
    cd ${PKG}
    bin\\zhc.bat help"
    RUN_BIN="bin\\zhc.bat"
    REQ_LINE="系统要求：Windows x86_64（运行时 DLL 已随包置于 bin/，无需安装仓颉 SDK）。"
fi
cat > "$DIST/README.md" <<EOF
# zhc（仓颉方言编程框架）离线发布包 ${VERSION}（${OS}-${ARCH}）

无网络教学环境直接解压使用，无需安装仓颉 SDK、无需设置环境变量：

${RUN_STEPS}

语言包随包内置（lang-packs/，自动探测可执行文件旁目录）；
用户语言包安装到 ~/.zhc/lang-packs/ 即可覆盖内置。

常用命令：

    ${RUN_BIN} init <项目名>                 # 新建方言项目（--native 生成 cjpm 构建钩子）
    ${RUN_BIN} run src/main.zc               # 转译 + 编译 + 运行
    ${RUN_BIN} test                          # 方言测试
    ${RUN_BIN} mapping check [--missing]     # 映射质量门禁 / 待翻译清单
    ${RUN_BIN} lint src/main.zc              # cjlint 集成

教学配套（docs/）：《中文仓颉程序设计》（docs/中文仓颉程序设计/，全部母语示例，
三卷 20 章 + 附录 A/B/C）+ 错误信息字典（docs/errors-dictionary.md，按官方错误码反查）；
IDE 配套（tools/）：VS Code 扩展（高亮/右键运行/全角转换/LSP 诊断）与
高亮、字典生成脚本。扩展也可离线安装预打包的 .vsix（VS Code 内
「从 VSIX 安装…」选择文件，或命令行）：

    code --install-extension tools/zhc-dialect-${EXT_VER}.vsix

${REQ_LINE}
EOF

# ④ 打包 + 校验和（组装目录已含全部内容，打包后清理避免 dist/ 残留解压态目录）
tar -C dist -czf "dist/${PKG}.tar.gz" "$PKG"
# ⑤ 扩展 .vsix 同步到 dist/ 根（发布附件渠道；离线包内 tools/ 仍留一份供解压安装）
EXT_VSIX="$(ls "$DIST"/tools/zhc-dialect-*.vsix 2>/dev/null | head -1 || true)"
if [ -n "$EXT_VSIX" ]; then
    cp "$EXT_VSIX" "dist/$(basename "$EXT_VSIX")"
    echo "==> 已同步扩展附件：dist/$(basename "$EXT_VSIX")"
else
    echo "==> 提示：.vsix 未打包（需 node/npx），dist/ 根附件渠道跳过"
fi
rm -rf "$DIST"
echo "==> 产物：dist/${PKG}.tar.gz"
sha256sum "dist/${PKG}.tar.gz"
if [ "$OS" = "linux" ]; then
    echo "==> 解压验证：tar xzf dist/${PKG}.tar.gz -C /tmp && cd /tmp/${PKG} && ./bin/zhc run <示例.zc>"
else
    echo "==> 解压验证（Windows）：tar xzf ${PKG}.tar.gz 后 cd ${PKG}，执行 bin\\zhc.bat run <示例.zc>"
fi
