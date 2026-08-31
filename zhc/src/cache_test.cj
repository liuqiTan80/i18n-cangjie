package zhc

import std.unittest.*
import std.unittest.testmacro.*

// 缓存层单元测试（设计 §14.1 单元层：缓存指纹；§4.3 增量缓存键）

@Test
public func testHash64Deterministic() {
    // 同输入同输出（缓存命中的前提）
    @Expect(hash64("hello"), hash64("hello"))
    @Expect(hash64("主函数() {\n}"), hash64("主函数() {\n}"))
}

@Test
public func testHash64Distinct() {
    // 不同输入不同输出（源文本变化 → 缓存失效）
    @Expect(hash64("hello") == hash64("hello!"), false)
    @Expect(hash64("") == hash64(" "), false)
}

@Test
public func testHexOf() {
    @Expect(hexOf(UInt64(0)), "0000000000000000")
    @Expect(hexOf(UInt64(15)), "000000000000000f")
    @Expect(hexOf(UInt64(255)), "00000000000000ff")
}

@Test
public func testHexOfHashLen() {
    // 缓存文件名：恒 16 位小写十六进制
    @Expect(hexOf(hash64("任意文本")).size, Int64(16))
}
