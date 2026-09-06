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
    // en 包为恒等映射（关键字键=值）；errors.toml = Top-50 诊断码（人工精译）
    // （消息表节未建：兜底路径回退官方原文，测试与文件现状同步）
    @Expect(lang.getOrThrow().keywords.get("if").getOrThrow(), "if")
    @Expect(lang.getOrThrow().diagKinds.size, Int64(50))
    @Expect(lang.getOrThrow().msgEntries.size, Int64(0))
}

@Test
public func testLoadMissingPack() {
    // 不存在的语言代码与不存在的目录 → None（调用方回退默认 zh）
    @Expect(isNoneOpt(loadLangPack("./", "xx")), true)
    @Expect(isNoneOpt(loadLangPack("/不存在/目录", "zh")), true)
}

@Test
public func testUiFallbackChain() {
    // P-3 运行时三级回退：当前语言命中 → en 兜底 → zh 原文（key）
    let zh = loadLangPack("./", "zh").getOrThrow()
    let en = loadLangPack("./", "en").getOrThrow()
    let ja = loadLangPack("./", "ja").getOrThrow()
    let de = loadLangPack("./", "de").getOrThrow()
    let es = loadLangPack("./", "es").getOrThrow()
    let fr = loadLangPack("./", "fr").getOrThrow()
    let ko = loadLangPack("./", "ko").getOrThrow()
    // ① standard 档（ja 全量 312 键）母语键命中：不经 en
    setUiLangWithRoot(ja, "./")
    @Expect(uiText("文件不存在：{0}"), "ファイルが存在しません: {0}")
    // ② standard 档（de 全量 312 键）母语键命中
    setUiLangWithRoot(de, "./")
    @Expect(uiText("文件不存在：{0}"), "Datei existiert nicht: {0}")
    // ③ standard 档（es 全量 312 键）母语键命中
    setUiLangWithRoot(es, "./")
    @Expect(uiText("文件不存在：{0}"), "el archivo no existe: {0}")
    // ④ standard 档（fr 全量 312 键）母语键命中
    setUiLangWithRoot(fr, "./")
    @Expect(uiText("文件不存在：{0}"), "le fichier n'existe pas : {0}")
    // ⑤ standard 档（ko 全量 312 键）母语键命中
    setUiLangWithRoot(ko, "./")
    @Expect(uiText("文件不存在：{0}"), "파일이 존재하지 않음: {0}")
    // ⑥ 两级皆未命中（源码新增键未重生成）：回退 zh 原文 key 本身
    @Expect(uiText("全新界面串（未登记）：{0}"), "全新界面串（未登记）：{0}")
    // ⑦ en 全量档直接命中英文
    setUiLangWithRoot(en, "./")
    @Expect(uiText("文件不存在：{0}"), "File not found: {0}")
    // ⑧ zh 无界面表：缺键回退 key 即原文（不查 en，行为与旧版一致）
    setUiLangWithRoot(zh, "./")
    @Expect(uiText("文件不存在：{0}"), "文件不存在：{0}")
    @Expect(uiText("需求为空：请用一句话描述想实现的程序"),
            "需求为空：请用一句话描述想实现的程序")
    // 复位为 zh（防影响后续用例；setUiLang 接收 LangPack）
    setUiLang(zh)
}

@Test
public func testLangByExt() {
    // P-2 扩展名反查（显式 bases，不依赖环境变量）：lang_info.toml 声明驱动
    let bases = ArrayList<String>()
    bases.add("./")   // cjpm test 工作目录 = zhc/（含 lang-packs/）
    @Expect(langCodeByExt("demo.zc", bases).getOrThrow(), "zh")
    @Expect(langCodeByExt("demo.en", bases).getOrThrow(), "en")
    @Expect(langCodeByExt("demo.rc", bases).getOrThrow(), "ru")
    @Expect(langCodeByExt("demo.jc", bases).getOrThrow(), "ja")
    @Expect(langCodeByExt("x/深/demo.rc", bases).getOrThrow(), "ru")
    // 官方 .cj / 未知扩展名 / 无扩展名 → None（回退环境决议）
    @Expect(isNoneOpt(langCodeByExt("demo.cj", bases)), true)
    @Expect(isNoneOpt(langCodeByExt("demo.xyz", bases)), true)
    @Expect(isNoneOpt(langCodeByExt("demo", bases)), true)
    // 根目录不存在 → None（静默）
    let noneBases = ArrayList<String>()
    noneBases.add("/不存在/目录")
    @Expect(isNoneOpt(langCodeByExt("demo.rc", noneBases)), true)
}

@Test
public func testJstr() {
    let node = parseJsonValue("{\"a\": \"你好\", \"n\": 123}").getOrThrow()
    @Expect(jstr(node, "a").getOrThrow(), "你好")
    @Expect(jstr(node, "n") == None, true)
    @Expect(jstr(node, "missing") == None, true)
}
