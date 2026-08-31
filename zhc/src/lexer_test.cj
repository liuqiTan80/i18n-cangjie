package zhc

import std.unittest.*
import std.unittest.testmacro.*

// 词法层单元测试（设计 §14.1 单元层：词法转译；§14.2 对抗：标识符边界）

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
