package zhc

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// zhc fmt 排版器单元测试：缩进/括号内空格/逗号冒号/运算符两侧空格/控制词空格、
// 字符串与注释保护、泛型与范围透传、一元 +/-、幂等性、跨行块注释、变化行计数。

/** 构造控制词集合（官方值 if/while/for/match 的方言键——与 cmdFmt 白名单一致）。 */
func mkKwSpace(): Array<String> {
    let a = ArrayList<String>()
    a.add("如果")
    a.add("当")
    a.add("对于")
    a.add("匹配")
    return a.toArray()
}

func fmtTo(src: String): String {
    let cnt = FmtCount()
    return fmtSource(src, mkKwSpace(), cnt)
}

@Test
public func testFmtIndentAndSpaces() {
    // 缩进 4 空格/层 + 运算符两侧空格 + 控制词 ( 前空格 + { 前空格 + 行首 } 退级
    // 单行块不拆行；a>0 紧贴时 > 透传不加空格（泛型保护，见 testFmtGenericRangeUntouched）
    let src = "主函数(){\n让 a=1\n如果(a>0){打印行(a+1)}\n}\n"
    let want = "主函数() {\n    让 a = 1\n    如果 (a>0) {打印行(a + 1)}\n}\n"
    @Expect(fmtTo(src), want)
}

@Test
public func testFmtCommaColonArray() {
    // 逗号/冒号后空格、括号内侧清理、方括号列表
    let out = fmtTo("让 列表=[1 ,2,  3]\n让 名:字符串=\"x\"\n调( 名 )\n")
    @Expect(out, "让 列表 = [1, 2, 3]\n让 名: 字符串 = \"x\"\n调(名)\n")
}

@Test
public func testFmtGenericRangeUntouched() {
    // 泛型 <...> 与范围 .. 不加空格；字符串内容不动
    let out = fmtTo("让 映射=哈希映射<字符串,整数>()\n对于(值 in 0..3){打印行(\"a=b 总=x+1\")}\n")
    @Expect(out, "让 映射 = 哈希映射<字符串, 整数>()\n对于 (值 in 0..3) {打印行(\"a=b 总=x+1\")}\n")
}

@Test
public func testFmtUnaryMinus() {
    // 一元 +/-：-1 贴附；二元后的一元保留 MUST 空格（a - -1）；f(a, -1)
    @Expect(fmtTo("可变 x=a - -1\n"), "可变 x = a - -1\n")
    @Expect(fmtTo("让 y=取反(-3)\n"), "让 y = 取反(-3)\n")
}

@Test
public func testFmtKeywordNoSpaceAfterNameLike() {
    // 非控制词关键字（主函数/函数）后的 ( 不加空格；调用紧贴
    @Expect(fmtTo("主函数() {\n}\n"), "主函数() {\n}\n")
    @Expect(fmtTo("函数 双倍(数:整数){返回 数*2}\n"), "函数 双倍(数: 整数) {返回 数 * 2}\n")
}

@Test
public func testFmtCommentsAndQuotesProtected() {
    // 行注释内容与缩进（跟随代码深度）、字符串内全角/符号原样
    let src = "主函数() {\n打印行(\"（全角）  a=b  //不是注释\")\n//  注释  原样\n}\n"
    let want = "主函数() {\n    打印行(\"（全角）  a=b  //不是注释\")\n    //  注释  原样\n}\n"
    @Expect(fmtTo(src), want)
}

@Test
public func testFmtBlockCommentSpan() {
    // 跨行块注释：起始行按代码缩进（/* 行不丢字符），中间行原样，*/ 后恢复格式化
    let src = "主函数() {\n/* 多行注释\n   注释  { 不算 }  深度\n*/\n打印行(1)\n}\n"
    let want = "主函数() {\n    /* 多行注释\n   注释  { 不算 }  深度\n*/\n    打印行(1)\n}\n"
    @Expect(fmtTo(src), want)
}

@Test
public func testFmtIdempotent() {
    // 已格式化文本再格式化无变化（尾注前 1 空格为 fmt 规范形态）
    let src = "主函数() {\n    如果 (a>0) {\n        打印行(a + 1) // 尾注\n    }\n}\n"
    @Expect(fmtTo(src), src)
}

@Test
public func testFmtCountLines() {
    // 变化行计数：{ 前补空 1 行 + 缩进变化 1 行；末行 } 无变化不计
    let cnt = FmtCount()
    fmtSource("主函数(){\n打印行(1)\n}\n", mkKwSpace(), cnt)
    @Expect(cnt.lines, Int64(2))
}

@Test
public func testFmtElseSameLine() {
    // } 否则 { 同行排版与单行块保持
    let out = fmtTo("如果(a>0){打印行(1)}否则{打印行(2)}\n")
    @Expect(out, "如果 (a>0) {打印行(1)} 否则 {打印行(2)}\n")
}
