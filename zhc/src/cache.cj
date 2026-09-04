package zhc

import std.collection.*
import std.convert.*
import std.fs.*
import std.sort.*

/**
 * 阶段 5（s5t9a）：转译增量缓存（设计 §4.3 务实版）。
 *
 * 缓存键 = hash64(源文本) 与语言包指纹的组合；语言包指纹在**转译相关
 * 映射表合并完成后**计算（keywords/macros/modulePaths/aliases 排序拼串哈希）
 * ——源码不变但语言包更新（用户目录覆盖、lang install）→ 指纹变化 → 自动
 * 失效重译（对应蓝图坑 ⑨ 与 §4.3"旧译文不复活"）。
 *
 * 缓存内容 = TranspileResult 序列化（dstText + MapEntry 列表 + total），
 * 命中后由 dstText/map 重建 SourceMap——诊断坐标与未命中路径完全一致。
 * 缓存位置 = 项目 .zhc/cache/（随项目清理，.gitignore 已忽略 .zhc/）。
 *
 * s5t10a 产物缓存（性能）：转译缓存只免词法转译，cjc 编译每次仍要跑；
 * 对二次运行同源（教学高频：改一字重跑）补一层「编译产物缓存」——
 * .zhc/out/main 旁记录元数据（转译缓存键 + cjc 版本标签），两者未变则
 * 命中：跳过 cjc 直接复用产物。SDK 升级 → 版本标签变化 → 自动失效重编。
 *
 * 1.0 适配：UInt64 加减乘运行时溢出均抛 OverflowException（见 hash64 注释），
 * HashMap 遍历无序 → 指纹拼串前必须排序（坑 ①）。
 */

/**
 * 64 位混合哈希（循环左移 + 黄金比例异或；非加密场景足够）。
 * 1.0 适配（实测）：UInt64 加减乘**运行时溢出均抛 OverflowException**
 * （编译期常量折叠同样拦截）→ 哈希只能用无溢出的纯位运算（异或/移位）。
 */
public func hash64(text: String): UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for (b in text.toArray()) {
        hash = hash ^ UInt64(b)
        hash = (hash << 7) | (hash >> 57)
        hash = hash ^ 0x9e3779b97f4a7c15
    }
    return hash
}

/** UInt64 → 16 位小写十六进制（缓存文件名）。 */
public func hexOf(v: UInt64): String {
    let digits = "0123456789abcdef"
    var out = ""
    var x = v
    var i = 0
    while (i < 16) {
        let d = x % 16
        out = "${digits[Int64(d)..Int64(d) + 1]}${out}"
        x = x / 16
        i += 1
    }
    return out
}

/** 语言包指纹：转译相关四表（关键字/宏/模块路径/别名）排序拼串后哈希。 */
public func langFingerprint(lang: LangPack): UInt64 {
    var parts = ArrayList<String>()
    for (m in [lang.keywords, lang.macros, lang.modulePaths, lang.aliases]) {
        let keys = ArrayList<String>()
        for (k in m.keys()) {
            keys.add(k)
        }
        sort(keys)
        for (k in keys) {
            parts.add("${k}=${m.get(k).getOrThrow()}")
        }
    }
    var joined = ""
    for (p in parts) {
        joined = "${joined}${p}\u{0}"
    }
    return hash64(joined)
}

/** 缓存键（源文本 + 指纹 → 文件名；转译缓存与产物缓存共用）。 */
public func cacheKey(srcText: String, fingerprint: UInt64): String {
    return hexOf(hash64("${srcText}\u{0}${fingerprint}"))
}

/**
 * 编译产物缓存（s5t10a 性能）：二次运行同源免 cjc。
 * 命中条件 = 产物 .zhc/out/main 存在（Windows 为 main.exe）&& 元数据记录（转译键 + cjc 版本）
 * 与当前一致。转译键 = 源码 + 语言包指纹 → 源码/词表未变才可能命中；
 * cjc 版本记录 → SDK 升级自动失效（旧产物不复用）。
 * sdkTag 为空（探测失败）→ 永不命中（安全降级：重编译兜底）。
 */
public func artifactHit(outDir: String, key: String, sdkTag: String): Bool {
    if (sdkTag.isEmpty()) {
        return false
    }
    if (!exists(Path(exeOutPath("${outDir}/main")))) {
        return false
    }
    let metaPath = artifactMetaPath(outDir)
    if (!exists(Path(metaPath))) {
        return false
    }
    try {
        return readTextFile(metaPath) == "${key}\n${sdkTag}"
    } catch (e: Exception) {
        return false
    }
}

/** 编译成功后记录产物元数据（写失败静默 → 仅失去缓存机会，不影响主流程）。 */
public func storeArtifactMeta(outDir: String, key: String, sdkTag: String): Unit {
    try {
        File.writeTo(artifactMetaPath(outDir), "${key}\n${sdkTag}".toArray())
    } catch (e: Exception) {
        ()
    }
}

/** cjc 版本标签（每次进程至多一次 exec；探测失败返回空串 → 缓存安全降级）。 */
public func sdkTagOf(): String {
    let v = probeCjcVersion()
    return if (v == None) { "" } else { v.getOrThrow() }
}

/** 产物元数据文件（.zhc/out/ 下的隐藏点文件，随项目清理）。 */
private func artifactMetaPath(outDir: String): String {
    return "${outDir}/.zhc-key"
}

/** 查找转译缓存；未命中或缓存损坏返回 None（损坏自愈：下次转译覆盖重写）。 */
public func lookupTranspile(cacheDir: String, srcText: String, fingerprint: UInt64): ?TranspileResult {
    let key = cacheKey(srcText, fingerprint)
    let path = "${cacheDir}/${key}"
    if (!exists(Path(path))) {
        return None
    }
    // 读取/解析全程兜底：缓存文件被截断、权限异常、字段非法等一律降级为
    // cache miss，绝不向上抛（此前 Int64.parse 等异常会导致进程崩溃）
    try {
        return parseTranspileCache(readTextFile(path))
    } catch (e: Exception) {
        return None
    }
}

/** 解析转译缓存文本；任何结构性不符返回 None。 */
private func parseTranspileCache(text: String): ?TranspileResult {
    match (parseJsonValue(text)) {
        case None => return None
        case Some(root) =>
            if (root.kind != 0) {
                return None
            }
            let t = jstr(root, "t")
            let n = jstr(root, "n")
            if (t == None || n == None) {
                return None
            }
            let map = ArrayList<MapEntry>()
            match (root.obj.get("m")) {
                case None => return None
                case Some(mNode) =>
                    if (mNode.kind != 5) {
                        return None
                    }
                    for (e in mNode.arr) {
                        if (e.kind != 0) {
                            return None
                        }
                        let o = jstr(e, "o")
                        let l = jstr(e, "l")
                        let g = jstr(e, "g")
                        let r = jstr(e, "r")
                        if (o == None || l == None || g == None || r == None) {
                            return None
                        }
                        map.add(MapEntry(Int64.parse(o.getOrThrow()), Int64.parse(l.getOrThrow()),
                                         g.getOrThrow(), r.getOrThrow()))
                    }
            }
            return TranspileResult(t.getOrThrow(), map, Int64.parse(n.getOrThrow()))
    }
}

/** 存储转译缓存（目录自动创建；失败静默不影响主流程）。 */
public func storeTranspile(cacheDir: String, srcText: String, fingerprint: UInt64,
                           result: TranspileResult): Unit {
    try {
        ensureDir(cacheDir)   // 递归创建（含父目录链）
        var entries = ""
        for (e in result.map) {
            entries = "${entries}${jsonQuote("o")}:${e.offset},${jsonQuote("l")}:${e.len}," +
                "${jsonQuote("g")}:${jsonQuote(e.original)},${jsonQuote("r")}:${jsonQuote(e.replacement)},"
        }
        if (!entries.isEmpty()) {
            entries = entries[0..entries.size - 1]   // 去尾逗号
        }
        let payload = "{${jsonQuote("t")}:${jsonQuote(result.text)}," +
            "${jsonQuote("n")}:${result.total}," +
            "${jsonQuote("m")}:[${entries}]}"
        // 原子写入：先写临时文件再改名覆盖，进程中断不留半截缓存文件
        let target = "${cacheDir}/${cacheKey(srcText, fingerprint)}"
        let tmp = "${target}.tmp"
        File.writeTo(tmp, payload.toArray())
        try {
            rename(Path(tmp), to: Path(target), overwrite: true)
        } catch (e: Exception) {
            // 改名失败（目标被占用等）：退回直接覆盖写，并清理临时文件
            File.writeTo(target, payload.toArray())
            removeFileBestEffort(tmp)
        }
    } catch (e: Exception) {
        ()   // 缓存写入失败不影响转译（诊断日志静默同 §16.5）
    }
}
