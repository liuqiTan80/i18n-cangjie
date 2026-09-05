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
# 必须 export：zhc 子进程（lint 的 cjlint 集成）与 cjc 都需要 CANGJIE_HOME（cjlint 缺失时退出 255）
export CANGJIE_HOME
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
export ZHC_DIAG_STATS="$WORK/diag-stats.txt"   # 建议 B7：全程收集命中的稳定错误码（段 15 聚合）

# ---------- 0. SDK 版本可追溯（结论固化于 zhc-design §13.1，SDK 漂移 = 结论失效） ----------
step "0. SDK 版本检查（zhc 实测结论固化于 cjc 1.0.5）"
CJC_BIN="$CANGJIE_HOME/bin/cjc"
if [ ! -x "$CJC_BIN" ]; then
    bad "SDK cjc 不存在：$CJC_BIN（CANGJIE_HOME=$CANGJIE_HOME）"
elif CJC_VER="$("$CJC_BIN" --version 2>/dev/null | head -1)" \
    && python3 -c "import sys,re
m=re.search(r'([0-9]+)\\.([0-9]+)\\.([0-9]+)', '''$CJC_VER''')
sys.exit(0 if m and tuple(map(int, m.groups())) >= (1,0,5) else 1)" 2>/dev/null; then
    ok "SDK 版本 ≥ 1.0.5（$CJC_VER）"
else
    bad "SDK 版本过低或不可解析（$CJC_VER）——请升级后重跑验收"
fi

# ---------- 1. 自检 ----------
step "1. 自检（help）"
ZH help >"$WORK/help.txt" 2>&1 && ok "help 可运行" || bad "help 失败"
grep -q "zhc test" "$WORK/help.txt" && ok "usage 覆盖 test" || bad "usage 缺 test"

# ---------- 2. 映射质量门禁 ----------
step "2. mapping check（zh/en/ru/ja 全语言包）"
ZH mapping check >"$WORK/mapping.txt" 2>&1 \
    && grep -q "全部通过" "$WORK/mapping.txt" \
    && ok "全部语言包通过（$(grep -o '[0-9]\+ 个语言包' "$WORK/mapping.txt" | tail -1)）" || bad "mapping check 未通过"

# ---------- 2b. ja 日语演示端到端（词表漂移/转译退化哨兵） ----------
step "2b. ja 日语演示（ZHCLANG=ja 转译 + 编译 + 运行）"
printf 'いれる 標準コレクション.{リスト}\n\nメイン() {\n    おく 数々 = リスト<せいすう>()\n    数々.くわえる(3)\n    ひょうじ("こんにちは、${数々.ながさ}")\n}\n' >"$WORK/ja_demo.jc"
( cd "$WORK" && ZHC_LANG_PACKS="$ZHC_DIR" ZHCLANG=ja "$ZHC_BIN" run ja_demo.jc ) >"$WORK/ja.out" 2>&1 \
    && ok "ja 转译编译运行" || bad "ja 运行失败（$(tail -2 "$WORK/ja.out" | head -1)）"
expect_output "$WORK/ja.out" "こんにちは、1" "ja 输出正确（値は 1）"

# ---------- 2c. zhc fmt 排版格式化器（排版退化哨兵） ----------
step "2c. zhc fmt（缩进/运算符空格；--check 模式）"
printf '主函数(){\n让 数=1\n如果(数>0){打印行("fmt ok")}\n}\n' >"$WORK/fmt_dirty.zc"
cp "$WORK/fmt_dirty.zc" "$WORK/fmt_ck.zc"
# --check 检出脏文件且不改写（rc=1）
( cd "$WORK" && "$ZHC_BIN" fmt --check fmt_ck.zc ) >/dev/null 2>&1 \
    && bad "fmt --check 脏文件误过" || ok "fmt --check 检出脏文件（rc=1）"
grep -q '^主函数(){' "$WORK/fmt_ck.zc" && ok "fmt --check 不改写文件" || bad "fmt --check 误改写文件"
# 格式化 + 报告行数 + 内容断言
( cd "$WORK" && "$ZHC_BIN" fmt fmt_dirty.zc ) >"$WORK/fmt.out" 2>&1 \
    && ok "fmt 执行" || bad "fmt 失败（$(tail -2 "$WORK/fmt.out" | head -1)）"
expect_output "$WORK/fmt.out" "已格式化 3 行" "fmt 报告变化行数"
grep -q '^    如果 (数>0) {打印行("fmt ok")}' "$WORK/fmt_dirty.zc" \
    && ok "缩进/控制词/单行块排版正确" || bad "fmt 输出不符（$(head -3 "$WORK/fmt_dirty.zc")）"
# 已格式化文本：--check 无差异（幂等）
( cd "$WORK" && "$ZHC_BIN" fmt --check fmt_dirty.zc ) >/dev/null 2>&1 \
    && ok "fmt --check 无差异 rc=0" || bad "fmt --check 误报差异"
# 格式化后端到端：转译 + 编译 + 运行
( cd "$WORK" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run fmt_dirty.zc ) >"$WORK/fmt_run.out" 2>&1 \
    && ok "fmt 后运行" || bad "fmt 后运行失败（$(tail -2 "$WORK/fmt_run.out" | head -1)）"
expect_output "$WORK/fmt_run.out" "fmt ok" "fmt 后运行输出正确"

# ---------- 2d. zhc compare 对照视图数据源（方言↔官方词级映射 JSON） ----------
step "2d. zhc compare（对照 JSON：词对坐标/取词一致/保行）"
ZH help >"$WORK/help2.txt" 2>&1
if grep -q "zhc compare" "$WORK/help2.txt"; then ok "usage 覆盖 compare"; else bad "usage 缺 compare"; fi
# 无参数：用法提示 rc=1
ZH compare >/dev/null 2>&1 && bad "compare 无参数误过" || ok "compare 无参数 rc=1"
# 真实样例：JSON 结构 + 每对区间在两侧取词一致 + 行数保行 + 源偏移升序
ZH compare "$ZHC_DIR/examples/hello.zc" >"$WORK/cmp.json" 2>&1 \
    && ok "compare 输出对照 JSON" || bad "compare 失败（$(tail -1 "$WORK/cmp.json")）"
python3 - "$WORK/cmp.json" <<'PYEOF' && ok "compare JSON：取词一致/保行/升序" || bad "compare JSON 结构断言失败"
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
ps = d['pairs']
assert len(ps) >= 5, '词对数过少'
assert d['dialect'].count('\n') == d['official'].count('\n'), '两侧行数不等（转译应保行）'
for s, sl, o, ol in ps:
    zh = d['dialect'][s:s + sl]
    en = d['official'][o:o + ol]
    assert zh and en and zh != en, '区间取词异常'
assert all(ps[i][0] < ps[i + 1][0] for i in range(len(ps) - 1)), '条目未按源偏移升序'
PYEOF

# ---------- 2e. 用户自定义宏 ----------
step "2e. zhc 用户自定义宏（宏.zcm：展开运行/保护/错误诊断/compare 集成）"
MACRO="$WORK/macro"
mkdir -p "$MACRO"
cat >"$MACRO/宏.zcm" <<'ZCMEOF'
// 我的宏：断言条件成立，不成立则打印消息
@断言(条件, 消息) {
    如果 (!(条件)) {
        打印行(消息)
    }
}

@问候(名字) {
    打印行("你好，" + 名字)
}

@打印(消息) {
    打印行("消息：" + 消息)
}
ZCMEOF
cat >"$MACRO/main.zc" <<'ZCMEOF'
主函数() {
    让 数 = 3
    让 上界 = 5
    @断言(数 > 上界, "数太小了")
    @问候("小明")
    @打印("ABC")
}
ZCMEOF
# 展开运行：断言命中 / 参数整词替换 / 字符串内同名文本不替换（"消息：" 字面保留）
( cd "$MACRO" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run main.zc ) >"$WORK/macro.out" 2>&1 \
    && ok "宏：run 编译运行通过" || bad "宏：run 失败（$(tail -1 "$WORK/macro.out")）"
python3 - "$WORK/macro.out" <<'PYEOF' && ok "宏：展开语义正确（断言/替换/保护）" || bad "宏：输出语义不符"
import sys
with open(sys.argv[1], encoding='utf-8') as f:
    t = f.read()
ks = ["数太小了", "你好，小明", "消息：ABC"]
pos = -1
for k in ks:
    i = t.find(k)
    assert i > pos, f'缺少或乱序: {k}'
    pos = i
PYEOF
# compare 集成：对照 JSON 的方言侧 = 宏展开后的文本（与编译链一致）
ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" compare "$MACRO/main.zc" >"$WORK/macro_cmp.json" 2>&1 \
    && ok "宏：compare 输出 JSON" || bad "宏：compare 失败"
python3 - "$WORK/macro_cmp.json" <<'PYEOF' && ok "宏：compare 方言侧已含展开体" || bad "宏：compare 方言侧未展开"
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
assert '@断言' not in d['dialect'], '方言侧仍含未展开宏调用'
assert '如果' in d['dialect'] and '打印行' in d['dialect'], '方言侧缺少宏体内容'
assert d['dialect'].count('\n') == d['official'].count('\n'), '展开后两侧仍保行'
PYEOF
# 实参个数错：rc=1 + 母语错误（含调用行号）
sed 's/@断言(数 > 上界, "数太小了")/@断言(数 > 上界)/' "$MACRO/main.zc" >"$MACRO/badcall.zc"
if ( cd "$MACRO" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run badcall.zc ) >"$WORK/macro_bad.out" 2>&1; then
    bad "宏：实参个数错不应通过"
else
    ok "宏：实参个数错 rc=1"
fi
expect_output "$WORK/macro_bad.out" "需 2 个实参" "宏：实参个数错母语诊断"
expect_output "$WORK/macro_bad.out" "第 4 行" "宏：实参个数错带调用行号"
# 宏文件语法错：rc=1 + 定位到宏文件行号
mkdir -p "$MACRO/bad"
printf '@坏宏(甲) {\n    打印行(甲)\n' >"$MACRO/bad/宏.zcm"
printf '主函数() {\n    @坏宏(1)\n}\n' >"$MACRO/bad/main.zc"
if ( cd "$MACRO/bad" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run main.zc ) >"$WORK/macro_syn.out" 2>&1; then
    bad "宏：宏文件语法错不应通过"
else
    ok "宏：宏文件语法错 rc=1"
fi
expect_output "$WORK/macro_syn.out" "宏体缺少配对的 }" "宏：语法错母语诊断"
expect_output "$WORK/macro_syn.out" "宏.zcm" "宏：语法错定位到宏定义文件"
# 无宏定义文件：行为回归（不影响既有项目）
mkdir -p "$WORK/nomacro"
cp "$ZHC_DIR/examples/hello.zc" "$WORK/nomacro/"
( cd "$WORK/nomacro" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run hello.zc ) >"$WORK/nomacro.out" 2>&1 \
    && ok "宏：无宏文件时正常运行" || bad "宏：无宏文件时被误伤（$(tail -1 "$WORK/nomacro.out")）"
expect_output "$WORK/nomacro.out" "你好，仓颉" "宏：无宏文件运行输出正确"

# ---------- 2f. libs 翻译众包平台（门禁 / 润色替换 / 用户标识符豁免） ----------
step "2f. libs 翻译众包平台（check-libs 门禁 / 润色替换 / 用户标识符豁免）"
# 众包规范源 libs/zh/crates ↔ 运行时镜像 lang-packs/zh/crates 一致性 + 格式 + 撞词表
if python3 "$REPO/scripts/check-libs.py" >"$WORK/libs_gate.out" 2>&1; then
    ok "平台：check-libs 门禁通过（格式/撞词表/双目录一致）"
else
    bad "平台：check-libs 门禁失败（$(tail -3 "$WORK/libs_gate.out")）"
fi
# 文档多语言同步门禁（docs/i18n/：源指纹 + 导航链接，见 docs/i18n/README.md）
if python3 "$REPO/scripts/verify-i18n-docs.py" >"$WORK/i18n_docs.out" 2>&1; then
    ok "i18n：文档多语言同步门禁通过（$(grep -c '^同步' "$WORK/i18n_docs.out") 个译文同步）"
else
    bad "i18n：文档同步门禁失败（$(tail -3 "$WORK/i18n_docs.out")）"
fi
# 撞词表负路径：临时键撞 zh 词表（函数 = keywords 键）→ 门禁必须拦截
printf '["标识符"]\n"颜色" = "Color"\n"函数" = "func"\n' >"$REPO/libs/zh/crates/__gate_probe.toml"
if python3 "$REPO/scripts/check-libs.py" >/dev/null 2>&1; then
    bad "平台：违规键文件未被拦截"
else
    ok "平台：违规键（撞词表/跨库重复）被门禁拦截"
fi
rm -f "$REPO/libs/zh/crates/__gate_probe.toml"
# 润色生效 + 声明豁免：crates 键在库符号使用处替换为官方名；用户声明名不被劫持
printf '// libs 冒烟：crates 键替换 + 用户声明豁免\n主函数() {\n    let 问候语 = 颜色\n    打招呼(问候语)\n    打印行(数量上限)\n}\n' >"$WORK/libs_smoke.zc"
ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" compare "$WORK/libs_smoke.zc" >"$WORK/libs_cmp.json" 2>&1 \
    && ok "平台：compare 冒烟可运行" || bad "平台：compare 冒烟失败（$(tail -1 "$WORK/libs_cmp.json")）"
python3 - "$WORK/libs_cmp.json" <<'PYEOF' && ok "平台：库符号替换生效且用户变量不被劫持" || bad "平台：替换语义不符（豁免失效）"
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
off = d['official']
assert 'Color' in off and 'greet' in off and 'MAX_N' in off, 'crates 键未替换为官方名'
assert '问候语' in off, '用户声明的同名标识符被劫持（豁免失效）'
PYEOF


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

# ---------- 4. 诊断教学用例库（建议 D4：目录化黄金样例 + 码命中断言） ----------
step "4. 诊断教学用例库（tools/diag-cases 目录驱动：母语断言 + 期望码命中）"
# 用例库 = tools/diag-cases/<码名>/{main.zc, expect.txt}（12 迁移 + 4 新增：
# 第 20 章扩展/运算符坑 + 索引越界）；驱动断言三件事：错误源码必失败 /
# 母语片段命中（防英文回退）/ ZHC_DIAG_STATS 命中目录码名（防码面漂移）
if ( cd "$REPO" && python3 tools/diag_cases.py --zhc "$ZHC_BIN" --lang-packs "$ZHC_DIR" \
        --stats "$ZHC_DIAG_STATS" ) >"$WORK/diag_cases.out" 2>&1; then
    ok "诊断教学用例 16/16：母语片段 + 期望码全部命中"
else
    bad "诊断教学用例存在失败（见 $WORK/diag_cases.out）"
    grep -A2 '❌' "$WORK/diag_cases.out" | head -16
fi

# 警告场景：detail（↳）与 note（·）行也必须全中文（2026-09 全中文提示回归门禁）
printf '主函数() {\n    让 未使用的变量 = 1\n    打印行("ok")\n}\n' >"$WORK/examples/err_warn.zc"
( cd "$WORK/examples" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" check err_warn.zc ) >"$WORK/err_warn.out" 2>&1
if grep -qF "↳ 未使用的变量" "$WORK/err_warn.out"; then
    ok "警告 detail 行中文（未使用的变量）"
else
    bad "警告 detail 行未翻译（$(grep '↳' "$WORK/err_warn.out" | head -1)）"
fi
if grep -qF "此警告可通过编译器选项" "$WORK/err_warn.out"; then
    ok "警告 note 行中文（编译器选项）"
else
    bad "警告 note 行未翻译（$(grep '·' "$WORK/err_warn.out" | head -1)）"
fi
rm -f "$WORK/examples/err_warn.zc" "$WORK/err_warn.out"

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

# 教程综合案例项目（18.8 温度转换 / 19 章猜数字）
( cd "$WORK/examples/projects" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run temperature/main.zc <<<"25" ) >"$WORK/temp.out" 2>&1 \
    && expect_output "$WORK/temp.out" "77.000000" "温度转换：25 → 77" \
    || bad "temperature 项目运行失败"
( cd "$WORK/examples/projects" && ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run temperature/main.zc <<<"abc" ) >"$WORK/temp2.out" 2>&1 \
    && expect_output "$WORK/temp2.out" "不是数字" "温度转换：非法输入友好提示" \
    || bad "temperature 非法输入处理失败"
( cd "$WORK/examples/projects" && printf '50\n退出\n退出\n' | ZHC_LANG_PACKS="$ZHC_DIR" "$ZHC_BIN" run guessing-game/main.zc ) >"$WORK/guess.out" 2>&1 \
    && grep -q "再见！" "$WORK/guess.out" && ok "猜数字项目完整对局 + 退出" \
    || bad "guessing-game 项目运行失败（$(tail -1 "$WORK/guess.out")）"

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
step "9. zhc 自身单元测试（std.unittest，用例数动态统计）"
# src/*_test.cj 与 main.cj 同包共存（§14.1）；期望用例数从源码 @Test 注解
# 动态统计，不再写死（新增测试免同步本脚本，审计修复）
EXPECTED_TESTS="$(grep -h -c '^@Test' "$ZHC_DIR"/src/*_test.cj | awk '{s+=$1} END {print s}')"
# cjpm test 输出含 ANSI 颜色码（PASSED 与数字之间插转义序列），先剥离再断言
( cd "$ZHC_DIR" && cjpm test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' ) >"$WORK/unit.out" 2>&1 \
    && ok "cjpm test 可运行" || bad "cjpm test 失败（$(tail -3 "$WORK/unit.out" | head -1)）"
expect_output "$WORK/unit.out" "PASSED: ${EXPECTED_TESTS}" "单元测试 ${EXPECTED_TESTS} 用例全过"
expect_output "$WORK/unit.out" "FAILED: 0" "单元测试 0 失败"
expect_output "$WORK/unit.out" "cjpm test success" "cjpm test 成功退出"

# ---------- 10. 离线发布包 ----------
step "10. release.sh + 离线包解压验证"
# 版本单一来源（建议 A1）：cjpm.toml ↔ package.json ↔ 离线包名三方一致
CJPM_VER="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$ZHC_DIR/cjpm.toml" | head -1)"
VSIX_VER="$(sed -n 's/^  "version": "\([^"]*\)",/\1/p' "$REPO/tools/vscode-extension/package.json" | head -1)"
if [ -n "$CJPM_VER" ] && [ "$CJPM_VER" = "$VSIX_VER" ]; then
    ok "版本单一来源：cjpm.toml 与 package.json 一致（$CJPM_VER）"
else
    bad "版本漂移：cjpm.toml=$CJPM_VER vs package.json=$VSIX_VER"
fi
bash "$REPO/scripts/release.sh" >"$WORK/release.log" 2>&1 \
    && ok "release.sh 打包" || bad "release.sh 失败（见 $WORK/release.log）"
# 按 cjpm.toml 版本精确取包（dist/ 可能残留旧版包，字母序取首个会错拿）
PKG_TGZ="$(ls "$ZHC_DIR"/dist/zhc-${CJPM_VER}-*.tar.gz 2>/dev/null | head -1)"
if [ -n "$PKG_TGZ" ]; then
    PKG_VER="$(basename "$PKG_TGZ" .tar.gz | sed 's/^zhc-\([^-]*\)-.*$/\1/')"
    [ "$PKG_VER" = "$CJPM_VER" ] && ok "离线包版本与 cjpm.toml 一致（$PKG_VER）" \
        || bad "离线包版本漂移：产物=$PKG_VER vs cjpm.toml=$CJPM_VER"
    PKG_DIR="$WORK/pkg"; mkdir -p "$PKG_DIR"
    tar xzf "$PKG_TGZ" -C "$PKG_DIR" && PKG_ROOT="$(ls -d "$PKG_DIR"/* | head -1)"
    ( cd "$PKG_ROOT" && ./bin/zhc run "$ZHC_DIR/examples/hello.zc" ) >"$WORK/pkg_run.out" 2>&1 \
        && expect_output "$WORK/pkg_run.out" "你好，仓颉" "离线包 bin/zhc run" \
        || bad "离线包运行失败"
    "$PKG_ROOT/bin/zhc" mapping check >"$WORK/pkg_map.out" 2>&1 \
        && grep -q "全部通过" "$WORK/pkg_map.out" && ok "离线包 mapping check" \
        || bad "离线包 mapping check 失败"
    [ -f "$PKG_ROOT/docs/errors-dictionary.md" ] && [ -d "$PKG_ROOT/docs/中文仓颉程序设计" ] \
        && ok "离线包 docs 齐全" || bad "离线包缺 docs"
    [ -d "$PKG_ROOT/tools/vscode-extension" ] && [ -f "$PKG_ROOT/tools/gen_highlight.py" ] \
        && [ -f "$PKG_ROOT/tools/gen_error_dict.py" ] \
        && ok "离线包 tools 齐全" || bad "离线包缺 tools"
    grep -q "entity.name.function.macro" "$PKG_ROOT/tools/vscode-extension/syntaxes/zhc.tmLanguage.json" \
        && ok "离线包语法含宏高亮" || bad "离线包语法缺宏高亮"
    ls "$PKG_ROOT"/tools/zhc-dialect-*.vsix >/dev/null 2>&1 \
        && ok "离线包含 .vsix 扩展包" || bad "离线包缺 .vsix（需 node/npx 打包）"
    # 一键安装脚本（建议 C9）：--file 本地包 + sha256 强制校验
    INST_HASH="$(sha256sum "$PKG_TGZ" | cut -d' ' -f1)"
    if bash "$REPO/scripts/install.sh" --file "$PKG_TGZ" --sha256 "$INST_HASH" --prefix "$WORK/zhc-inst" \
        >"$WORK/install.log" 2>&1 && [ -x "$WORK/zhc-inst/bin/zhc" ]; then
        ok "install.sh 本地安装（sha256 校验 + 软链）"
    else
        bad "install.sh 安装失败（见 $WORK/install.log）"
        tail -4 "$WORK/install.log"
    fi
    ( "$WORK/zhc-inst/bin/zhc" run "$ZHC_DIR/examples/hello.zc" ) >"$WORK/inst_run.out" 2>&1 \
        && expect_output "$WORK/inst_run.out" "你好，仓颉" "install.sh 产物可运行" \
        || bad "install.sh 产物运行失败"
else
    bad "未找到离线包产物"
fi

# ---------- 11. 语法检查 ----------
step "11. 静态语法检查（脚本/JSON/JS/Python）"
SYNTAX_FAIL=0
bash -n "$REPO/scripts/release.sh" "$REPO/scripts/acceptance.sh" \
    "$REPO/scripts/setup-cangjie.sh" "$REPO/scripts/tutorial-check.sh" \
    "$REPO/scripts/install.sh" "$REPO/scripts/sdk-smoke.sh" 2>/dev/null || SYNTAX_FAIL=1
python3 -c "import ast,sys
for p in ['$REPO/tools/gen_highlight.py','$REPO/tools/gen_error_dict.py','$REPO/tools/gen_words.py',
          '$REPO/tools/diag_coverage.py','$REPO/tools/gen_ui_packs.py',
          '$REPO/tools/ui_translations_en.py','$REPO/tools/ui_translations_ru.py',
          '$REPO/tools/mock_llm.py',
          '$REPO/scripts/lsp-smoke.py',
          '$REPO/scripts/check-libs.py',
          '$REPO/.verify/extract.py','$REPO/.verify/combo_check.py']:
    ast.parse(open(p,encoding='utf-8').read())" 2>/dev/null || SYNTAX_FAIL=1
if command -v node >/dev/null 2>&1; then
    node --check "$REPO/tools/vscode-extension/extension.js" 2>/dev/null || SYNTAX_FAIL=1
    node --check "$REPO/tools/vscode-extension/lib/fullwidth.js" 2>/dev/null || SYNTAX_FAIL=1
    node --check "$REPO/tools/vscode-extension/lib/words.js" 2>/dev/null || SYNTAX_FAIL=1
    node --check "$REPO/tools/vscode-extension/lib/compare.js" 2>/dev/null || SYNTAX_FAIL=1
    node "$REPO/tools/vscode-extension/test/fullwidth.test.js" >/dev/null 2>&1 || SYNTAX_FAIL=1   # 建议 E4：全角转换纯函数单测
    node "$REPO/tools/vscode-extension/test/words.test.js" >/dev/null 2>&1 || SYNTAX_FAIL=1      # 词表补全/悬停纯逻辑单测
    node "$REPO/tools/vscode-extension/test/compare.test.js" >/dev/null 2>&1 || SYNTAX_FAIL=1    # 对照视图行模型/HTML 纯逻辑单测
fi
python3 -c "import json
json.load(open('$REPO/tools/vscode-extension/package.json'))
json.load(open('$REPO/tools/vscode-extension/syntaxes/zhc.tmLanguage.json'))
json.load(open('$REPO/tools/vscode-extension/lib/zhc-words.json'))" 2>/dev/null || SYNTAX_FAIL=1
[ "$SYNTAX_FAIL" = 0 ] && ok "全部静态检查通过" || bad "存在静态检查失败项"

# ---------- 12. 教程代码全量验证（150+ 代码块；ZHC_SKIP_TUTORIAL=1 跳过） ----------
if [ "${ZHC_SKIP_TUTORIAL:-}" = "1" ]; then
    step "12. 教程代码全量验证（已跳过：ZHC_SKIP_TUTORIAL=1）"
else
    step "12. 教程代码全量验证（《中文仓颉程序设计》全部代码块 + 组合验证）"
    export ZHC_BIN="$ZHC_BIN" ZHC_LANG_PACKS="$ZHC_DIR"
    if VERIFY_ROOT="$WORK/tutorial-verify" bash "$REPO/scripts/tutorial-check.sh" >"$WORK/tutorial_check.log" 2>&1; then
        ok "教程全部代码块实测通过（含 19.5 组合验证）"
    else
        bad "教程代码验证失败（见 $WORK/tutorial_check.log 末尾）"
        tail -8 "$WORK/tutorial_check.log"
    fi
fi

# ---------- 13. 生成物防漂移（errors.toml/错误字典与翻译表同步；建议 E3 加 ru 链；ui.toml 三包） ----------
step "13. 生成物防漂移（zh/ru errors.toml + errors-dictionary.md + ui.toml 三包重生成 diff 为空）"
# zh 全集式与 ru 增量式生成链（tools/gen_full_errors.py --lang zh|ru，--out 供 diff）：
# 翻译表/修复示例改动后忘记重生成 → 此处直接报失败，提示运行对应命令
ZHE_GEN="$WORK/errors-zh.gen.toml"
RU_GEN="$WORK/errors-ru.gen.toml"
if python3 "$REPO/tools/gen_full_errors.py" --lang zh --out "$ZHE_GEN" >/dev/null 2>&1 \
    && diff -q "$ZHE_GEN" "$REPO/zhc/lang-packs/zh/errors.toml" >/dev/null 2>&1; then
    ok "zh errors.toml 与翻译表同步（--lang zh 重新生成无差异）"
else
    bad "zh errors.toml 已过期——请运行 python3 tools/gen_full_errors.py"
fi
if python3 "$REPO/tools/gen_full_errors.py" --lang ru --out "$RU_GEN" >/dev/null 2>&1 \
    && diff -q "$RU_GEN" "$REPO/zhc/lang-packs/ru/errors.toml" >/dev/null 2>&1; then
    ok "ru errors.toml 与翻译表同步（--lang ru 重新生成无差异）"
else
    bad "ru errors.toml 已过期——请运行 python3 tools/gen_full_errors.py --lang ru"
fi
GEN_OUT="$WORK/errors-dict.gen.md"
if python3 "$REPO/tools/gen_error_dict.py" "$REPO/zhc/lang-packs/zh/errors.toml" "$GEN_OUT" >/dev/null 2>&1 \
    && diff -q "$GEN_OUT" "$REPO/docs/errors-dictionary.md" >/dev/null 2>&1; then
    ok "errors-dictionary.md 与语言包同步（重新生成无差异）"
else
    bad "errors-dictionary.md 已过期——请运行 python3 tools/gen_error_dict.py 重新生成"
fi
# ui.toml 三包防漂移（tools/gen_ui_packs.py --out-dir 重生成 diff 为空）：
# 翻译源 ui_translations_en/ru.py → en/ru/zh 三包 ui.toml；zh 仅测试词典（界面消息
# 缺键回退 = zh 模板原文）。代码新增 UI 串未同步翻译 → 生成器校验失败即报错。
UI_GEN="$WORK/ui-packs-gen"
if python3 "$REPO/tools/gen_ui_packs.py" --out-dir "$UI_GEN" >/dev/null 2>&1 \
    && diff -q "$UI_GEN/en/ui.toml" "$REPO/zhc/lang-packs/en/ui.toml" >/dev/null 2>&1 \
    && diff -q "$UI_GEN/ru/ui.toml" "$REPO/zhc/lang-packs/ru/ui.toml" >/dev/null 2>&1 \
    && diff -q "$UI_GEN/zh/ui.toml" "$REPO/zhc/lang-packs/zh/ui.toml" >/dev/null 2>&1; then
    ok "ui.toml 三包与代码 UI 串同步（重生成无差异；EN/RU 界面消息 219 键全覆盖）"
else
    bad "ui.toml 已过期/漏翻——请运行 python3 tools/gen_ui_packs.py（新增 UI 串后须补 ui_translations_en/ru.py 翻译）"
fi
# 语言跟随冒烟（T3 核心目标：提示语言 = 用户语言，非固定中文）：
# ZHCLANG=en → 英文提示；ZHCLANG=ru → 俄语提示（缺键回退 zh 原文即视为漏翻）
( cd "$WORK" && ZHC_LANG_PACKS="$ZHC_DIR" ZHCLANG=en "$ZHC_BIN" run nope.zc ) >"$WORK/en_ui.out" 2>&1
expect_output "$WORK/en_ui.out" "File not found: nope.zc" "语言跟随：ZHCLANG=en 输出英文提示"
( cd "$WORK" && ZHC_LANG_PACKS="$ZHC_DIR" ZHCLANG=ru "$ZHC_BIN" run nope.zc ) >"$WORK/ru_ui.out" 2>&1
expect_output "$WORK/ru_ui.out" "Файл не найден: nope.zc" "语言跟随：ZHCLANG=ru 输出俄语提示"

# ---------- 14. LSP 端到端冒烟 ----------
step "14. LSP 端到端冒烟（行帧协议 initialize → didOpen → 中文诊断推送）"
if [ "${ZHC_SKIP_LSP:-}" = "1" ]; then
    echo "（已跳过：ZHC_SKIP_LSP=1）"
else
    if CANGJIE_HOME="$CANGJIE_HOME" ZHC_BIN="$ZHC_BIN" python3 "$REPO/scripts/lsp-smoke.py" \
        "$ZHC_BIN" "$WORK/lsp-smoke" >"$WORK/lsp_smoke.log" 2>&1; then
        ok "LSP 冒烟通过（initialize/诊断推送/干净退出）"
    else
        bad "LSP 冒烟失败（见 $WORK/lsp_smoke.log 末尾）"
        tail -6 "$WORK/lsp_smoke.log"
    fi
fi

# ---------- 15. 诊断码触发率（建议 B7：ZHC_DIAG_STATS 埋点聚合） ----------
step "15. 诊断码触发率（全程命中码聚合；0 触发清单 = 黄金样例/精翻候选）"
DIAG_REPORT="$WORK/diag-report.txt"
if [ -s "$WORK/diag-stats.txt" ] \
    && python3 "$REPO/tools/diag_coverage.py" "$WORK/diag-stats.txt" --top 0 >"$DIAG_REPORT" 2>&1; then
    HIT_N="$(sed -n 's/^实战命中（去重）：\([0-9]*\).*/\1/p' "$DIAG_REPORT")"
    MISS_N="$(sed -n 's/^0 触发清单：\([0-9]*\).*/\1/p' "$DIAG_REPORT")"
    ok "触发率统计生效（命中 ${HIT_N:-?} 个码，0 触发 ${MISS_N:-?} 条——语料有限≠死码）"
else
    bad "触发率统计失败（ZHC_DIAG_STATS 未收集到命中）"
fi

# ---------- 16. 教程用词 ↔ 词表一致性（建议 E2：声明豁免后疑似漏词门禁） ----------
step "16. 教程用词 ↔ 词表一致性（check_langpack --gate）"
if python3 "$REPO/.verify/check_langpack.py" --gate >"$WORK/langpack_check.txt" 2>&1; then
    ok "教程非声明 token 全部在词表（疑似漏词 0；自定义标识符按 zhc 豁免语义剔除）"
    grep -E "教程 token|词表规模|词表 0 使用" "$WORK/langpack_check.txt" | sed 's/^/    /'
else
    bad "疑似漏词非空（教程代码用到词表外 token，见 $WORK/langpack_check.txt）"
    head -8 "$WORK/langpack_check.txt"
fi

# ---------- 17. AI 辅助验收（设计 §17.5：mock 驱动，不依赖外网/Ollama） ----------
step "17. AI 辅助（mock LLM 驱动 zhc translate / zhc ai 全链路）"
AI_WORK="$WORK/ai-run"
AI_PACKS="$WORK/ai-packs"
rm -rf "$AI_WORK" "$AI_PACKS"
mkdir -p "$AI_WORK/demo_shape/src/ui" "$AI_PACKS"
cp -r "$ZHC_DIR/lang-packs" "$AI_PACKS/lang-packs"
# mock 隔离：清掉仓库 crates 种子（libs 润色由 2f 段独立验证），
# AI 门禁契约保持确定性（首轮 2 条故意违规，见 mock_llm.py 注释）
rm -f "$AI_PACKS/lang-packs/zh/crates/"*.toml
cat >"$AI_WORK/demo_shape/cjpm.toml" <<'EOF'
[package]
cjc-version = "1.0.5"
name = "demo_shape"
version = "0.1.0"
output-type = "static"
EOF
cat >"$AI_WORK/demo_shape/src/shape.cj" <<'EOF'
/** 图形基类：承载名称。 */
public class Shape {
    var 名称: String
    public init(名称: String) { this.名称 = 名称 }
}

/** 面板容器。 */
public class Panel {
    public init() {}
}

/** 二维坐标点。 */
public class Point {
    public init() {}
}

/** 计算面积：宽 × 高。 */
public func area(宽: Float64, 高: Float64): Float64 {
    return 宽 * 高
}

/** 渲染图形为文本描述。 */
public func render(形状: Shape): String {
    return 形状.名称
}
EOF
cat >"$AI_WORK/demo_shape/src/ui/panel.cj" <<'EOF'
// 面板渲染子模块（示例：目录存在即参与模块路径映射；注意本文件不声明 public，
// 否则会被 zhc translate 计入公开 API 提取，破坏 mock 预设的 5 键契约）。
EOF
# mock LLM：translate 首轮含 2 条故意违规（area→函数 撞关键字；render→形状 与
# Shape 译名重复）验证门禁重试；ai 场景首轮类型错误 → 次轮正确（见 tools/mock_llm.py 注释）
PORT_AI=18911
python3 "$REPO/tools/mock_llm.py" $PORT_AI >"$WORK/ai-mock.log" 2>&1 &
MOCK_PID=$!
sleep 1
( cd "$AI_WORK" && ZHC_LANG_PACKS="$AI_PACKS" \
    ZHC_AI_BASE="http://127.0.0.1:$PORT_AI/v1" ZHC_AI_KEY=sk-acceptance ZHC_AI_MODEL=mock \
    "$ZHC_BIN" translate demo_shape --share demo_shape >"$WORK/ai-translate.out" 2>&1 )
T_OUT="$WORK/ai-translate.out"
if grep -q "检测到 2 条映射冲突" "$T_OUT" && grep -q "翻译 5，恒等保留 0" "$T_OUT" \
    && grep -q "模块路径映射 1 条" "$T_OUT" \
    && grep -q "已导出共享目录" "$T_OUT"; then
    ok "translate 全链路（冲突门禁重试 → 修正采纳 → 模块路径 → --share 导出）"
else
    bad "translate 流程断言失败（见 $T_OUT）"
    tail -5 "$T_OUT"
fi
CRATE="$AI_PACKS/lang-packs/zh/crates/demo_shape.toml"
if grep -q '"面积" = "area"' "$CRATE" && grep -q '"渲染" = "render"' "$CRATE" \
    && ! grep -q '"函数" = "area"' "$CRATE" \
    && grep -q '"demo_shape.界面" = "demo_shape.ui"' "$CRATE"; then
    ok "crates 映射采纳修正版（无撞关键字/重复条目）+ 模块路径段"
else
    bad "crates 映射内容断言失败（见 $CRATE）"
    cat "$CRATE"
fi
if [ -f "$AI_WORK/zhc-共享-demo_shape/lang-packs/zh/crates/demo_shape.toml" ] \
    && [ -f "$AI_WORK/zhc-共享-demo_shape/README.md" ]; then
    ok "共享目录结构齐全（lang-packs 分层 + README 安装说明）"
else
    bad "共享目录结构缺失（见 $AI_WORK/zhc-共享-demo_shape/）"
fi
( cd "$AI_WORK" && ZHC_LANG_PACKS="$AI_PACKS" \
    ZHC_AI_BASE="http://127.0.0.1:$PORT_AI/v1" ZHC_AI_KEY=sk-acceptance ZHC_AI_MODEL=mock \
    "$ZHC_BIN" ai "打印九九乘法表" -o ai-out.zc --iter 3 >"$WORK/ai-write.out" 2>&1 )
A_OUT="$WORK/ai-write.out"
if grep -q "第 1 轮编译失败" "$A_OUT" && grep -q "编译通过（第 2 轮）" "$A_OUT"; then
    ok "ai 迭代闭环（首轮失败 → 诊断回喂 → 第 2 轮通过）"
else
    bad "ai 迭代闭环断言失败（见 $A_OUT）"
    tail -6 "$A_OUT"
fi
if [ -f "$AI_WORK/ai-out.zc" ] && grep -q "主函数" "$AI_WORK/ai-out.zc"; then
    RUN_OUT="$( cd "$AI_WORK" && ZHC_LANG_PACKS="$AI_PACKS" "$ZHC_BIN" run ai-out.zc 2>&1 )"
    if printf '%s' "$RUN_OUT" | grep -q "^42$"; then
        ok "ai 产物可运行（zhc run 输出 42）"
    else
        bad "ai 产物运行输出异常（期望 42，实际见下）"
        printf '%s\n' "$RUN_OUT" | tail -5
    fi
else
    bad "ai 输出文件缺失或非方言源码（见 $AI_WORK/ai-out.zc）"
fi
kill "$MOCK_PID" 2>/dev/null
if grep -q "translate=3" "$WORK/ai-mock.log" && grep -q "ai=2" "$WORK/ai-mock.log"; then
    ok "mock 调用计数精确（translate 3 次 = 首轮+重试+模块路径；ai 2 次 = 首轮+修复）"
else
    bad "mock 调用计数异常（见 $WORK/ai-mock.log）"
    cat "$WORK/ai-mock.log"
fi

# ---------- 18. 翻译资源共享（设计 §18：本地注册表 + HTTP 服务端双向闭环） ----------
step "18. 翻译资源共享（share publish/fetch：本地目录 + HTTP 服务端）"
SHARE_WORK="$WORK/share-run"
SHARE_REG="$WORK/share-registry"
SHARE_PACKS="$WORK/share-packs"
rm -rf "$SHARE_WORK" "$SHARE_REG" "$SHARE_PACKS"
mkdir -p "$SHARE_WORK" "$SHARE_PACKS"
cp -r "$ZHC_DIR/lang-packs" "$SHARE_PACKS/lang-packs"
cat >"$SHARE_WORK/demo_math.toml" <<'EOF'
# demo_math 共享映射样例（acceptance 段 18）
["标识符"]
"加法" = "add"
"减法" = "sub"
["模块路径"]
"数学库" = "demo_math"
EOF
# ① 本地目录注册表：publish → 落盘 + index 登记
( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="$SHARE_REG" \
    "$ZHC_BIN" share publish demo_math.toml --desc "验收样例" >"$WORK/share-pub1.out" 2>&1 ) \
    && ok "publish 本地注册表" || bad "publish 本地注册表失败（$(tail -1 "$WORK/share-pub1.out")）"
if [ -f "$SHARE_REG/crates/zh/demo_math.toml" ] \
    && grep -q '"名称": "demo_math"' "$SHARE_REG/index.json" \
    && grep -q '"校验和"' "$SHARE_REG/index.json"; then
    ok "publish 落盘 + index 登记（含键数/校验和元数据）"
else
    bad "publish 产物不完整（见 $SHARE_REG）"
    cat "$SHARE_REG/index.json" 2>/dev/null || true
fi
# 重复 publish = 更新语义：同名同语言条目幂等覆盖
( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="$SHARE_REG" \
    "$ZHC_BIN" share publish demo_math.toml --desc "验收样例2" >"$WORK/share-pub1b.out" 2>&1 )
SHARE_COUNT="$(grep -c '"名称": "demo_math"' "$SHARE_REG/index.json" || true)"
if [ "$SHARE_COUNT" = "1" ] && grep -q '"描述": "验收样例2"' "$SHARE_REG/index.json"; then
    ok "重复 publish 幂等（同名同语言覆盖更新）"
else
    bad "重复 publish 非幂等（条目数 $SHARE_COUNT，见 $SHARE_REG/index.json）"
fi
# fetch：按需下载单个映射到指定目录（校验和 + 门禁 + 安装）
( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="$SHARE_REG" \
    "$ZHC_BIN" share fetch demo_math --dir "$SHARE_WORK/fetched" >"$WORK/share-fetch.out" 2>&1 ) \
    && grep -q "已安装" "$WORK/share-fetch.out" \
    && grep -q '"加法" = "add"' "$SHARE_WORK/fetched/demo_math.toml" \
    && ok "fetch 按需下载（校验和 + 门禁通过，单文件安装）" \
    || bad "fetch 失败（$(tail -2 "$WORK/share-fetch.out" | tr '\n' ' ')）"
# 篡改拦截：注册表文件被改 → 校验和不符 → 拒绝安装
cp "$SHARE_REG/crates/zh/demo_math.toml" "$WORK/demo_math.bak"
printf 'x' >>"$SHARE_REG/crates/zh/demo_math.toml"
if ( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="$SHARE_REG" \
        "$ZHC_BIN" share fetch demo_math --dir "$SHARE_WORK/tampered" >"$WORK/share-tamper.out" 2>&1 ); then
    bad "篡改映射未被拦截（见 $WORK/share-tamper.out）"
else
    if grep -q "完整性校验失败" "$WORK/share-tamper.out"; then
        ok "篡改拦截（校验和不符拒绝安装）"
    else
        bad "篡改拦截报错异常（$(tail -1 "$WORK/share-tamper.out")）"
    fi
fi
cp "$WORK/demo_math.bak" "$SHARE_REG/crates/zh/demo_math.toml"
# ② HTTP 服务端闭环：POST 上传 → GET 按需下载 → list 浏览
SHARE_PORT=18912
python3 "$REPO/tools/share_server.py" --port $SHARE_PORT --registry "$SHARE_REG" \
    >"$WORK/share-server.log" 2>&1 &
SHARE_PID=$!
sleep 1
( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="http://127.0.0.1:$SHARE_PORT" \
    "$ZHC_BIN" share publish demo_math.toml --desc "HTTP 发布" >"$WORK/share-pub2.out" 2>&1 ) \
    && ok "publish HTTP 端点（POST share-publish）" \
    || bad "publish HTTP 失败（$(tail -2 "$WORK/share-pub2.out" | tr '\n' ' ')）"
( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="http://127.0.0.1:$SHARE_PORT" \
    "$ZHC_BIN" share fetch demo_math --dir "$SHARE_WORK/fetched-http" >"$WORK/share-fetch2.out" 2>&1 ) \
    && grep -q '"减法" = "sub"' "$SHARE_WORK/fetched-http/demo_math.toml" \
    && ok "fetch HTTP 按需下载闭环（GET 单文件）" \
    || bad "fetch HTTP 失败（$(tail -2 "$WORK/share-fetch2.out" | tr '\n' ' ')）"
( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="http://127.0.0.1:$SHARE_PORT" \
    "$ZHC_BIN" share list >"$WORK/share-list.out" 2>&1 ) \
    && grep -q "demo_math" "$WORK/share-list.out" \
    && ok "share list 浏览索引" || bad "share list 失败（$(tail -1 "$WORK/share-list.out")）"
( cd "$SHARE_WORK" && ZHC_LANG_PACKS="$SHARE_PACKS" ZHC_SHARE_BASE="http://127.0.0.1:$SHARE_PORT" \
    "$ZHC_BIN" share search demo >"$WORK/share-search.out" 2>&1 ) \
    && grep -q "命中" "$WORK/share-search.out" \
    && ok "share search 关键词检索" || bad "share search 失败（$(tail -1 "$WORK/share-search.out")）"
kill "$SHARE_PID" 2>/dev/null

# ---------- 汇总 ----------
echo
echo "==================== 验收汇总 ===================="
echo "共 $((PASS + FAIL)) 项断言，通过：$PASS    失败：$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '失败步骤：\n'
    for s in "${FAILED_STEPS[@]}"; do echo "  - $s"; done
    exit 1
fi
echo "✅ zhc 全量验收通过（蓝图 §14.3 交付物清单）"
