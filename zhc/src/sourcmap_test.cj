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
public func testSourceMapMapBackEndToEnd() {
    // 端到端（此前仅测 backShift/mergeMaps，mapBack 与 SourceMap 构造零覆盖）：
    // 多行含中文源 + 替换条目 → 产物行列反推回源行列
    let src = "让 a = 1\n打印行(名字)\n"
    let entries = ArrayList<MapEntry>()
    // 第 2 行 '打印行'（源 Rune 偏移 8、长 3）→ 'println'（7）
    entries.add(MapEntry(8, 3, "打印行", "println"))
    let dst = "让 a = 1\nprintln(名字)\n"
    let sm = SourceMap(src, dst, entries)
    // 产物第 2 行 'println' 起点（及区间内任意列）→ 源第 2 行 '打印行' 起点
    let (l1, c1) = sm.mapBack(2, 1)
    @Expect(l1, Int64(2))
    @Expect(c1, Int64(1))
    // 产物第 2 行第 8 列（'(' 处，替换区右端：println 7 字符 + 1）→ 源第 2 行第 4 列
    let (l2, c2) = sm.mapBack(2, 8)
    @Expect(l2, Int64(2))
    @Expect(c2, Int64(4))
    // 产物第 2 行第 9 列（名字 起始，未替换区按累计差值平移）→ 源第 2 行第 5 列
    let (l4, c4) = sm.mapBack(2, 9)
    @Expect(l4, Int64(2))
    @Expect(c4, Int64(5))
    // 越界行原样回退（不崩溃）
    let (l3, _) = sm.mapBack(99, 1)
    @Expect(l3, Int64(99))
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

@Test
public func testMergeMapsInterleaved() {
    // 回归：折算后的 map2 条目落在 map1 条目之前（交错）时，
    // 合并输出仍须按源偏移升序（早期实现三段 append 乱序，
    // 致 SourceMap 构造器（升序假设）双侧坐标错位斜切）
    let map1 = ArrayList<MapEntry>()
    map1.add(MapEntry(10, 1, "后", "after"))  // 源基准 offset 10
    let map2 = ArrayList<MapEntry>()
    map2.add(MapEntry(3, 1, "前", "before"))  // map1 输出基准 offset 3
    let merged = mergeMaps(map1, map2, ArrayList<MapEntry>())
    @Expect(merged.size, Int64(2))
    @Expect(merged[0].offset, Int64(3))       // map2 折算 3 < map1 的 10
    @Expect(merged[1].offset, Int64(10))
    @Expect(merged[0].replacement, "before")
    @Expect(merged[1].replacement, "after")
}
