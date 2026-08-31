package zhc

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 别名替换单元测试（设计 §14.1 单元层：转译引擎核心 alias.cj）
// 输入为词法转译后文本（关键字已是官方），验证两遍扫描：豁免集收集 + 逐 token 替换

func mkAliasLang(): LangPack {
    let keywords = HashMap<String, String>()
    let macros = HashMap<String, String>()
    let mods = HashMap<String, String>()
    let aliases = HashMap<String, String>()
    aliases.add("打印行", "println")
    aliases.add("向量", "ArrayList")
    aliases.add("整数", "Int64")
    aliases.add("字符串", "String")
    aliases.add("有值", "Some")
    let diags = HashMap<String, DiagEntry>()
    let msgs = HashMap<String, DiagEntry>()
    let ui = HashMap<String, String>()
    return LangPack("zh", "中文", ArrayList<String>(), keywords, macros, mods,
        aliases, diags, msgs, ui)
}

@Test
public func testAliasBasic() {
    // 函数名/类型名替换 + 计数
    let r = replaceAliases("打印行(\"你好\")", mkAliasLang())
    @Expect(r.text, "println(\"你好\")")
    @Expect(r.count, Int64(1))
}

@Test
public func testAliasTypeInSignature() {
    // 参数名豁免、类型名替换（声明名后 (...) 内 `:` 后是类型）
    let r = replaceAliases("func 求和(数量: 整数): 整数 { return 数量 }", mkAliasLang())
    @Expect(r.text, "func 求和(数量: Int64): Int64 { return 数量 }")
    @Expect(r.count, Int64(2))
}

@Test
public func testAliasDeclNameExempt() {
    // 声明名豁免：func 后标识符及全文件裸使用处均不替换（§3.4/§3.5）
    let r = replaceAliases("func 打印行() {}\n打印行()", mkAliasLang())
    @Expect(r.text, "func 打印行() {}\n打印行()")
    @Expect(r.count, Int64(0))
}

@Test
public func testAliasStringProtected() {
    // 字符串内容不替换
    let r = replaceAliases("println(\"打印行 向量\")", mkAliasLang())
    @Expect(r.text, "println(\"打印行 向量\")")
    @Expect(r.count, Int64(0))
}

@Test
public func testAliasBacktickProtected() {
    // 反引号原始标识符：别名阶段跳过（强制原文）
    let r = replaceAliases("`打印行`()", mkAliasLang())
    @Expect(r.text, "`打印行`()")
    @Expect(r.count, Int64(0))
}

@Test
public func testAliasForBindingExempt() {
    // for (键 in ...)：绑定名豁免，in 后表达式照常替换
    let r = replaceAliases("for (键 in 向量) {}", mkAliasLang())
    @Expect(r.text, "for (键 in ArrayList) {}")
    @Expect(r.count, Int64(1))
}

@Test
public func testAliasCaseCtorPattern() {
    // case 构造器模式（§13.1 第 40 条修复）：构造器名在别名表 → 替换，
    // 括号内绑定豁免（caseCand 延迟决定）
    let r = replaceAliases("case 有值(值) => 值", mkAliasLang())
    @Expect(r.text, "case Some(值) => 值")
    @Expect(r.count, Int64(1))
}

@Test
public func testAliasInterpolation() {
    // 字符串内 ${} 插值段按代码态递归替换（scanAliasInterp 括号栈配对）
    // 注：输入用 Rune 拼接构造，避免仓颉编译期把 `${}` 当字符串插值展开
    let dollar = String([r'$'])
    let r = replaceAliases("println(\"x" + dollar + "{向量}\")", mkAliasLang())
    @Expect(r.text, "println(\"x" + dollar + "{ArrayList}\")")
    @Expect(r.count, Int64(1))
}

@Test
public func testAliasMemberAfterDot() {
    // `.段` 照常替换（§3.5 闭环），豁免集在 `.` 后同样生效
    let r = replaceAliases("obj.打印行()", mkAliasLang())
    @Expect(r.text, "obj.println()")
    @Expect(r.count, Int64(1))
}
