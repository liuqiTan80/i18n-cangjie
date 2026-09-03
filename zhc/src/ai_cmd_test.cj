package zhc

import std.unittest.*
import std.unittest.testmacro.*

// zhc ai 代码块提取单元测试（§17.3 容错：剥 ```cangjie 围栏）。

@Test
public func testExtractFencedCangjie() {
    // 标准 ```cangjie 围栏：只取中间代码，前后说明文字剥除
    let resp = "好的，这是代码：\n```cangjie\n导入 标准核心.{打印行}\n\n主函数() {\n    打印行(\"你好\")\n}\n```\n希望对你有帮助"
    let code = extractCodeBlock(resp)
    @Expect(code, "导入 标准核心.{打印行}\n\n主函数() {\n    打印行(\"你好\")\n}")
}

@Test
public func testExtractFencedBare() {
    // 裸 ``` 围栏（无语言名）
    let resp = "```\n主函数() {\n    打印行(\"你好\")\n}\n```"
    let code = extractCodeBlock(resp)
    @Expect(code, "主函数() {\n    打印行(\"你好\")\n}")
}

@Test
public func testExtractNoFence() {
    // 无围栏：全文原样返回（trimAscii 去首尾空白）
    let code = extractCodeBlock("  主函数() {\n    打印行(\"你好\")\n}\n  ")
    @Expect(code, "主函数() {\n    打印行(\"你好\")\n}")
}

@Test
public func testExtractEmpty() {
    @Expect(extractCodeBlock(""), "")
    @Expect(extractCodeBlock("   \n  "), "")
}
