package zhc

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 类型本地化单元测试（设计 §14.1：类型本地化黄金样例；§7.3 处理链）
// 黄金样例：expected 'Struct-String', found 'Class-Deque<Tuple<Int64, Int64>>'

func mkTypeMap(): TypeMap {
    let types = HashMap<String, String>()
    types.add("String", "字符串")
    types.add("Int64", "整数")
    types.add("Deque", "双端队列")
    types.add("Tuple", "元组")
    types.add("List", "列表")
    return TypeMap(types, HashMap<String, String>())
}

@Test
public func testLocalizeStruct() {
    // 种类前缀：Struct- → 结构体-
    @Expect(localizeType("Struct-String", mkTypeMap()), "结构体-字符串")
}

@Test
public func testLocalizeGenericNested() {
    // 泛型递归：类-双端队列<元组<整数, 整数>>（嵌套 < 深度配对）
    @Expect(localizeType("Class-Deque<Tuple<Int64, Int64>>", mkTypeMap()),
        "类-双端队列<元组<整数, 整数>>")
}

@Test
public func testLocalizeNullable() {
    // 可空标记 ? 前缀原样保留
    @Expect(localizeType("?Int64", mkTypeMap()), "?整数")
    @Expect(localizeType("??String", mkTypeMap()), "??字符串")
}

@Test
public func testLocalizeUnknown() {
    // 未知类型原样透传（不崩溃）
    @Expect(localizeType("UnknownXYZ", mkTypeMap()), "UnknownXYZ")
    // 括号包裹（如诊断中的参数列表 `(Int64)`）：剥括号递归再还原
    @Expect(localizeType("(Int64)", mkTypeMap()), "(整数)")
    @Expect(localizeType("(Int64, String)", mkTypeMap()), "(整数, 字符串)")
}

@Test
public func testLocalizeGenericList() {
    // 多参数泛型：顶层逗号拆分
    @Expect(localizeType("List<String>", mkTypeMap()), "列表<字符串>")
}

@Test
public func testSplitTopLevel() {
    // 按深度 0 逗号拆分（泛型内逗号不计）
    let p = splitTopLevel("Int64, Tuple<Int64, Int64>, String")
    @Expect(p.size, Int64(3))
    @Expect(p[0].trimAscii(), "Int64")
    @Expect(p[1].trimAscii(), "Tuple<Int64, Int64>")
    @Expect(p[2].trimAscii(), "String")
}

@Test
public func testIsAscii() {
    @Expect(isAscii("abc123"), true)
    @Expect(isAscii(""), true)
    @Expect(isAscii("中文"), false)
    @Expect(isAscii("a中b"), false)
}
