package zhc

import std.unittest.*
import std.unittest.testmacro.*

// JSON 原语单元测试（设计 §14.1；LSP 帧与诊断报告解析基础）

@Test
public func testExtractJsonStr() {
    // 转义还原：\n → 换行
    @Expect(extractJsonStr("{\"a\": \"x\\ny\"}", "a").getOrThrow(), "x\ny")
    // \uXXXX → 中文码点
    @Expect(extractJsonStr("{\"a\": \"\\u4e2d\"}", "a").getOrThrow(), "中")
    // 中文原文直接提取
    @Expect(extractJsonStr("{\"消息\": \"你好\"}", "消息").getOrThrow(), "你好")
}

@Test
public func testExtractJsonStrNone() {
    // 值非字符串 → None
    let v1 = extractJsonStr("{\"a\": 42}", "a")
    @Expect(isNoneOpt(v1), true)
    // 键不存在 → None
    let v2 = extractJsonStr("{\"a\": \"x\"}", "b")
    @Expect(isNoneOpt(v2), true)
}

@Test
public func testExtractJsonNum() {
    @Expect(extractJsonNum("{\"line\": 42}", "line").getOrThrow(), "42")
    @Expect(extractJsonNum("{\"line\": 0}", "line").getOrThrow(), "0")
    let v = extractJsonNum("{\"line\": 42}", "col")
    @Expect(isNoneOpt(v), true)
}

@Test
public func testSplitJsonArray() {
    let arr = splitJsonArray("[{\"a\": 1}, {\"b\": 2}]")
    @Expect(arr.size, Int64(2))
    @Expect(arr[0].contains("\"a\""), true)
    @Expect(arr[1].contains("\"b\""), true)
}

@Test
public func testJsonQuote() {
    // 引号与反斜杠转义
    @Expect(jsonQuote("a\"b"), "\"a\\\"b\"")
    @Expect(jsonQuote("a\\b"), "\"a\\\\b\"")
    // 换行 → \n
    @Expect(jsonQuote("x\ny"), "\"x\\ny\"")
    // 中文原样
    @Expect(jsonQuote("你好"), "\"你好\"")
}
