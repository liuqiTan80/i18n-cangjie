package zhc

import std.unittest.*
import std.unittest.testmacro.*

// 词法层单元测试（设计 §14.1 单元层：词法转译；§14.2 对抗：标识符边界）

func lexTestLang(): LangPack {
    return loadLangPack("./", "zh").getOrThrow()
}

@Test
public func testIdentStart() {
    @Expect(isIdentStart(Rune(97)), true)      // 'a' ASCII 字母
    @Expect(isIdentStart(Rune(95)), true)      // '_'
    @Expect(isIdentStart(Rune(48)), false)     // '0' 数字不能开头
    @Expect(isIdentStart(Rune(20013)), true)   // '中' 非 ASCII 可开头
    @Expect(isIdentStart(Rune(64)), false)     // '@' 符号不可开头
}

@Test
public func testIdentPart() {
    @Expect(isIdentPart(Rune(97)), true)       // 字母
    @Expect(isIdentPart(Rune(48)), true)       // 数字可续
    @Expect(isIdentPart(Rune(95)), true)       // 下划线
    @Expect(isIdentPart(Rune(20013)), true)    // 中文可续
    @Expect(isIdentPart(Rune(45)), false)      // '-' 不可续
}

@Test
public func testIsSpace() {
    @Expect(isSpace(Rune(32)), true)           // 空格
    @Expect(isSpace(Rune(9)), true)            // \t
    @Expect(isSpace(Rune(10)), true)           // \n
    @Expect(isSpace(Rune(13)), true)           // \r
    @Expect(isSpace(Rune(97)), false)
}

@Test
public func testScanQuoted() {
    // 输入 "a\"b"（含转义引号）：两端引号 + a + \ + " + b = 6 runes
    let s = "\"a\\\"b\"".toRuneArray()
    let (tok, next) = scanQuoted(s, 0, s.size, r'"')
    @Expect(tok, "\"a\\\"b\"")
    @Expect(next, Int64(6))
}

@Test
public func testScanLineComment() {
    // "// 注释" = 5 runes，\n 在 index 5
    let s = "// 注释\n代码".toRuneArray()
    let (tok, next) = scanLineComment(s, 0, s.size)
    @Expect(tok, "// 注释")
    @Expect(next, Int64(5))
}

@Test
public func testScanBlockComment() {
    // "/* a\nb */" = 9 runes（跨行块注释）
    let s = "/* a\nb */x".toRuneArray()
    let (tok, next) = scanBlockComment(s, 0, s.size)
    @Expect(tok, "/* a\nb */")
    @Expect(next, Int64(9))
}

@Test
public func testScanBlockCommentUnclosed() {
    // 未闭合块注释容错到 end
    let s = "/* abc".toRuneArray()
    let (tok, next) = scanBlockComment(s, 0, s.size)
    @Expect(tok, "/* abc")
    @Expect(next, Int64(6))
}

@Test
public func testTranspileInterpState() {
    // ${} 插值态转译（此前 transpile/插值状态机零覆盖，审计缺口）：
    // 插值段内按代码规则查关键字表，插值段外字符串文本原样。
    // 注意：方言源里的 ${…} 须经 \u{24} 转义构造，避免外层仓颉字符串
    // 把它当插值解析（\u{24} = '$'，源文本中无相邻 ${ 序列）
    let lang = lexTestLang()
    let kwMain = lang.keywords.get("主函数").getOrThrow()
    let r = transpile("打印行(\"值=\u{24}{主函数}!\")", lang)
    // 字符串插值段外的文本原样保留
    @Expect(r.text.indexOf("值=") != None, true)
    @Expect(r.text.indexOf("!\")") != None, true)
    // 插值段内命中关键字表（主函数 → main，保留 ${} 包裹）
    let needle = "\u{24}{" + kwMain + "}"
    @Expect(r.text.indexOf(needle) != None, true)
    // 普通关键字转译照常（打印行在别名表属阶段 3，词法层不动）
    @Expect(r.text.startsWith("打印行("), true)
}

@Test
public func testTranspileAtPendingSemantics() {
    // @ 前缀语义（§5.1 第 4 条；回归：此前 @ 后空白/注释不清标志，
    // 导致其后标识符误入宏表查询）
    let lang = lexTestLang()
    // @ 后紧跟标识符：只查宏表（测试 ∈ 宏表 → Test）
    @Expect(transpile("@测试(1)", lang).text, "@Test(1)")
    // @ 后遇空白：清除宏前缀，恢复关键字查询（测试不在关键字表 → 原样）
    @Expect(transpile("@ 测试(1)", lang).text, "@ 测试(1)")
    // @ 后隔行注释：同样清除
    @Expect(transpile("@ // 注释\n测试(1)", lang).text, "@ // 注释\n测试(1)")
}
