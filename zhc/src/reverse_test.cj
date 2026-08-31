package zhc

import std.collection.*
import std.sort.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * 反向映射构建单元测试（§14.1 单元层）：buildReverseMap 三表合并、
 * 关键字表优先、碰撞检测与确定性。
 */
@Test
public func testBuildReverseMap() {
    // 三表合并：官方词 → 母语候选列表
    let keywords = HashMap<String, String>()
    keywords.add("如果", "if")
    keywords.add("让", "let")
    let macros = HashMap<String, String>()
    macros.add("期望", "Expect")
    let aliases = HashMap<String, String>()
    aliases.add("列表", "ArrayList")
    let rm = buildReverseMap(keywords, macros, aliases)
    @Expect(isSomeOpt(rm.entries.get("if")), true)
    @Expect(isSomeOpt(rm.entries.get("Expect")), true)
    @Expect(isSomeOpt(rm.entries.get("ArrayList")), true)
    @Expect(rm.collisions.size == 0, true)
}

@Test
public func testReverseMapPriority() {
    // 同一母语词在关键字表与别名表都出现 → 关键字表优先（官方词取关键字表值）
    let keywords = HashMap<String, String>()
    keywords.add("是", "is")
    let macros = HashMap<String, String>()
    let aliases = HashMap<String, String>()
    aliases.add("是", "belong")
    let rm = buildReverseMap(keywords, macros, aliases)
    let v = rm.entries.get("is")
    @Expect(isSomeOpt(v), true)
    @Expect(v.getOrThrow().size == 1, true)
    @Expect(v.getOrThrow()[0] == "是", true)
    // 别名表的 belong 不应出现（是 已被关键字表占用）
    @Expect(rm.entries.get("belong") == None, true)
    @Expect(rm.collisions.size == 0, true)
}

@Test
public func testReverseMapCollision() {
    // 同一官方词对应多个母语词 → 碰撞报告 + 首个命中策略
    let keywords = HashMap<String, String>()
    keywords.add("属于", "is")
    let macros = HashMap<String, String>()
    let aliases = HashMap<String, String>()
    aliases.add("是", "is")
    let rm = buildReverseMap(keywords, macros, aliases)
    @Expect(rm.collisions.size == 1, true)
    @Expect(rm.collisions[0].indexOf("反向映射碰撞") != None, true)
    @Expect(rm.collisions[0].indexOf("`is`") != None, true)
    // 首个命中 = 排序后第一个（属于 与 是 的字节序）
    let v = rm.entries.get("is").getOrThrow()
    @Expect(v.size == 2, true)
}

@Test
public func testReverseMapDeterministic() {
    // 多轮构建结果稳定（排序保证确定性，§6.3）
    let keywords = HashMap<String, String>()
    keywords.add("则", "then")
    keywords.add("否则", "else")
    let macros = HashMap<String, String>()
    let aliases = HashMap<String, String>()
    aliases.add("或者", "or")
    let r1 = buildReverseMap(keywords, macros, aliases)
    let r2 = buildReverseMap(keywords, macros, aliases)
    let k1 = ArrayList<String>()
    for (k in r1.entries.keys()) {
        k1.add(k)
    }
    sort(k1)
    let k2 = ArrayList<String>()
    for (k in r2.entries.keys()) {
        k2.add(k)
    }
    sort(k2)
    @Expect(k1.size == k2.size, true)
    var i = 0
    while (i < k1.size) {
        @Expect(k1[i], k2[i])
        i += 1
    }
    @Expect(r1.collisions.size == r2.collisions.size, true)
}
