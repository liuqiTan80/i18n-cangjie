package zhc

import std.unittest.*
import std.unittest.testmacro.*

// TOML 解析单元测试（设计 §14.1 数据层：语言包 TOML 合法性）

@Test
public func testParseTomlSections() {
    let t = parseToml("[package]\nname = \"zhc\"\nversion = \"0.1.0\"\n\n[dependencies]\n")
    @Expect(t.contains("package"), true)
    @Expect(t.contains("dependencies"), true)
    let pkg = t.get("package").getOrThrow()
    @Expect(pkg.get("name").getOrThrow(), "zhc")
    @Expect(pkg.get("version").getOrThrow(), "0.1.0")
}

@Test
public func testParseTomlCommentAndBlank() {
    // 注释行与空行跳过
    let t = parseToml("# 顶部注释\n\n[a]\nx = \"1\" # 行尾注释\n\n\n[b]\n")
    @Expect(t.contains("a"), true)
    @Expect(t.contains("b"), true)
    @Expect(t.get("a").getOrThrow().get("x").getOrThrow(), "1")
}

@Test
public func testParseTomlQuotedSection() {
    // 语言包节名带引号写法（["界面消息"]）
    let t = parseToml("[\"界面消息\"]\ncompile_ok = \"编译成功\"\n")
    let ui = t.get("界面消息").getOrThrow()
    @Expect(ui.get("compile_ok").getOrThrow(), "编译成功")
}

@Test
public func testParseTomlNested() {
    // 嵌套节与直接键值（语言包 errors.toml 约定格式：`["外层"."子层"]`，
    // 子节空 = 键值直属外层节）
    let t = parseTomlNested("[\"标识符\"]\n\"sum\" = \"sum\"\n\"x\" = \"x\"\n\n[\"crates\".\"items\"]\n\"求和\" = \"sum\"\n")
    let root = t.get("标识符").getOrThrow()
    let leaf = root.get("").getOrThrow()
    @Expect(leaf.get("sum").getOrThrow(), "sum")
    let items = t.get("crates").getOrThrow().get("items").getOrThrow()
    @Expect(items.get("求和").getOrThrow(), "sum")
}
