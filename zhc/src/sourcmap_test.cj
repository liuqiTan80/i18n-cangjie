package zhc

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 源映射单元测试（设计 §14.1 单元层：偏移折算；§5.6 偏移单位 UTF-16）

@Test
public func testRuneLen() {
    @Expect(runeLenOf("abc"), Int64(3))
    @Expect(runeLenOf("你好"), Int64(2))
    @Expect(runeLenOf("a😀b"), Int64(3))      // emoji 也是 1 个 Rune
    @Expect(runeLenOf(""), Int64(0))
}

@Test
public func testUtf16Len() {
    @Expect(utf16LenOf("abc"), Int64(3))
    @Expect(utf16LenOf("你好"), Int64(2))     // BMP 各 1 单元
    @Expect(utf16LenOf("😀"), Int64(2))       // 非 BMP 计 2
    @Expect(utf16LenOf("a😀b"), Int64(4))
}

@Test
public func testBackShiftBefore() {
    // 源"ab让cd" → 替换后"abletcd"：entry = (offset 2, 让 → let)
    let entries = ArrayList<MapEntry>()
    entries.add(MapEntry(2, 1, "让", "let"))
    @Expect(backShift(entries, 0), Int64(0))  // 替换前偏移不变
    @Expect(backShift(entries, 1), Int64(1))
    @Expect(backShift(entries, 2), Int64(2))  // 替换起点
}

@Test
public func testBackShiftInside() {
    let entries = ArrayList<MapEntry>()
    entries.add(MapEntry(2, 1, "让", "let"))
    @Expect(backShift(entries, 3), Int64(3))  // "l" 映射回源 3
    @Expect(backShift(entries, 4), Int64(3))  // "e" 超长钳制到源 3
    @Expect(backShift(entries, 5), Int64(3))  // "t" 超长钳制到源 3
}

@Test
public func testBackShiftAfter() {
    let entries = ArrayList<MapEntry>()
    entries.add(MapEntry(2, 1, "让", "let"))
    @Expect(backShift(entries, 5), Int64(3))  // 替换后首个字符：源 3
    @Expect(backShift(entries, 6), Int64(4))  // 长度差 2 累计折算
}

@Test
public func testMergeMaps() {
    let map1 = ArrayList<MapEntry>()
    map1.add(MapEntry(2, 1, "让", "let"))
    let map2 = ArrayList<MapEntry>()
    map2.add(MapEntry(5, 1, "a", "b"))        // 偏移为 map1 变换后基准
    let merged = mergeMaps(map1, map2, ArrayList<MapEntry>())
    @Expect(merged.size, Int64(2))
    @Expect(merged[0].offset, Int64(2))
    @Expect(merged[1].offset, Int64(3))       // 折回源基准：5-2=3
    @Expect(merged[1].replacement, "b")
}
