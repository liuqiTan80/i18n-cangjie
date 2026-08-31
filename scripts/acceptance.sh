#!/usr/bin/env bash
# zhc 一键全量验收（设计 §14.3 交付物清单，本地与 CI 共用）
# 用法：bash scripts/acceptance.sh
#   - 覆盖：构建 / help / mapping check / examples 端到端 / 教程综合 / expand /
#            init+run+lint / zhc test / zhc 自身单元测试 / 离线发布包+解压验证 / 语法检查
#   - 任一环节失败 → 汇总报告 FAIL 且退出码非 0（不中断后续步骤，便于一次看全）
#   - 素材全部来自仓库内 zhc/examples/，无外部依赖
cd "$(dirname "$0")/.."
REPO="$(pwd)"
ZHC_DIR="$REPO/zhc"
ZHC_BIN="$ZHC_DIR/target/release/bin/main"
CANGJIE_HOME="${CANGJIE_HOME:-/home/tan80/ruanj/cangjie}"
export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

PASS=0; FAIL=0; FAILED_STEPS=()

step() { echo; echo "==> $1"; }

ok()   { PASS=$((PASS+1)); echo "    ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_STEPS+=("$1"); echo "    ❌ $1"; }

expect_output() { # 文件 期望子串 步骤名
    if grep -qF "$2" "$1"; then ok "$3"; else bad "$3（未输出「$2」）"; fi
}

# ---------- 0. 环境 ----------
if [ ! -x "$ZHC_BIN" ]; then
    step "构建（cjpm build）"
    ( cd "$ZHC_DIR" && rm -rf target && cjpm build ) >/tmp/zhc_accept_build.log 2>&1 \
        && ok "构建成功" || bad "构建失败（见 /tmp/zhc_accept_build.log）"
fi
[ -x "$ZHC_BIN" ] || { echo "无法获取 zhc 可执行文件：$ZHC_BIN"; exit 1; }
export ZHC_LANG_PACKS="$ZHC_DIR"
WORK="$(mktemp -d /tmp/zhc_accept.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
ZH() { "$ZHC_BIN" "$@"; }   # 统一入口（ZHC_LANG_PACKS 已 export；变量展开的 NAME=value 词不当赋值）

# ---------- 1. 自检 ----------
step "1. 自检（help）"
ZH help >"$WORK/help.txt" 2>&1 && ok "help 可运行" || bad "help 失败"
grep -q "zhc test" "$WORK/help.txt" && ok "usage 覆盖 test" || bad "usage 缺 test"

# ---------- 2. 映射质量门禁 ----------
step "2. mapping check（zh/en 一致性）"
ZH mapping check >"$WORK/mapping.txt" 2>&1 \
    && grep -q "全部通过" "$WORK/mapping.txt" \
    && ok "两个语言包全部通过" || bad "mapping check 未通过"

# ---------- 3. examples 端到端 ----------
step "3. examples 端到端（转译 + 编译 + 运行）"
# 在临时目录跑（避免在仓库内生成 .zhc/ 产物，审计 D5）
cp -r "$ZHC_DIR/examples" "$WORK/examples"
( cd "$WORK/examples" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run hello.zc ) >"$WORK/hello.out" 2>&1 \
    && ok "hello.zc 运行" || bad "hello.zc 运行失败（$(tail -1 "$WORK/hello.out")）"
expect_output "$WORK/hello.out" "你好，仓颉" "hello.zc 输出正确"
( cd "$WORK/examples" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" check stdlib.zc ) >"$WORK/stdlib.out" 2>&1 \
    && ok "stdlib.zc 检查" || bad "stdlib.zc 检查失败"
# 诊断黄金样例（设计 §14.1 诊断层）：固定错误源码 → 固定母语诊断文本断言
printf '主函数() {\n    打印行(不存在的标识符)\n}\n' >"$WORK/examples/err_diag.zc"
if ( cd "$WORK/examples" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" check err_diag.zc ) >"$WORK/diag.out" 2>&1; then
    bad "诊断样例：错误源码不应编译通过"
else
    ok "诊断样例：错误源码按预期失败"
fi
expect_output "$WORK/diag.out" "未声明的标识符" "诊断黄金样例：母语翻译命中"
expect_output "$WORK/diag.out" "💡 使用了未定义的名称" "诊断黄金样例：教学提示输出"
# adv.zc 为对抗用例（@派生 宏 1.0.5 语法挂起），不入验收

# ---------- 4. 错误翻译黄金样例（生产级回归门禁） ----------
step "4. 错误翻译黄金样例（12 个高频场景）"
# 每个场景：方言源码 → zhc check → 断言母语片段（防英文回退回归）；
# 源码经 printf %b 展开 \n；场景名/源码/期望片段用 | 分隔（源码不含 |）
ERR_CASES=(
  '未声明标识符|主函数() {\n    打印行(不存在的标识符)\n}|未声明的标识符'
  '类型不匹配|主函数() {\n    让 变量: 整数 = "字符串"\n}|类型不匹配'
  '不可变赋值|主函数() {\n    让 变量 = 1\n    变量 = 2\n}|不能给不可变值赋值'
  '缺右括号|主函数() {\n    让 变量 = (1\n}|未闭合的分隔符'
  '找不到包|导入 标准库.不存在模块.*\n主函数() {}|找不到包'
  '参数个数|函数 甲(参数: 整数) {}\n主函数() {\n    甲()\n}|参数数量不匹配'
  '未知类型|主函数() {\n    让 变量: 不存在的类型 = 1\n}|未声明的类型名'
  '重复声明|主函数() {\n    让 变量 = 1\n    让 变量 = 2\n}|重复声明'
  '泛型缺参|类 盒子<T> {}\n主函数() {\n    让 变量: 盒子 = 盒子()\n}|泛型类型缺少类型参数'
  '非法转义|主函数() {\n    打印行("\\q")\n}|无法识别的转义'
  '数字溢出|主函数() {\n    让 变量: 整数 = 9223372036854775808\n}|超出类型 `整数` 的取值范围'
  '主函数缺失|函数 甲() {}|缺少程序入口 `主函数`'
)
for c in "${ERR_CASES[@]}"; do
    IFS='|' read -r name src expect <<< "$c"
    printf '%b' "$src" >"$WORK/examples/err_$name.zc"
    ( cd "$WORK/examples" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" check "err_$name.zc" ) >"$WORK/err_$name.out" 2>&1
    if grep -qF "$expect" "$WORK/err_$name.out"; then
        ok "$name → $expect"
    else
        bad "$name 未翻译（$(head -1 "$WORK/err_$name.out")）"
    fi
    rm -f "$WORK/examples/err_$name.zc" "$WORK/err_$name.out"
done

# ---------- 5. 教程综合 ----------
step "5. 教程综合（ch030405 / ch06）"
( cd "$WORK/examples/tutorial" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run ch030405.zc ) >"$WORK/ch030405.out" 2>&1 \
    && ok "ch030405.zc 运行" || bad "ch030405.zc 运行失败"
for s in "分数 25：加油" "距离平方：25" "旺财 说：汪汪" "成绩：90"; do
    expect_output "$WORK/ch030405.out" "$s" "ch030405 输出「$s」"
done
( cd "$WORK/examples/tutorial" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run ch06.zc ) >"$WORK/ch06.out" 2>&1 \
    && ok "ch06.zc 运行" || bad "ch06.zc 运行失败"
for s in "没有这个人" "捕获到异常" "无论成败都会执行"; do
    expect_output "$WORK/ch06.out" "$s" "ch06 输出「$s」"
done

# ---------- 6. 宏展开视图 ----------
step "6. expand 宏展开教学视图"
( cd "$WORK/examples/macro-demo" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" expand hello.zc --macro-pkg define ) >"$WORK/expand.out" 2>&1 \
    && ok "expand 可运行" || bad "expand 失败"
grep -q "展开前" "$WORK/expand.out" && grep -q "展开后" "$WORK/expand.out" \
    && ok "三栏视图齐全" || bad "expand 视图缺少对照栏"

# ---------- 7. init + run + lint ----------
step "7. init + run + lint（临时项目）"
( cd "$WORK" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" init 验收项目 ) >"$WORK/init.out" 2>&1 \
    && ok "zhc init 建项目" || bad "zhc init 失败"
( cd "$WORK/验收项目" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run src/main.zc ) >"$WORK/init_run.out" 2>&1 \
    && expect_output "$WORK/init_run.out" "你好，仓颉" "init 项目运行" \
    || bad "init 项目运行失败"
printf '主函数() {\n    打印行("全角，测试：")；\n}\n\n\n' >"$WORK/验收项目/src/fw.zc"
( cd "$WORK/验收项目" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" lint src/fw.zc ) >"$WORK/lint.out" 2>&1
grep -q "全角标点" "$WORK/lint.out" && ok "lint 检出全角标点" || bad "lint 未检出全角标点"
( cd "$WORK/验收项目" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" lint --fix src/fw.zc ) >"$WORK/lintfix.out" 2>&1 \
    && grep -q "已修复" "$WORK/lintfix.out" && ok "lint --fix 修复" || bad "lint --fix 失败"
# 修复后应零风格问题（全角已换半角、空行已压缩）
( cd "$WORK/验收项目" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" lint src/fw.zc ) >"$WORK/lint2.out" 2>&1
if grep -q "风格检查：发现 0 处问题" "$WORK/lint2.out"; then
    ok "lint 修复后零风格问题"
else
    bad "lint 修复后仍有风格问题（$(head -1 "$WORK/lint2.out")）"
fi

# ---------- 8. zhc test ----------
step "8. zhc test（方言测试全链路）"
mkdir -p "$WORK/测试项目/src"
cat >"$WORK/测试项目/cjpm.toml" <<'EOF'
[package]
cjc-version = "1.0.5"
name = "zhc_accept"
version = "0.1.0"
output-type = "executable"

[dependencies]
EOF
cat >"$WORK/测试项目/src/math.zc" <<'EOF'
公开 函数 加法(左: 整数, 右: 整数): 整数 { 返回 左 + 右 }
公开 函数 乘法(左: 整数, 右: 整数): 整数 { 返回 左 * 右 }
EOF
cat >"$WORK/测试项目/src/math_test.zc" <<'EOF'
导入 标准测试宏.*
导入 标准测试.*

@测试
公开 函数 加法正确() {
    @期望(加法(2, 3), 5)
}

@测试
公开 函数 乘法正确() {
    @期望(乘法(3, 4), 12)
}
EOF
( cd "$WORK/测试项目" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" test ) >"$WORK/test.out" 2>&1 \
    && ok "zhc test 通过" || bad "zhc test 失败（$(tail -2 "$WORK/test.out" | head -1)）"
expect_output "$WORK/test.out" "[ 通过 ] 用例： 加法正确" "测试用例 1 母语化输出"
expect_output "$WORK/test.out" "通过： 2" "两个用例全部通过"

# ---------- 9. zhc 自身单元测试 ----------
step "9. zhc 自身单元测试（std.unittest 58 用例）"
# src/*_test.cj 与 main.cj 同包共存（§14.1）；新增测试时同步更新下方 58 断言
# cjpm test 输出含 ANSI 颜色码（PASSED 与数字之间插转义序列），先剥离再断言
( cd "$ZHC_DIR" && cjpm test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' ) >"$WORK/unit.out" 2>&1 \
    && ok "cjpm test 可运行" || bad "cjpm test 失败（$(tail -3 "$WORK/unit.out" | head -1)）"
expect_output "$WORK/unit.out" "PASSED: 58" "单元测试 58 用例全过"
expect_output "$WORK/unit.out" "cjpm test success" "cjpm test 成功退出"

# ---------- 10. 离线发布包 ----------
step "10. release.sh + 离线包解压验证"
bash "$REPO/scripts/release.sh" >"$WORK/release.log" 2>&1 \
    && ok "release.sh 打包" || bad "release.sh 失败（见 $WORK/release.log）"
PKG_TGZ="$(ls "$ZHC_DIR"/dist/zhc-*.tar.gz 2>/dev/null | head -1)"
if [ -n "$PKG_TGZ" ]; then
    PKG_DIR="$WORK/pkg"; mkdir -p "$PKG_DIR"
    tar xzf "$PKG_TGZ" -C "$PKG_DIR" && PKG_ROOT="$(ls -d "$PKG_DIR"/* | head -1)"
    ( cd "$PKG_ROOT" && ./bin/zhc run "$ZHC_DIR/examples/hello.zc" ) >"$WORK/pkg_run.out" 2>&1 \
        && expect_output "$WORK/pkg_run.out" "你好，仓颉" "离线包 bin/zhc run" \
        || bad "离线包运行失败"
    "$PKG_ROOT/bin/zhc" mapping check >"$WORK/pkg_map.out" 2>&1 \
        && grep -q "全部通过" "$WORK/pkg_map.out" && ok "离线包 mapping check" \
        || bad "离线包 mapping check 失败"
    [ -f "$PKG_ROOT/docs/errors-dictionary.md" ] && [ -d "$PKG_ROOT/docs/tutorial" ] \
        && ok "离线包 docs 齐全" || bad "离线包缺 docs"
    [ -d "$PKG_ROOT/tools/vscode-extension" ] && [ -f "$PKG_ROOT/tools/gen_highlight.py" ] \
        && ok "离线包 tools 齐全" || bad "离线包缺 tools"
    grep -q "entity.name.function.macro" "$PKG_ROOT/tools/vscode-extension/syntaxes/zhc.tmLanguage.json" \
        && ok "离线包语法含宏高亮" || bad "离线包语法缺宏高亮"
else
    bad "未找到离线包产物"
fi

# ---------- 11. 语法检查 ----------
step "11. 静态语法检查（脚本/JSON/JS/Python）"
SYNTAX_FAIL=0
bash -n "$REPO/scripts/release.sh" "$REPO/scripts/acceptance.sh" 2>/dev/null || SYNTAX_FAIL=1
python3 -c "import ast,sys
for p in ['$REPO/tools/gen_highlight.py','$REPO/tools/gen_error_dict.py']:
    ast.parse(open(p,encoding='utf-8').read())" 2>/dev/null || SYNTAX_FAIL=1
if command -v node >/dev/null 2>&1; then
    node --check "$REPO/tools/vscode-extension/extension.js" 2>/dev/null || SYNTAX_FAIL=1
fi
python3 -c "import json
json.load(open('$REPO/tools/vscode-extension/package.json'))
json.load(open('$REPO/tools/vscode-extension/syntaxes/zhc.tmLanguage.json'))" 2>/dev/null || SYNTAX_FAIL=1
[ "$SYNTAX_FAIL" = 0 ] && ok "全部静态检查通过" || bad "存在静态检查失败项"

# ---------- 汇总 ----------
echo
echo "==================== 验收汇总 ===================="
echo "通过：$PASS    失败：$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '失败步骤：\n'
    for s in "${FAILED_STEPS[@]}"; do echo "  - $s"; done
    exit 1
fi
echo "✅ zhc 全量验收通过（蓝图 §14.3 交付物清单）"
