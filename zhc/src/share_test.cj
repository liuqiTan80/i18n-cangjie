package zhc

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

// share 模块单元测试（设计 §18：翻译资源共享）
// 覆盖：名称净化 / 映射内容门禁 / KV 行解析 / index 解析与重建 / 请求体组装
// round-trip / 校验和向量。HTTP 传输与文件安装走 acceptance 段 18 端到端。

@Test
public func testSanitizeShareName() {
    @Expect(sanitizeShareName("csv4cj"), "csv4cj")
    @Expect(sanitizeShareName("  库名  "), "库名")
    // 路径穿越与分隔符拒绝
    @Expect(sanitizeShareName("../etc/passwd"), "")
    @Expect(sanitizeShareName("a/b"), "")
    @Expect(sanitizeShareName("a\\b"), "")
    @Expect(sanitizeShareName("a b"), "")
    @Expect(sanitizeShareName(""), "")
}

@Test
public func testShareChecksum() {
    // hash64（cache.cj 同款）+ hexOf 向量：空串与 "abc"
    @Expect(shareChecksum(""), "cbf29ce484222325")
    @Expect(shareChecksum("abc"), "c7757e902df0de84")
}

@Test
public func testShareJoinUrl() {
    @Expect(shareJoinUrl("https://x.y/libs", "index.json"), "https://x.y/libs/index.json")
    @Expect(shareJoinUrl("https://x.y/libs/", "index.json"), "https://x.y/libs/index.json")
    @Expect(shareJoinUrl("/tmp/reg", "crates/zh/a.toml"), "/tmp/reg/crates/zh/a.toml")
}

@Test
public func testParseShareKvLine() {
    @Expect(parseShareKvLine("\"颜色\" = \"Color\"").getOrThrow()[0], "颜色")
    @Expect(parseShareKvLine("\"颜色\" = \"Color\"").getOrThrow()[1], "Color")
    // 缺引号 / 缺等号 / 行内注释 → 拒绝
    @Expect(isNoneOpt(parseShareKvLine("颜色 = \"Color\"")), true)
    @Expect(isNoneOpt(parseShareKvLine("\"颜色\" \"Color\"")), true)
    @Expect(isNoneOpt(parseShareKvLine("\"颜色\" = \"Color\" # 注释")), true)
    @Expect(isNoneOpt(parseShareKvLine("[\"标识符\"]")), true)
}

@Test
public func testValidateMappingTomlPass() {
    let toml = "# 头注释\n[\"标识符\"]\n\"颜色\" = \"Color\"\n\"问候语\" = \"GREETING\"\n" +
        "[\"模块路径\"]\n\"图形库\" = \"graph4cj\"\n"
    @Expect(validateMappingToml(toml).size, 0)
}

@Test
public func testValidateMappingTomlFails() {
    // 重复键
    let dup = "[\"标识符\"]\n\"颜色\" = \"Color\"\n\"颜色\" = \"Colour\"\n"
    @Expect(validateMappingToml(dup).size, 1)
    // 非法节名
    let badSec = "[\"乱写的\"]\n\"颜色\" = \"Color\"\n"
    @Expect(validateMappingToml(badSec).size, 1)
    // 行内注释（平台禁令）
    let inline = "[\"标识符\"]\n\"颜色\" = \"Color\" # x\n"
    @Expect(validateMappingToml(inline).size, 1)
    // 空值
    let emptyVal = "[\"标识符\"]\n\"颜色\" = \"\"\n"
    @Expect(validateMappingToml(emptyVal).size, 1)
    // 值非官方标识符（含中划线）
    let badId = "[\"标识符\"]\n\"颜色\" = \"my-Color\"\n"
    @Expect(validateMappingToml(badId).size, 1)
    // 键值出现在节声明之前
    let noSec = "\"颜色\" = \"Color\"\n"
    @Expect(validateMappingToml(noSec).size, 1)
}

@Test
public func testParseShareIndex() {
    let idx = "{\n\"版本\": 1,\n\"库\": [\n" +
        "{\"名称\": \"csv4cj\", \"语言\": \"zh\", \"描述\": \"CSV 解析\", \"作者\": \"a\", \"键数\": 73, \"校验和\": \"aa\", \"时间\": \"t1\"},\n" +
        "{\"名称\": \"ini4cj\", \"语言\": \"zh\", \"描述\": \"INI 解析\", \"作者\": \"b\", \"键数\": 25, \"校验和\": \"bb\", \"时间\": \"t2\"}\n" +
        "]\n}\n"
    let entries = parseShareIndex(idx)
    @Expect(entries.size, 2)
    @Expect(entries[0].name, "csv4cj")
    @Expect(entries[0].keyCount, 73)
    @Expect(entries[1].checksum, "bb")
    // 非 JSON / 缺 "库" 节 → 空清单（容错）
    @Expect(parseShareIndex("not json").size, 0)
    @Expect(parseShareIndex("{}").size, 0)
}

@Test
public func testBuildShareIndexJsonRoundTrip() {
    let entries = ArrayList<ShareEntry>()
    entries.add(ShareEntry("zlib", "zh", "压缩", "甲", 11, "c1", "t1"))
    entries.add(ShareEntry("alog", "zh", "算法", "乙", 22, "c2", "t2"))
    let json = buildShareIndexJson(entries)
    // 重建 → 再解析：条目齐全、字段一致、顺序按名称字典序（alog 在前）
    let back = parseShareIndex(json)
    @Expect(back.size, 2)
    @Expect(back[0].name, "alog")
    @Expect(back[0].keyCount, 22)
    @Expect(back[1].name, "zlib")
    @Expect(back[1].checksum, "c1")
    // 幂等：同输入重建输出相同（确定性 diff）
    @Expect(buildShareIndexJson(parseShareIndex(json)), json)
}

@Test
public func testBuildPublishJsonRoundTrip() {
    let content = "[\"标识符\"]\n\"引号\" = \"Quote\\\"X\\\"\"\n\"多行\" = \"Line1\\nLine2\"\n"
    let body = buildPublishJson("demo", "zh", "测试 \"库\"", "作者", 2, "abcd0123", "t", content)
    match (parseJsonValue(body)) {
        case None => @Expect(true, false)
        case Some(root) =>
            @Expect(root.kind, 0)
            @Expect(shareJsonStr(root, "名称"), "demo")
            @Expect(shareJsonStr(root, "描述"), "测试 \"库\"")
            @Expect(shareJsonNum(root, "键数"), 2)
            @Expect(shareJsonStr(root, "内容"), content)
    }
}

@Test
public func testIsLocalShareBase() {
    @Expect(isLocalShareBase("/tmp/share-registry"), true)
    @Expect(isLocalShareBase("D:\\reg"), true)
    @Expect(isLocalShareBase("http://127.0.0.1:8000"), false)
    @Expect(isLocalShareBase("https://gitcode.com/x/raw/master/libs"), false)
}

@Test
public func testExtractShareOpt() {
    let args = ["fetch", "csv4cj", "--lang", "zh", "--force"]
    @Expect(extractShareOpt(args, "--lang").getOrThrow(), "zh")
    @Expect(isNoneOpt(extractShareOpt(args, "--dir")), true)
    // 缺值（flag 在末尾）→ None
    @Expect(isNoneOpt(extractShareOpt(["--base"], "--base")), true)
}
