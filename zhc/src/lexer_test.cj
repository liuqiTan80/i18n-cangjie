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
public func testXidStartClass() {
    // P-7：与 cjc 1.0.5 实测 XID 语义对齐（首字符 = XID_Start）
    @Expect(isIdentStart(Rune(0xE9)), true)       // é 拉丁扩展
    @Expect(isIdentStart(Rune(0x3042)), true)     // あ 平假名
    @Expect(isIdentStart(Rune(0x30E1)), true)     // メ 片假名
    @Expect(isIdentStart(Rune(0x3005)), true)     // 々 Lm 可开头（cjc 实测通过）
    @Expect(isIdentStart(Rune(0x30FC)), true)     // ー 长音 Lm
    @Expect(isIdentStart(Rune(0xFF21)), true)     // Ａ 全角字母（Lu）
    @Expect(isIdentStart(Rune(0x20000)), true)    // 𠀀 CJK 扩展 B（非 BMP）
    @Expect(isIdentStart(Rune(0x915)), true)      // न 天城文
    @Expect(isIdentStart(Rune(0x627)), true)      // ا 阿拉伯
    @Expect(isIdentStart(Rune(0x3000)), false)    // 全角空格（Zs）不可开头（cjc 实测拒）
    @Expect(isIdentStart(Rune(0x301)), false)     // 组合音标 Mn 不可开头
    @Expect(isIdentStart(Rune(0x1F600)), false)   // emoji 不可开头
    @Expect(isIdentStart(Rune(0x30FB)), false)    // ・ 不可开头（cjc 实测拒）
    @Expect(isIdentStart(Rune(0xB2)), false)      // ² 不可开头
}

@Test
public func testXidPartClass() {
    @Expect(isIdentPart(Rune(0x301)), true)       // 组合音标可续（cjc 实测 cafe+U+301 通过）
    @Expect(isIdentPart(Rune(0x94D)), true)       // 天城文 virama 可续（नमस्ते 实测通过）
    @Expect(isIdentPart(Rune(0x3000)), false)     // 全角空格不可续
    @Expect(isIdentPart(Rune(0x1F600)), false)    // emoji 不可续
    @Expect(isIdentPart(Rune(0x30FB)), false)     // ・ 不可续（cjc 实测拒）
    @Expect(isIdentPart(Rune(0x2014)), false)     // — 破折号不可续
}

@Test
public func testTranspileNonXidSplits() {
    // P-7 回归：非 XID 字符（全角空格/emoji）不再被并入标识符 token，
    // 两侧词可独立查表（旧实现 Rune>=128 全收会把“如果　否则”并成死词）
    let lang = lexTestLang()
    @Expect(transpile("如果　否则", lang).text, "if　else")
    @Expect(transpile("让😀可变", lang).text, "let😀var")   // 词表键两侧独立命中
    @Expect(transpile("打印行(1😀x)", lang).text, "打印行(1😀x)")  // 数字/emoji 不透传吞并
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
public func testTranspileStringProtect() {
    // 回归：scanInterpString 曾把开引号当闭引号（缺「先输出开引号」步骤），
    // 字符串内容落入外层代码态扫描——词表词被误替换、`//` 误入注释态吞同行代码。
    let lang = lexTestLang()
    // 插值段外文本含关键字：原样保留（不再误替换）
    @Expect(transpile("打印行(\"让\")", lang).text, "打印行(\"让\")")
    @Expect(transpile("打印行(\"如果 否则\")", lang).text, "打印行(\"如果 否则\")")
    // 字符串含 `//`（URL 场景）：不吞同行后续代码（后续关键字照常转译）
    @Expect(transpile("打印行(\"http://x\"); 让", lang).text, "打印行(\"http://x\"); let")
    // 字符串含转义引号：整体原样（闭引号识别正确，内容仍受保护）
    @Expect(transpile("打印行(\"a\\\"让\\\"b\")", lang).text, "打印行(\"a\\\"让\\\"b\")")
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
