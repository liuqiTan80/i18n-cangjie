package zhc

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 诊断翻译单元测试（设计 §14.1：后缀键匹配 / {q0} 捕获；§7.2 决策链 ②③）

func mkEntries(): HashMap<String, DiagEntry> {
    let m = HashMap<String, DiagEntry>()
    m.add("mismatched types", DiagEntry("类型不匹配", "检查两侧类型", "修复示例"))
    m.add("expected", DiagEntry("期望标识", "", ""))
    m.add("~not found", DiagEntry("未找到", "", ""))
    return m
}

@Test
public func testMatchExact() {
    let m = matchMessage(mkEntries(), "mismatched types")
    @Expect(isSomeOpt(m), true)
    @Expect(m.getOrThrow().entry.template, "类型不匹配")
}

@Test
public func testMatchPrefix() {
    // 完整消息以键为前缀 → 最长前缀命中
    let m = matchMessage(mkEntries(), "mismatched types in expression")
    @Expect(isSomeOpt(m), true)
    @Expect(m.getOrThrow().entry.template, "类型不匹配")
    // 消息含键但非前缀 → 不命中前缀规则
    let miss = matchMessage(mkEntries(), "a mismatched types")
    @Expect(isNoneOpt(miss), true)
}

@Test
public func testMatchSuffix() {
    // ~ 后缀键：锚定消息尾部
    let m = matchMessage(mkEntries(), "identifier not found")
    @Expect(isSomeOpt(m), true)
    @Expect(m.getOrThrow().entry.template, "未找到")
}

@Test
public func testMatchNone() {
    let m1 = matchMessage(mkEntries(), "totally unknown message")
    @Expect(isNoneOpt(m1), true)
    let m2 = matchMessage(mkEntries(), "")
    @Expect(isNoneOpt(m2), true)
}

@Test
public func testExtractQuoted() {
    // 单引号与反引号按出现顺序捕获
    let q = extractQuoted("expected 'Int64', found `String`")
    @Expect(q.size, Int64(2))
    @Expect(q[0], "Int64")
    @Expect(q[1], "String")
}

@Test
public func testFillQuotes() {
    // {q0}/{q1} 按序填充
    @Expect(fillQuotes("类型 {q0} 与 {q1} 不匹配", "expected 'Int64', found 'String'"),
        "类型 Int64 与 String 不匹配")
    // 占位符缺对应值时填空串
    @Expect(fillQuotes("缺 {q0}", "无引号内容"), "缺 ")
}

@Test
public func testFillQuotesOptional() {
    // {q0?} 有值 → 反引号包裹（全集自动条目纯中文模板）
    @Expect(fillQuotes("未定义的变量{q0?}", "undefined variable 'x'"),
        "未定义的变量 `x`")
    // {q0?} 无值 → 空串（消息无引号内容时纯翻译输出）
    @Expect(fillQuotes("泛型类型缺少类型参数{q0?}", "generic type should be used"),
        "泛型类型缺少类型参数")
    // {q0?} 空引号对（''）→ 空串（不输出空反引号对）
    @Expect(fillQuotes("期望内容{q0?}", "expected ''"),
        "期望内容")
    // {raw} 保留兼容
    @Expect(fillQuotes("无法识别的转义（原文：{raw}）", "unrecognized escape '\\q'"),
        "无法识别的转义（原文：unrecognized escape '\\q'）")
}

@Test
public func testStripQuoted() {
    // 引号对及其内容剔除
    @Expect(stripQuoted("a'b'c"), "ac")
    @Expect(stripQuoted("x `y` z"), "x  z")
    @Expect(stripQuoted("无引号"), "无引号")
}
