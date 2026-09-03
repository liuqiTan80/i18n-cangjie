package zhc

import std.collection.*
import std.fs.*
import std.process.*

/**
 * 阶段 5（s5t7）：workspace 多模块支持（设计 §11）。
 *
 * cjpm 1.0 workspace 实测（§13.1 第 31 条）：
 *   - 根 cjpm.toml 含 [workspace] 节（members/build-members/test-members 数组）；
 *   - `cjpm build` 在根构建全部成员，`-m <成员>` 指定单个；
 *   - `cjpm run` 不支持 -m（报 unknown command），需进入成员目录运行；
 *   - 被依赖成员 output-type 不能是 executable，依赖键名须等于成员包名；
 *   - zhc 首批不做跨成员包依赖解析（成员各自独立转译 + cjc -p 编译，
 *     诊断按模块输出），成员间依赖链接留待 cjpm 构建钩子批次（§16.2）。
 *
 * zhc workspace 模式：
 *   - run/check：识别根 [workspace] → 对每个含方言源码的成员转译到
 *     <成员>/.zhc/src/ 并 cjc -p 编译（诊断各自映射回方言坐标）；
 *     run 模式依次运行各可执行成员产物；
 *   - test：对每个含方言源码的成员执行 .zhc-test/ 流程（lint_tool.cj）。
 */

/** 单成员转译 + 编译结果（诊断输出 + 源映射）。 */
public class MemberBuildResult {
    public var code: Int64
    public var mappedCount: Int64
    public var stdoutB: Array<Byte>
    public var stderrB: Array<Byte>
    public var maps: HashMap<String, SourceMap>
    public var srcs: HashMap<String, String>

    public init(code: Int64, mappedCount: Int64, stdoutB: Array<Byte>, stderrB: Array<Byte>,
                maps: HashMap<String, SourceMap>, srcs: HashMap<String, String>) {
        this.code = code
        this.mappedCount = mappedCount
        this.stdoutB = stdoutB
        this.stderrB = stderrB
        this.maps = maps
        this.srcs = srcs
    }
}

/** 判断 cjpm.toml 是否为 workspace 根（首个节标题为 [workspace]）。 */
public func isWorkspaceRoot(tomlText: String): Bool {
    for (line in tomlText.split("\n")) {
        let t = line.trimAscii()
        if (t.startsWith("[")) {
            return t.startsWith("[workspace]")
        }
    }
    return false
}

/** 从项目根（成员根）向上查找 workspace 根（父目录含 [workspace] 的 cjpm.toml）。 */
public func findWorkspaceRoot(memberRoot: String): ?String {
    var dir = parentDir(memberRoot)
    while (dir != "." && !dir.isEmpty()) {
        let toml = "${dir}/cjpm.toml"
        if (exists(Path(toml)) && isWorkspaceRoot(readTextFile(toml))) {
            return dir
        }
        let p = parentDir(dir)
        if (p == dir) {
            break
        }
        dir = p
    }
    return None
}

/** 解析 [workspace] 节 members 数组（`members = ["a", "b"]` → ["a","b"]）。
 * toml_mini 不支持数组值，这里手工提取节内引号字符串。 */
public func parseWorkspaceMembers(tomlText: String): ArrayList<String> {
    let out = ArrayList<String>()
    var inWs = false
    for (line in tomlText.split("\n")) {
        let t = line.trimAscii()
        if (t.startsWith("[")) {
            inWs = t.startsWith("[workspace]")
            continue
        }
        if (!inWs) {
            continue
        }
        if (!t.startsWith("members")) {
            continue
        }
        let eq = t.indexOf("=")
        if (eq == None) {
            continue
        }
        let rest = t[eq.getOrThrow() + 1..t.size]
        let runes = rest.toRuneArray()
        var i: Int64 = 0
        while (i < runes.size) {
            if (runes[i] == r'"') {
                var j = i + 1
                while (j < runes.size && runes[j] != r'"') {
                    j += 1
                }
                if (j < runes.size) {
                    out.add(String(runes[i + 1..j]))
                    i = j + 1
                } else {
                    i = j
                }
            } else {
                i += 1
            }
        }
        break
    }
    return out
}

/**
 * 转译成员 src/ 到 <成员>/.zhc/src/（保留相对结构）并 cjc -p 编译。
 * 诊断输出与源映射随结果返回，由调用方决定打印与定位（单项目/workspace 共用）。
 */
public func buildMember(memberRoot: String, lang: LangPack): MemberBuildResult {
    let workDir = "${memberRoot}/.zhc"
    let cjSrc = "${workDir}/src"
    let outDir = "${workDir}/out"
    ensureDir(workDir)
    ensureDir(cjSrc)
    ensureDir(outDir)

    var mappedCount: Int64 = 0
    let entries = ArrayList<SourceEntry>()
    collectSourceFiles("${memberRoot}/src", "", entries)
    let maps = HashMap<String, SourceMap>()
    let srcs = HashMap<String, String>()
    // 混编 package：方言转译产物补 package 声明（官方 .cj 自带）——
    // cjc -p 要求同目录同包，否则 default 包与命名包冲突（s5t9b 实测）
    // 容错：cjpm.toml 含 toml_mini 不支持的键（如空内联表 {}）时包名留空，
    // 产物统一 default 包（纯方言项目不受影响）
    var pkgName = ""
    let pkgToml = "${memberRoot}/cjpm.toml"
    if (exists(Path(pkgToml))) {
        try {
            let toml = parseToml(readTextFile(pkgToml))
            match (toml.get("package")) {
                case None => ()
                case Some(sec) =>
                    let nm = sec.get("name")
                    if (nm != None) {
                        pkgName = nm.getOrThrow()
                    }
            }
        } catch (e: Exception) {
            pkgName = ""
        }
    }
    for (e in entries) {
        // cjc -p 不递归子目录（§13 实测项 #6）：子目录方言源码暂不支持项目编译
        if (e.isZh && e.relPath.contains("/")) {
            println(uiTextF("警告：{0} 位于 src/ 子目录，cjc -p 不递归编译，项目模式暂不支持（建议放 src/ 一层；eject 导出不受限）", [e.relPath]))
        }
        let dst = if (e.isZh) { zhToCj("${cjSrc}/${e.relPath}") } else { "${cjSrc}/${e.relPath}" }
        ensureParentDir(dst)
        if (e.isZh) {
            let srcText = readTextFile(e.absPath)
            scanUnicodeRisks(srcText, e.absPath)
            // s5t9a：增量缓存（§4.3）——键 = 源文本 + 语言包指纹，命中跳过转译
            let fingerprint = langFingerprint(lang)
            match (lookupTranspile("${workDir}/cache", srcText, fingerprint)) {
                case Some(cached) =>
                    mappedCount += cached.total
                    File.writeTo(dst, (withPackage(cached.text, pkgName)).toArray())
                    maps.add(dst, SourceMap(srcText, cached.text, cached.map))
                    srcs.add(dst, e.absPath)
                case None =>
                    let result = transpileFull(srcText, lang)
                    mappedCount += result.total
                    File.writeTo(dst, (withPackage(result.text, pkgName)).toArray())
                    maps.add(dst, SourceMap(srcText, result.text, result.map))
                    srcs.add(dst, e.absPath)
                    storeTranspile("${workDir}/cache", srcText, fingerprint, result)
            }
        } else {
            File.writeTo(dst, readTextFile(e.absPath).toArray())
        }
    }

    let (code, stdoutB, stderrB) = executeWithOutput(
        "cjc", ["-p", cjSrc, "--diagnostic-format=json", "--output-dir", outDir])
    return MemberBuildResult(code, mappedCount, stdoutB, stderrB, maps, srcs)
}

/**
 * 转译产物补 package 声明：cjc -p 要求同目录同包（方言源码无 package →
 * default 包，与官方 .cj 的命名包冲突，s5t9b 实测）；产物已有则不重复。
 */
public func withPackage(text: String, pkgName: String): String {
    if (!pkgName.isEmpty() && !text.startsWith("package ")) {
        return "package ${pkgName}\n" + text
    }
    return text
}

/**
 * workspace 模式 run/check：对每个含方言源码的成员转译 + 编译，
 * 诊断按成员各自映射回方言坐标并汇总；run 模式依次运行可执行成员产物。
 */
public func runWorkspace(root: String, lang: LangPack, runMode: Bool): Int64 {
    let members = parseWorkspaceMembers(readTextFile("${root}/cjpm.toml"))
    if (members.isEmpty()) {
        println(uiText("警告：workspace 未配置 members，无可编译成员。"))
        return 1
    }
    let typeMap = buildTypeMap(lang.keywords, lang.macros, lang.aliases, lang.modulePaths)
    var failed: Int64 = 0
    var anyZh = false
    for (m in members) {
        let mRoot = normalizePath("${root}/${m}")
        if (!exists(Path("${mRoot}/src"))) {
            println(uiTextF("[{0}] 跳过：无 src/ 目录", [m]))
            continue
        }
        if (!dirHasZhFiles("${mRoot}/src")) {
            println(uiTextF("[{0}] 跳过：纯官方源码成员（无方言 .zc）", [m]))
            continue
        }
        anyZh = true
        let r = buildMember(mRoot, lang)
        printDiagnostics(r.stdoutB, r.stderrB, lang, typeMap, DiagLocator(r.maps, r.srcs))
        if (r.code != 0) {
            println(uiTextF("[{0}] 编译失败（退出码 {1}）：已替换 {2} 处方言标识符。", [m, r.code.toString(), r.mappedCount.toString()]))
            failed += 1
            continue
        }
        println(uiTextF("[{0}] 编译成功：替换方言标识符 {1} 处。", [m, r.mappedCount.toString()]))
        if (runMode) {
            // 平台产物名探测：Windows cjc 产物带 .exe 后缀
            let exePath = exeOutPath("${mRoot}/.zhc/out/main")
            if (!exists(Path(exePath))) {
                println(uiTextF("[{0}] 未找到编译产物：{1}", [m, exePath]))
                failed += 1
                continue
            }
            let (rcode, routB, rerrB) = executeWithOutput(exePath, [])
            if (routB.size > 0) {
                print(String.fromUtf8(routB))
            }
            if (rerrB.size > 0) {
                print(String.fromUtf8(rerrB))
            }
            if (rcode != 0) {
                println(uiTextF("[{0}] 运行失败（退出码 {1}）", [m, rcode.toString()]))
                failed += 1
            }
        }
    }
    if (!anyZh) {
        println(uiText("警告：workspace 无含方言源码的成员。"))
        return 1
    }
    return if (failed > 0) { 1 } else { 0 }
}
