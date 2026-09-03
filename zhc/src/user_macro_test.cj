package zhc

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// 用户自定义宏单元测试（设计见 user_macro.cj：模板宏解析/实参整词替换/
// 字符串与注释保护/嵌套展开/调用与定义错误）

func testMacroLang(): LangPack {
    return loadLangPack("./", "zh").getOrThrow()
}

@Test
public func testParseMacroOk() {
    let defs = HashMap<String, UserMacro>()
    let ok = parseUserMacroFile(
        "@断言(条件, 消息) {\n" +
        "    如果 (!(条件)) {\n" +
        "        打印行(消息)\n" +
        "    }\n" +
        "}\n" +
        "\n" +
        "@问候(名字) {\n" +
        "    打印行(\"你好，\" + 名字)\n" +
        "}\n", testMacroLang(), "宏.zcm", defs)
    @Expect(ok, true)
    @Expect(defs.size, Int64(2))
    @Expect(defs.contains("断言"), true)
    @Expect(defs.get("断言").getOrThrow().params.size, Int64(2))
    @Expect(defs.get("问候").getOrThrow().params.get(0).getOrThrow(), "名字")
    @Expect(defs.get("问候").getOrThrow().body.indexOf("你好") != None, true)
}

@Test
public func testParseMacroErrors() {
    // 形参表缺 ')'（后续内容落入形参解析 → 非法）
    let d1 = HashMap<String, UserMacro>()
    @Expect(parseUserMacroFile("@断言(条件 {\n    打印行(条件)\n}\n", testMacroLang(), "宏.zcm", d1), false)
    // 宏体缺配对 '}'
    let d2 = HashMap<String, UserMacro>()
    @Expect(parseUserMacroFile("@a(x) {\n    打印行(x)\n", testMacroLang(), "宏.zcm", d2), false)
    // 重复定义同名
    let d3 = HashMap<String, UserMacro>()
    @Expect(parseUserMacroFile("@a() {\n    1\n}\n@a() {\n    2\n}\n", testMacroLang(), "宏.zcm", d3), false)
    // 文件里出现宏定义之外的内容
    let d4 = HashMap<String, UserMacro>()
    @Expect(parseUserMacroFile("随便写点什么\n", testMacroLang(), "宏.zcm", d4), false)
    // @ 后不跟宏名
    let d5 = HashMap<String, UserMacro>()
    @Expect(parseUserMacroFile("@1() {\n    1\n}\n", testMacroLang(), "宏.zcm", d5), false)
    // 空参宏 + 块注释混排可解析
    let d6 = HashMap<String, UserMacro>()
    @Expect(parseUserMacroFile("/* 头部注释 */\n@a() {\n    1\n}\n// 尾部注释\n", testMacroLang(), "宏.zcm", d6), true)
    @Expect(d6.contains("a"), true)
}

@Test
public func testParseBodyStringBrace() {
    // 宏体字符串字面量里的 '}' 不参与配对
    let d = HashMap<String, UserMacro>()
    let ok = parseUserMacroFile("@say() {\n    打印行(\"}\")\n}\n", testMacroLang(), "宏.zcm", d)
    @Expect(ok, true)
    @Expect(d.get("say").getOrThrow().body.indexOf("打印行") != None, true)
}

@Test
public func testReplaceParamsProtect() {
    // 参数按整词替换；字符串字面量与行注释中的同名文本保留
    let params = ArrayList<String>()
    params.add("名字")
    let args = ArrayList<String>()
    args.add("\"小明\"")
    let out = replaceParams("打印行(\"名字：\" + 名字)  // 名字注释", params, args)
    @Expect(out, "打印行(\"名字：\" + \"小明\")  // 名字注释")
}

@Test
public func testReplaceParamsNoPartial() {
    // 前缀/后缀相似的标识符（形参名须整词出现）不被误伤
    let params = ArrayList<String>()
    params.add("数")
    let args = ArrayList<String>()
    args.add("10")
    @Expect(replaceParams("打印行(数 + 数据 + 大数 + 数数)", params, args),
        "打印行(10 + 数据 + 大数 + 数数)")
}

@Test
public func testExpandCallsOnce() {
    // 正常替换：实参去首尾空白；字符串里的 @调用 不展开；未定义 @名 原样
    let defs = HashMap<String, UserMacro>()
    let p = ArrayList<String>()
    p.add("数")
    let b = ArrayList<String>()
    b.add("10")
    defs.add("加", UserMacro(p, "数 + 1"))
    let seen = ArrayList<String>()
    let r = expandCallsOnce("打印行(\"@加(99)\")  @加( 10 )  @未知(1)", defs, "main.zc", seen)
    @Expect(r == None, false)
    @Expect(r.getOrThrow(), "打印行(\"@加(99)\")  10 + 1  @未知(1)")
    @Expect(seen.size, Int64(1))
    @Expect(seen.get(0).getOrThrow(), "加")
}

@Test
public func testExpandArityMismatch() {
    // 实参个数不符 → None（错误已打印），不产出半成品
    let defs = HashMap<String, UserMacro>()
    let p = ArrayList<String>()
    p.add("甲")
    p.add("乙")
    defs.add("两", UserMacro(p, "甲 + 乙"))
    let seen = ArrayList<String>()
    @Expect(expandCallsOnce("@两(1)", defs, "main.zc", seen) == None, true)
}

@Test
public func testNestedExpandRounds() {
    // 模板体内可调用其他用户宏：逐轮整文本展开
    let defs = HashMap<String, UserMacro>()
    let pa = ArrayList<String>()
    pa.add("x")
    defs.add("a", UserMacro(pa, "@b(x)"))
    let pb = ArrayList<String>()
    pb.add("y")
    defs.add("b", UserMacro(pb, "y + 1"))
    var text = "@a(5)"
    var seen = ArrayList<String>()
    let r1 = expandCallsOnce(text, defs, "main.zc", seen)
    @Expect(r1.getOrThrow(), "@b(5)")
    text = r1.getOrThrow()
    seen = ArrayList<String>()
    let r2 = expandCallsOnce(text, defs, "main.zc", seen)
    @Expect(r2.getOrThrow(), "5 + 1")
}

@Test
public func testExpandNoMacroFile() {
    // 无宏定义文件：原样返回
    let r = expandUserMacros("主函数() {\n    打印行(\"a\")\n}\n", testMacroLang(),
        "/nonexistent_zhc_dir/x.zc")
    @Expect(r == None, false)
    @Expect(r.getOrThrow(), "主函数() {\n    打印行(\"a\")\n}\n")
}

@Test
public func testLineOfRunes() {
    @Expect(lineOf("@a\n@b\n@c".toRuneArray(), 0), Int64(1))
    @Expect(lineOf("@a\n@b\n@c".toRuneArray(), 3), Int64(2))
    @Expect(lineOf("@a\n@b\n@c".toRuneArray(), 9), Int64(3))
}
