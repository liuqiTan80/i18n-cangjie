package zhc

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

// 缓存层单元测试（设计 §14.1 单元层：缓存指纹；§4.3 增量缓存键；
// s5t10a 产物缓存元数据）——临时目录用 target/（.gitignore 已忽略）

@Test
public func testHash64Deterministic() {
    // 同输入同输出（缓存命中的前提）
    @Expect(hash64("hello"), hash64("hello"))
    @Expect(hash64("主函数() {\n}"), hash64("主函数() {\n}"))
}

@Test
public func testHash64Distinct() {
    // 不同输入不同输出（源文本变化 → 缓存失效）
    @Expect(hash64("hello") == hash64("hello!"), false)
    @Expect(hash64("") == hash64(" "), false)
}

@Test
public func testHexOf() {
    @Expect(hexOf(UInt64(0)), "0000000000000000")
    @Expect(hexOf(UInt64(15)), "000000000000000f")
    @Expect(hexOf(UInt64(255)), "00000000000000ff")
}

@Test
public func testHexOfHashLen() {
    // 缓存文件名：恒 16 位小写十六进制
    @Expect(hexOf(hash64("任意文本")).size, Int64(16))
}

/** 产物缓存测试目录（target/ 已忽略，随构建产物清理）。 */
private func artTestDir(tag: String): String {
    let dir = "target/art-${tag}"
    if (!exists(Path(dir))) {
        Directory.create(Path(dir))
    }
    return dir
}

@Test
public func testArtifactRoundTrip() {
    // 编译成功记元数据 → 同键同版本命中；键/版本任一变化即失效
    let dir = artTestDir("roundtrip")
    File.writeTo("${dir}/main", "fake exe".toArray())
    storeArtifactMeta(dir, "k1", "1.0.5")
    @Expect(artifactHit(dir, "k1", "1.0.5"), true)
    @Expect(artifactHit(dir, "k2", "1.0.5"), false)   // 源码/词表变 → 键变
    @Expect(artifactHit(dir, "k1", "1.0.6"), false)   // SDK 升级 → 版本变
}

@Test
public func testArtifactNeedsMainAndSdk() {
    // 产物缺失（用户清理/换目录）或版本探测失败 → 永不命中（安全重编译）
    let dir = artTestDir("needs-main")
    File.writeTo("${dir}/.zhc-key", "k1\n1.0.5".toArray())
    @Expect(artifactHit(dir, "k1", "1.0.5"), false)   // 无 main 产物
    @Expect(artifactHit(dir, "k1", ""), false)       // sdkTag 探测失败
}

@Test
public func testArtifactCacheKeyShared() {
    // 产物缓存键 = 转译缓存键（源码 + 语言包指纹）——两缓存同键联动
    let fp = UInt64(42)
    @Expect(cacheKey("源A", fp) == cacheKey("源A", fp), true)
    @Expect(cacheKey("源A", fp) == cacheKey("源B", fp), false)
}
