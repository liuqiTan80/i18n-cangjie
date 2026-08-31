package zhc

import std.collection.*

/**
 * 语言包加载单元测试（§14.1 单元层）：真实 zh 包全量加载回归
 * （644 错误码大 TOML 解析）、en 包对称性、缺失目录回退、jstr 取值。
 * 注：cjpm test 工作目录为 zhc/，故语言包根目录用相对路径 ./
 * （loadLangPack 内部拼 ${baseDir}/lang-packs/${code}）。
 */
@Test
public func testLoadZhPack() {
    let lang = loadLangPack("./", "zh")
    @Expect(isSomeOpt(lang), true)
    @Expect(lang.getOrThrow().code, "zh")
    // 关键字表（55 关键字 + 3 宏）
    @Expect(lang.getOrThrow().keywords.size >= 50, true)
    @Expect(lang.getOrThrow().macros.get("期望").getOrThrow(), "Expect")
    // 别名表（stdlib 标识符）
    @Expect(lang.getOrThrow().aliases.get("打印行").getOrThrow(), "println")
    // 诊断码表回归：644 条官方 DiagKind + 1 条方言自定义（package_search_error）
    // 大 TOML（errors.toml 3282 行）必须解析无缺漏
    @Expect(lang.getOrThrow().diagKinds.size == 645, true)
    // 精翻条目字段完整（消息模板 + 教学提示）
    let e = lang.getOrThrow().diagKinds.get("sema_undeclared_identifier").getOrThrow()
    @Expect(e.template.indexOf("未声明的标识符") != None, true)
    @Expect(e.tip.size > 0, true)
}

@Test
public func testLoadEnPack() {
    let lang = loadLangPack("./", "en")
    @Expect(isSomeOpt(lang), true)
    @Expect(lang.getOrThrow().code, "en")
    // en 包为恒等映射（关键字键=值）；无 errors.toml → 诊断码表为空
    @Expect(lang.getOrThrow().keywords.get("if").getOrThrow(), "if")
    @Expect(lang.getOrThrow().diagKinds.size == 0, true)
    @Expect(lang.getOrThrow().msgEntries.size == 0, true)
}

@Test
public func testLoadMissingPack() {
    // 不存在的语言代码与不存在的目录 → None（调用方回退默认 zh）
    @Expect(isNoneOpt(loadLangPack("./", "xx")), true)
    @Expect(isNoneOpt(loadLangPack("/不存在/目录", "zh")), true)
}

@Test
public func testJstr() {
    let node = parseJsonValue("{\"a\": \"你好\", \"n\": 123}").getOrThrow()
    @Expect(jstr(node, "a").getOrThrow(), "你好")
    @Expect(jstr(node, "n") == None, true)
    @Expect(jstr(node, "missing") == None, true)
}
