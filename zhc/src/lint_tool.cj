package zhc

import std.collection.*
import std.env.*
import std.fs.*
import std.process.*

/**
 * 阶段 5 第二批（设计 §16.6 lint / §16.8 test + 坑 ⑫ Unicode 检查）：
 *   - zhc lint <文件.zc>：转译 → cjlint（JSON 报告）→ 位置映射回方言源码 → 母语 lint 报告
 *   - zhc test：转译项目全部方言源码 → cjpm test → 翻译测试输出（方言测试自举）
 *   - Unicode 安全检查：转译前扫描零宽/双向控制符，告警不阻断、位置精确（坑 ⑫）
 *
 * 1.0 实测（§13.1 第 28-29 条）：
 *   - cjlint -f <目录> -r json -o <报告>：报告为 JSON 数组（空报告为 []），
 *     字段 file/line/column/endLine/endColumn/analyzerName/description/
 *     defectLevel/defectType/language，行列 1-based；需 CANGJIE_HOME 环境变量；
 *   - std.unittest 1.0：@Test 宏在 std.unittest.testmacro 包；assertEqual 签名
 *     (expectedStr, actualStr, expectedVal, actualVal, isDelta: true)；
 *     cjpm test 文本输出（TP:/TCS: 行 + [ FAILED ] CASE: + Summary 汇总）；
 *   - executeWithOutput 无 cwd 参数 → 工作目录切换用 bash -c "cd ... && ..."。
 */

// ==================== zhc lint（§16.6）====================

/** 单条 lint 报告：产物路径/行列（1-based）/级别/描述。 */
class LintItem {
    public var file: String
    public var line: String
    public var col: String
    public var level: String
    public var desc: String

    public init(file: String, line: String, col: String, level: String, desc: String) {
        this.file = file
        this.line = line
        this.col = col
        this.level = level
        this.desc = desc
    }
}

/**
 * zhc lint <文件.zc> [--fix]：方言风格检查（全角标点/尾随空白/CRLF/重复空行/
 * 行长度，--fix 自动修复前三类）→ 转译到 .zhc/lint/ → cjlint JSON 报告 →
 * 位置映射回方言源码（§5.6 源映射）→ 级别本地化 + 描述透传（规则码在描述内）。
 */
public func cmdLint(args: Array<String>): Int64 {
    var path = ""
    var fix = false
    // 参数任意顺序：zhc lint <文件.zc> [--fix] 或 zhc lint --fix <文件.zc>
    for (i in 1..args.size) {
        if (args[i] == "--fix") {
            fix = true
        } else if (path.isEmpty()) {
            path = args[i]
        }
    }
    if (path.isEmpty()) {
        println("用法：zhc lint <文件.zc> [--fix]")
        return 1
    }
    let lang = resolveLangPack(resolveLang())
    if (!exists(Path(path))) {
        println("文件不存在：${path}")
        return 1
    }
    let srcRaw = readTextFile(path)
    let src = styleCheckFix(srcRaw, path, fix)
    if (fix && src != srcRaw) {
        File.writeTo(path, src.toArray())
    }
    scanUnicodeRisks(src, path)
    let result = transpileFull(src, lang)
    // 转译产物（绝对路径：cjlint 报告的 file 字段是绝对路径，映射键需一致）
    let pwd = getVariable("PWD")
    var base = "."
    if (pwd != None && !pwd.getOrThrow().isEmpty()) {
        base = pwd.getOrThrow()
    }
    let workDir = normalizePath("${base}/.zhc/lint")
    ensureDir(workDir)
    let cjPath = "${workDir}/${baseNameOf(path)}.cj"
    File.writeTo(cjPath, result.text.toArray())

    let binOpt = resolveCjlint()
    if (binOpt == None) {
        println("未找到 cjlint（请设置 CANGJIE_HOME 或将其 tools/bin 加入 PATH）")
        return 1
    }
    let report = "${workDir}/report.json"
    let bin = binOpt.getOrThrow()
    // cjlint 依赖 $CANGJIE_HOME/tools/lib（libcjlint.so，§13.1 第 28 条）；
    // executeWithOutput 无 env 参数（probe 实测），命中内置路径时 bash 包装补 LD_LIBRARY_PATH
    let home = getVariable("CANGJIE_HOME")
    var cmd = "'${bin}' -f '${workDir}' -r json -o '${report}'"
    if (home != None && !home.getOrThrow().isEmpty() && bin == "${home.getOrThrow()}/tools/bin/cjlint") {
        let cur = getVariable("LD_LIBRARY_PATH")
        let libPath = if (cur != None && !cur.getOrThrow().isEmpty()) {
            "'${home.getOrThrow()}/tools/lib:${cur.getOrThrow()}'"
        } else {
            "'${home.getOrThrow()}/tools/lib'"
        }
        cmd = "LD_LIBRARY_PATH=${libPath} ${cmd}"
    }
    let (code, _, _) = executeWithOutput("bash", ["-c", cmd])
    if (code != 0) {
        println("cjlint 执行失败（退出码 ${code}）")
        return code
    }
    if (!exists(Path(report))) {
        println("未生成 cjlint 报告：${report}")
        return 1
    }
    let maps = HashMap<String, SourceMap>()
    maps.add(cjPath, SourceMap(src, result.text, result.map))
    let srcs = HashMap<String, String>()
    srcs.add(cjPath, path)
    let loc = DiagLocator(maps, srcs)
    var errors: Int64 = 0
    var warnings: Int64 = 0
    var suggestions: Int64 = 0
    for (item in parseLintReport(readTextFile(report))) {
        let (dispFile, dispLine, dispCol) = loc.resolve(item.file, item.line, item.col)
        let label = if (item.level == "ERROR") { "错误" } else if (item.level == "WARNING") { "警告" } else { "建议" }
        if (item.level == "ERROR") {
            errors += 1
        } else if (item.level == "WARNING") {
            warnings += 1
        } else {
            suggestions += 1
        }
        println("[${label}] ${dispFile}:${dispLine}:${dispCol} ${item.desc}")
    }
    println("lint 完成：错误 ${errors}，警告 ${warnings}，建议 ${suggestions}")
    return if (errors > 0) { 1 } else { 0 }
}

/** 解析 cjlint JSON 报告（数组元素逐个字段提取，失败元素跳过不崩溃）。 */
func parseLintReport(text: String): ArrayList<LintItem> {
    let out = ArrayList<LintItem>()
    for (elem in splitJsonArray(text)) {
        let f = extractJsonStr(elem, "file")
        let l = extractJsonNum(elem, "line")
        let c = extractJsonNum(elem, "column")
        let lv = extractJsonStr(elem, "defectLevel")
        let d = extractJsonStr(elem, "description")
        if (f == None || l == None || c == None || lv == None || d == None) {
            continue
        }
        out.add(LintItem(f.getOrThrow(), l.getOrThrow(), c.getOrThrow(), lv.getOrThrow(), d.getOrThrow()))
    }
    return out
}

/** 定位 cjlint：CANGJIE_HOME/tools/bin/cjlint → PATH。 */
func resolveCjlint(): ?String {
    let home = getVariable("CANGJIE_HOME")
    if (home != None && !home.getOrThrow().isEmpty()) {
        let p = "${home.getOrThrow()}/tools/bin/cjlint"
        if (exists(Path(p))) {
            return p
        }
    }
    let (code, out, _) = executeWithOutput("bash", ["-c", "command -v cjlint"])
    if (code == 0) {
        let t = String.fromUtf8(out).trimAscii()
        if (!t.isEmpty()) {
            return t
        }
    }
    return None
}

// ==================== 方言风格检查与自动修复（教程 08.3：--fix）====================

/** 全角标点 → 半角映射（与 VS Code 扩展 FULLWIDTH_MAP 一致：（）→() ，→, ；→; ：→:）。
 * 字符字面量在仓颉中是 String，Rune 比较须用 Rune(码点) 构造（§13.1 第 31 条）。 */
let FW_FULL = [Rune(0xFF08), Rune(0xFF09), Rune(0xFF0C), Rune(0xFF1B), Rune(0xFF1A)]
let FW_HALF = [Rune(40), Rune(41), Rune(44), Rune(59), Rune(58)]

/** 风格检查计数：问题总数 / 已修复数。 */
class StyleCount {
    public var issues: Int64
    public var fixed: Int64
    public init() {
        issues = 0
        fixed = 0
    }
}

/**
 * 方言风格检查 + 可选自动修复（--fix）。
 * 检查项（教程 08.3）：全角标点（字符串/注释内豁免，与扩展词法保护一致）、
 * 尾随空白、CRLF、重复空行（最多保留 1 个）、行长度 >120（只报告不自动修）。
 * 返回修复后的文本（fix=false 时逐行重建原样）；报告逐条 [风格] 输出。
 */
public func styleCheckFix(src: String, path: String, fix: Bool): String {
    let cnt = StyleCount()
    let lines = src.split("\n")
    let out = ArrayList<String>()
    var inBlockComment = false
    var prevBlank = false
    var ln: Int64 = 1
    for (line in lines) {
        let runes = line.toRuneArray()
        // 行长度检查（原始行，超过 120 建议手动折行）
        if (runes.size > 120) {
            cnt.issues += 1
            println("[风格] ${path}:${ln}:1 行长度 ${runes.size} 超过 120（请手动折行）")
        }
        var n = runes.size
        var hasCR = n > 0 && runes[n - 1] == Rune(13)
        if (hasCR) {
            cnt.issues += 1
            println("[风格] ${path}:${ln}:${n} 使用 CRLF 换行（建议 LF）")
            if (fix) {
                n -= 1
                cnt.fixed += 1
                hasCR = false
            }
        }
        // 词法扫描（块注释跨行；字符串/行注释内不查全角标点）
        let fixedRunes = ArrayList<Rune>()
        var i: Int64 = 0
        while (i < n) {
            let r = runes[i]
            if (inBlockComment) {
                if (r == Rune(42) && i + 1 < n && runes[i + 1] == Rune(47)) {
                    fixedRunes.add(r)
                    fixedRunes.add(runes[i + 1])
                    i += 2
                    inBlockComment = false
                } else {
                    fixedRunes.add(r)
                    i += 1
                }
                continue
            }
            if (r == Rune(47) && i + 1 < n) {
                if (runes[i + 1] == Rune(47)) {
                    // 行注释：剩余原样保留
                    while (i < n) {
                        fixedRunes.add(runes[i])
                        i += 1
                    }
                    continue
                }
                if (runes[i + 1] == Rune(42)) {
                    inBlockComment = true
                    fixedRunes.add(r)
                    fixedRunes.add(runes[i + 1])
                    i += 2
                    continue
                }
            }
            if (r == Rune(34)) {
                // 字符串字面量：扫到未转义 " 结束，内部不查全角
                fixedRunes.add(r)
                i += 1
                var esc = false
                while (i < n) {
                    let c = runes[i]
                    fixedRunes.add(c)
                    if (esc) {
                        esc = false
                    } else if (c == Rune(92)) {
                        esc = true
                    } else if (c == Rune(34)) {
                        i += 1
                        break
                    }
                    i += 1
                }
                continue
            }
            // 全角标点替换
            var matched: Int64 = -1
            var fi: Int64 = 0
            while (fi < FW_FULL.size) {
                if (r == FW_FULL[fi]) {
                    matched = fi
                    break
                }
                fi += 1
            }
            if (matched >= 0) {
                cnt.issues += 1
                println("[风格] ${path}:${ln}:${i + 1} 全角标点「${r}」应为半角「${FW_HALF[matched]}」")
                if (fix) {
                    fixedRunes.add(FW_HALF[matched])
                    cnt.fixed += 1
                } else {
                    fixedRunes.add(r)
                }
                i += 1
                continue
            }
            fixedRunes.add(r)
            i += 1
        }
        // 尾随空白（先跳过行尾 \r——CRLF 已单独报告，避免被其挡住）
        var end = fixedRunes.size
        if (end > 0 && fixedRunes[end - 1] == Rune(13)) {
            end -= 1
        }
        let contentEnd = end   // 去 \r 后的有效行尾
        while (end > 0 && (fixedRunes[end - 1] == Rune(32) || fixedRunes[end - 1] == Rune(9))) {
            end -= 1
        }
        if (end < contentEnd) {
            cnt.issues += 1
            println("[风格] ${path}:${ln}:${end + 1} 行尾存在空白")
            if (fix) {
                let trimmed = ArrayList<Rune>()
                for (k in 0..end) {
                    trimmed.add(fixedRunes[k])
                }
                fixedRunes.clear()
                for (k in 0..trimmed.size) {
                    fixedRunes.add(trimmed[k])
                }
                cnt.fixed += 1
            }
        }
        // 连续空行压缩（空行判定：修正后仅空白）
        var isBlank = true
        for (r in fixedRunes) {
            if (r != Rune(32) && r != Rune(9)) {
                isBlank = false
                break
            }
        }
        if (isBlank && prevBlank) {
            cnt.issues += 1
            println("[风格] ${path}:${ln}:1 连续空行（最多保留 1 个）")
            if (fix) {
                cnt.fixed += 1
                out.add("\u{1}")   // 哨兵行，最后剔除
                prevBlank = true
                ln += 1
                continue
            }
        }
        var lineText = ""
        for (r in fixedRunes) {
            lineText = "${lineText}${r}"
        }
        out.add(lineText)
        prevBlank = isBlank
        ln += 1
    }
    var result = ""
    var first = true
    for (l in out) {
        if (l == "\u{1}") {
            continue   // 剔除哨兵（fix 删除的连续空行）
        }
        result = if (first) { l } else { "${result}\n${l}" }
        first = false
    }
    println("风格检查：发现 ${cnt.issues} 处问题" + (if (fix) { "，已修复 ${cnt.fixed} 处" } else { "" }))
    return result
}

// ==================== zhc test（§16.8）====================

/**
 * zhc test：转译项目 src/ 全部方言源码到 .zhc-test/src/（注入 package 声明，
 * cjpm 要求包名匹配 cjpm.toml name），复制 cjpm.toml 后在 .zhc-test/ 下运行
 * cjpm test，输出翻译（用例名保留方言原名——用户标识符豁免）。
 * workspace 根（[workspace] 节，s5t7）→ 对每个方言成员依次执行（testWorkspace）。
 */
public func cmdTest(): Int64 {
    let lang = resolveLangPack(resolveLang())
    let rootOpt = findProjectRoot(".")
    if (rootOpt == None) {
        println("未找到项目根（cjpm.toml）：请先 zhc init")
        return 1
    }
    let root = rootOpt.getOrThrow()
    if (isWorkspaceRoot(readTextFile("${root}/cjpm.toml"))) {
        return testWorkspace(root, lang)
    }
    // 成员根：向上查找 workspace 根（成员内任意位置驱动整个 workspace 测试）
    let wsOpt = findWorkspaceRoot(root)
    if (wsOpt != None) {
        return testWorkspace(wsOpt.getOrThrow(), lang)
    }
    return runTestIn(root, lang)
}

/** 单项目测试流程（workspace 成员复用）。 */
public func runTestIn(root: String, lang: LangPack): Int64 {
    if (!dirHasZhFiles("${root}/src")) {
        println("src/ 下没有方言源码（.zc）：zhc test 面向方言项目")
        return 1
    }
    // 包名：cjpm.toml [package] name（非法字符替换为 _，与注入的 package 声明一致）
    var pkgName = "zhc_test"
    try {
        let projToml = parseToml(readTextFile("${root}/cjpm.toml"))
        match (projToml.get("package")) {
            case None => ()
            case Some(section) =>
                let v = section.get("name")
                if (v != None) {
                    pkgName = sanitizePkgName(v.getOrThrow())
                }
        }
    } catch (e: Exception) {
        ()   // 解析失败用默认包名（cjpm 会给出更具体的错误）
    }
    // 工作目录：.zhc-test/（重建）
    let workDir = "${root}/.zhc-test"
    if (exists(Path(workDir))) {
        removeIfExists(workDir, recursive: true)
    }
    ensureDir("${workDir}/src")
    var mappedCount: Int64 = 0
    let entries = ArrayList<SourceEntry>()
    collectSourceFiles("${root}/src", "", entries)
    for (e in entries) {
        let dst = if (e.isZh) { zhToCj("${workDir}/src/${e.relPath}") } else { "${workDir}/src/${e.relPath}" }
        ensureParentDir(dst)
        if (e.isZh) {
            let srcText = readTextFile(e.absPath)
            let result = transpileFull(srcText, lang)
            mappedCount += result.total
            File.writeTo(dst, ("package ${pkgName}\n" + result.text).toArray())
        } else {
            File.writeTo(dst, readTextFile(e.absPath).toArray())
        }
    }
    // 复制项目根 cjpm.toml（src 固定 src/ = 本目录转译产物），包名替换为合法名
    let cjpmText = readTextFile("${root}/cjpm.toml")
    let patched = sanitizeTomlName(cjpmText, pkgName)
    File.writeTo("${workDir}/cjpm.toml", patched.toArray())
    // 运行 cjpm test（bash 切工作目录；输出合并便于统一翻译）
    let (code, stdoutB, stderrB) = executeWithOutput("bash", ["-c", "cd '${workDir}' && cjpm test 2>&1"])
    let combined = String.fromUtf8(stdoutB) + String.fromUtf8(stderrB)
    printTestOutput(combined)
    if (code != 0) {
        println("测试未通过（cjpm 退出码 ${code}）：已转译 ${mappedCount} 处方言标识符。")
        return code
    }
    println("测试完成：已转译 ${mappedCount} 处方言标识符。")
    return 0
}

/** workspace 测试（s5t7）：对每个含方言源码的成员依次执行 runTestIn，汇总。 */
public func testWorkspace(root: String, lang: LangPack): Int64 {
    let members = parseWorkspaceMembers(readTextFile("${root}/cjpm.toml"))
    if (members.isEmpty()) {
        println("警告：workspace 未配置 members，无可测试成员。")
        return 1
    }
    var failed: Int64 = 0
    var anyZh = false
    for (m in members) {
        let mRoot = normalizePath("${root}/${m}")
        if (!exists(Path("${mRoot}/src")) || !dirHasZhFiles("${mRoot}/src")) {
            println("[${m}] 跳过：无方言源码成员")
            continue
        }
        anyZh = true
        println("===== 测试成员：${m} =====")
        if (runTestIn(mRoot, lang) != 0) {
            failed += 1
        }
    }
    if (!anyZh) {
        println("警告：workspace 无含方言源码的成员。")
        return 1
    }
    if (failed > 0) {
        println("workspace 测试：${failed} 个成员未通过。")
        return 1
    }
    println("workspace 测试：全部成员通过。")
    return 0
}

/** 包名合法化：非字母数字下划线替换为 _（cjpm 包名要求标识符）。 */
func sanitizePkgName(name: String): String {
    var sb = ""
    for (r in name.toRuneArray()) {
        let ok = (r >= Rune(48) && r <= Rune(57)) ||
                 (r >= Rune(65) && r <= Rune(90)) ||
                 (r >= Rune(97) && r <= Rune(122)) || r == Rune(95)
        sb = if (ok) { "${sb}${r}" } else { "${sb}_" }
    }
    if (sb.isEmpty()) {
        return "zhc_test"
    }
    return sb
}

/** 替换 cjpm.toml 中 [package] 节的 name（原 name 可能含非法字符）。 */
func sanitizeTomlName(tomlText: String, newName: String): String {
    let lines = tomlText.split("\n")
    var inPackage = false
    var out = ""
    for (line in lines) {
        let t = line.trimAscii()
        if (t.startsWith("[")) {
            inPackage = t.startsWith("[package")
        }
        if (inPackage && t.startsWith("name")) {
            out = "${out}name = \"${newName}\"\n"
        } else {
            out = "${out}${line}\n"
        }
    }
    return out
}

/** 翻译 cjpm test 文本输出（§16.8）：先剥 ANSI 颜色码（PASSED/FAILED 等
 * 带 \x1b[3xm 前缀，会阻断字面替换），再关键行母语化，其余透传。 */
func printTestOutput(text: String) {
    for (line in text.split("\n")) {
        var out = stripAnsi(line)
        out = out.replace("[ FAILED ] CASE:", "[ 失败 ] 用例：")
        out = out.replace("[ PASSED ] CASE:", "[ 通过 ] 用例：")
        out = out.replace("Project tests finished", "项目测试完成")
        out = out.replace("Summary: TOTAL:", "汇总：共")
        out = out.replace("PASSED:", "通过：")
        out = out.replace("SKIPPED:", "跳过：")
        out = out.replace("ERROR:", "错误：")
        out = out.replace("FAILED:", "失败：")
        out = out.replace("Error: cjpm test failed", "错误：cjpm 测试失败")
        out = out.replace("cjpm test success", "cjpm 测试成功")
        println(out)
    }
}

/** 剥离 ANSI 转义序列：\x1b[ CSI（参数字节 0x20-0x3F，最终字节 0x40-0x7E）
 * 与 \x1b + 单字符（\x1b7 保存光标等）。不可只找 m 结尾——
 * cjpm 尾部有 \x1b[0J/\x1b[;r/\x1b[?25h 等序列，会吞掉后续文本。 */
func stripAnsi(text: String): String {
    let runes = text.toRuneArray()
    var sb = ""
    var i: Int64 = 0
    let n = runes.size
    while (i < n) {
        if (runes[i] == r'\u{1B}') {
            if (i + 1 < n && runes[i + 1] == r'[') {
                i += 2
                while (i < n && (runes[i] < Rune(0x40) || runes[i] > Rune(0x7E))) {
                    i += 1
                }
                if (i < n) {
                    i += 1   // 跳过最终字节
                }
            } else {
                i += 2   // ESC + 单字符（\x1b7/\x1b8）
            }
        } else {
            sb = "${sb}${runes[i]}"
            i += 1
        }
    }
    return sb
}

// ==================== Unicode 安全检查（坑 ⑫）====================

/** 零宽/双向控制符检查：告警不阻断，报告 行:列 精确位置（坑 ⑫）。 */
public func scanUnicodeRisks(src: String, path: String): Int64 {
    var hits: Int64 = 0
    let lines = src.split("\n")
    var ln: Int64 = 1
    for (line in lines) {
        let runes = line.toRuneArray()
        var col: Int64 = 1
        for (r in runes) {
            let what = riskyRuneName(r)
            if (what != None) {
                println("警告：${path}:${ln}:${col} 含${what.getOrThrow()}（零宽/双向控制符，建议删除防注入，坑 ⑫）")
                hits += 1
            }
            col += 1
        }
        ln += 1
    }
    return hits
}

/** 判定并描述危险字符：零宽 U+200B-200D/2060/FEFF、双向 U+202A-202E/2066-2069。 */
func riskyRuneName(r: Rune): ?String {
    let v = codePointOf(r)
    if (v == 0x200B) {
        return "零宽空格"
    }
    if (v == 0x200C) {
        return "零宽非连接符"
    }
    if (v == 0x200D) {
        return "零宽连接符"
    }
    if (v == 0x2060) {
        return "字素连接符"
    }
    if (v == 0xFEFF) {
        return "字节序标记"
    }
    if (v >= 0x202A && v <= 0x202E) {
        return "双向控制符"
    }
    if (v >= 0x2066 && v <= 0x2069) {
        return "双向隔离符"
    }
    return None
}

/** Rune 码点（String 中转按 UTF-8 字节解析，参考 json_mini.runeValue）。 */
func codePointOf(r: Rune): Int64 {
    let bytes = "${r}".toArray()
    if (bytes.size == 1) {
        return Int64(bytes[0])
    }
    // UTF-8 解码（最多 4 字节）
    var v: Int64 = 0
    var i: Int64 = 0
    var n: Int64 = bytes.size
    let b0 = Int64(bytes[0])
    var extra: Int64 = 0
    if (b0 >= 0xF0) {
        v = b0 - 0xF0
        extra = 3
    } else if (b0 >= 0xE0) {
        v = b0 - 0xE0
        extra = 2
    } else {
        v = b0 - 0xC0
        extra = 1
    }
    i = 1
    while (i <= extra && i < n) {
        v = v * 64 + (Int64(bytes[i]) - 0x80)
        i += 1
    }
    return v
}
