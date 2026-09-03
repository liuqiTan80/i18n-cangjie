package zhc

import std.collection.*
import std.env.*
import std.fs.*
import std.sort.*

/**
 * 阶段 5（s5t9b）：mapping auto——第三方库映射自动提取（设计 §10）。
 *
 * 流程：扫描库源码目录的 .cj 文件 → 提取 public 声明（func/let/var/const/
 * class/struct/interface/enum/type/macro）的标识符 → 生成 crates/<库名>.toml
 * （["标识符"] 节，值 = 官方原名恒等，待人工润色为母语）→ 可选 --install
 * 顺带追加 [dependencies]（复用 §12.3 add 的策略）。
 *
 * 提取是启发式逐行扫描（教学库可控；块注释跨行状态机 + 行注释/字符串跳过），
 * 不解析 AST（std.ast 1.0 无公开 API，见 §13 实测项）。生成的映射由
 * mapping check 五项门禁把关（§10）。
 */

/** 库目录 → 库展示名（basename，非法字符转下划线，与 init 包名清洗一致）。
 * public：zhc translate（§17.2）共用。 */
public func crateNameOf(dir: String): String {
    let base = baseNameOf(dir)
    var out = ""
    for (c in base.toRuneArray()) {
        if (c.isAsciiLetter() || c.isAsciiNumber() || c == r'_' || c == r'-' || c == r'.') {
            out = "${out}${c}"
        } else {
            out = "${out}_"
        }
    }
    if (out.isEmpty()) {
        return "crate"
    }
    return out
}

/** ASCII 标识符字符（官方库 API 均为 ASCII）。 */
private func isIdRune(c: Rune): Bool {
    return c.isAsciiLetter() || c.isAsciiNumber() || c == r'_'
}

/**
 * 逐行注释剥离状态机：块注释跨行（/* */），行注释与字符串字面量跳过；
 * 返回 (处理后文本, 是否仍在块注释中)。1.0 无行注释/块注释 API，自实现。
 */
private func stripComments(line0: String, inBlock: Bool): (String, Bool) {
    var line = line0
    var blk = inBlock
    var done = false
    while (!done) {
        done = true
        if (blk) {
            let eOpt = line.indexOf("*/")
            if (eOpt == None) {
                return ("", true)
            }
            line = line[eOpt.getOrThrow() + 2..line.size]
            blk = false
            done = false
            continue
        }
        // 跳过字符串字面量："..." 与 f"..." 前缀（教学库中 public 声明行无字符串）
        let cOpt = line.indexOf("//")
        let bOpt = line.indexOf("/*")
        if (cOpt != None && (bOpt == None || cOpt.getOrThrow() < bOpt.getOrThrow())) {
            return (line[0..cOpt.getOrThrow()], false)
        }
        if (bOpt != None) {
            // 同行闭合的 /* ... */：截断前先找 */，闭合后保留行内剩余代码继续扫描
            let rest = line[bOpt.getOrThrow() + 2..line.size]
            let eOpt = rest.indexOf("*/")
            if (eOpt == None) {
                line = line[0..bOpt.getOrThrow()]
                blk = true
            } else {
                line = "${line[0..bOpt.getOrThrow()]}${rest[eOpt.getOrThrow() + 2..rest.size]}"
            }
            done = false
            continue
        }
        return (line, false)
    }
    return (line, blk)
}

/**
 * 单行 public 声明扫描：`public <关键字> <名字>` 提取名字（去重入 seen）。
 * String 下标返回 UInt8（字节），统一 toRuneArray 后按 Rune 处理（lexer 同款）。
 */
private func scanPublicDecls(line: String, seen: HashSet<String>): Unit {
    let ids = scanPublicDeclsOf(line)
    for (id in ids) {
        seen.add(id)
    }
}

/** 单行 public 声明扫描：返回本行命中的标识符列表（可多个 public 声明同行）。 */
private func scanPublicDeclsOf(line: String): ArrayList<String> {
    let out = ArrayList<String>()
    let runes = line.toRuneArray()
    let n = runes.size
    var i: Int64 = 0
    while (i + 6 <= n) {
        if (runes[i] == r'p' && runes[i + 1] == r'u' && runes[i + 2] == r'b' &&
            runes[i + 3] == r'l' && runes[i + 4] == r'i' && runes[i + 5] == r'c') {
            if (i > 0 && isIdRune(runes[i - 1])) {
                i += 6
                continue
            }
            var j = i + 6
            while (j < n && (runes[j] == r' ' || runes[j] == r'\t')) {
                j += 1
            }
            var k = j
            while (k < n && isIdRune(runes[k])) {
                k += 1
            }
            let kw = String(runes[j..k])
            if (kw == "func" || kw == "let" || kw == "var" || kw == "const" ||
                kw == "class" || kw == "struct" || kw == "interface" || kw == "enum" ||
                kw == "type" || kw == "macro") {
                var m = k
                while (m < n && (runes[m] == r' ' || runes[m] == r'\t')) {
                    m += 1
                }
                var q = m
                while (q < n && isIdRune(runes[q])) {
                    q += 1
                }
                if (q > m) {
                    out.add(String(runes[m..q]))
                }
                i = q
            } else {
                i = j + 1
            }
        } else {
            i += 1
        }
    }
    return out
}

/** 提取库源码 public API 标识符（去重 + 字典序，确定性输出）。 */
public func extractPublicApi(root: String): ArrayList<String> {
    let seen = HashSet<String>()
    let entries = ArrayList<SourceEntry>()
    collectSourceFiles(root, "", entries)
    for (e in entries) {
        if (!e.absPath.endsWith(".cj")) {
            continue
        }
        let text = readTextFile(e.absPath)
        var inBlock = false
        for (line0 in text.split("\n")) {
            let (clean, blk) = stripComments(line0, inBlock)
            inBlock = blk
            if (clean.isEmpty()) {
                continue
            }
            scanPublicDecls(clean, seen)
        }
    }
    let out = ArrayList<String>()
    for (id in seen) {
        out.add(id)
    }
    sort(out)
    return out
}

/**
 * public API 声明条目（zhc translate 用）：官方名 + 翻译上下文。
 * ctx = 紧邻前导 `//` 注释块 + 声明行原文（换行连接），供 LLM 判断用途。
 */
public class ApiDecl {
    public var name: String
    public var ctx: String
    public init(name: String, ctx: String) {
        this.name = name
        this.ctx = ctx
    }
}

/**
 * 带上下文的公开 API 提取（zhc translate 用）：(id → ctx) 列表，按 id 字典序。
 * 整行 `//` 注释累积为上下文，遇到空行/普通代码行清空（紧邻原则）；
 * 跨行块注释与行内注释由 stripComments 处理，不作上下文（教学库以 // 说明 API）。
 */
public func extractPublicApiWithCtx(root: String): ArrayList<ApiDecl> {
    let seen = HashMap<String, ApiDecl>()
    let entries = ArrayList<SourceEntry>()
    collectSourceFiles(root, "", entries)
    for (e in entries) {
        if (!e.absPath.endsWith(".cj")) {
            continue
        }
        let text = readTextFile(e.absPath)
        var inBlock = false
        var pending = ""
        for (line0 in text.split("\n")) {
            let trimmed = line0.trimAscii()
            if (inBlock) {
                // 跨行块注释：找闭合后继续处理本行剩余代码
                let closeOpt = line0.indexOf("*/")
                if (closeOpt == None) {
                    continue
                }
                inBlock = false
            } else if (trimmed.startsWith("//")) {
                pending = if (pending.isEmpty()) { trimmed } else { "${pending}\n${trimmed}" }
                continue
            }
            let (clean, blk) = stripComments(line0, inBlock)
            inBlock = blk
            if (clean.isEmpty()) {
                continue
            }
            let ids = scanPublicDeclsOf(clean)
            if (!ids.isEmpty()) {
                for (id in ids) {
                    if (!seen.contains(id)) {
                        let ctx = if (pending.isEmpty()) { trimmed } else { "${pending}\n${trimmed}" }
                        seen.add(id, ApiDecl(id, ctx))
                    }
                }
                pending = ""
            } else {
                pending = ""   // 普通代码行打断注释与后续声明的紧邻关系
            }
        }
    }
    let out = ArrayList<ApiDecl>()
    let names = ArrayList<String>()
    for (id in seen.keys()) {
        names.add(id)
    }
    sort(names)
    for (id in names) {
        out.add(seen.get(id).getOrThrow())
    }
    return out
}

/** 语言包根目录（与 resolveLangPack 相同候选顺序；找不到抛异常）。 */
public func packRootOf(code: String): String {
    let envDir = getVariable("ZHC_LANG_PACKS")
    if (envDir != None && !envDir.getOrThrow().isEmpty()) {
        if (exists(Path("${envDir.getOrThrow()}/lang-packs/${code}"))) {
            return envDir.getOrThrow()
        }
    }
    let candidates = ArrayList<String>()
    candidates.add(".")
    let exeDir = executableDir()
    if (exeDir != None) {
        candidates.add(exeDir.getOrThrow())
        candidates.add(dirOf(exeDir.getOrThrow()))   // 离线包结构 bin/ + 顶层 lang-packs/
    }
    let home = getVariable("HOME")
    if (home != None && !home.getOrThrow().isEmpty()) {
        candidates.add("${home.getOrThrow()}/.zhc")
    }
    for (base in candidates) {
        if (exists(Path("${base}/lang-packs/${code}"))) {
            return base
        }
    }
    throw TomlParseError("未找到语言包 `${code}` 的根目录（ZHC_LANG_PACKS / 可执行文件旁 / ~/.zhc）")
}

/** 追加依赖条目到项目 cjpm.toml 的 [dependencies] 节（与 cmdAdd 相同策略，§12.3）。 */
private func appendDep(root: String, name: String, entry: String): Bool {
    let cjpmPath = "${root}/cjpm.toml"
    let text = readTextFile(cjpmPath)
    for (line in text.split("\n")) {
        if (line.trimAscii().startsWith("\"${name}\"")) {
            println(uiTextF("依赖已存在：{0}（{1}）", [name, cjpmPath]))
            return false
        }
    }
    let lines = text.split("\n")
    var depLine: Int64 = -1
    var nextSection: Int64 = -1
    var idx: Int64 = 0
    while (idx < lines.size) {
        let t = lines[idx].trimAscii()
        if (depLine < 0 && t == "[dependencies]") {
            depLine = idx
        } else if (depLine >= 0 && t.startsWith("[") && t.endsWith("]") && nextSection < 0) {
            nextSection = idx
            break
        }
        idx += 1
    }
    var newText = ""
    if (depLine < 0) {
        newText = "${text}\n[dependencies]\n${entry}\n"
    } else if (nextSection < 0) {
        newText = "${text}\n${entry}\n"
    } else {
        var offset: Int64 = 0
        var li: Int64 = 0
        while (li < nextSection) {
            offset += lines[li].size + 1
            li += 1
        }
        newText = "${text[0..offset]}${entry}\n${text[offset..text.size]}"
    }
    File.writeTo(cjpmPath, newText.toArray())
    println(uiTextF("已追加依赖：{0} → {1}/cjpm.toml", [name, root]))
    return true
}

/**
 * zhc mapping auto <库目录> [--install <库名>=<路径>]
 * 生成 crates/<库名>.toml 到语言包根；--install 顺带追加 [dependencies]。
 */
public func cmdMappingAuto(args: Array<String>): Int64 {
    if (args.size < 3) {
        println(uiText("用法：zhc mapping auto <库目录> [--install <库名>=<相对路径>]"))
        println(uiText("  提取 .cj 公开 API 生成 crates/<库名>.toml（恒等映射，值待润色）"))
        return 1
    }
    let crateDir = args[2]
    if (!exists(Path(crateDir))) {
        println(uiTextF("库目录不存在：{0}", [crateDir]))
        return 1
    }
    var installName = ""
    var installPath = ""
    var i: Int64 = 3
    while (i < args.size) {
        if (args[i] == "--install" && i + 1 < args.size) {
            let pair = args[i + 1]
            let eqOpt = pair.indexOf("=")
            if (eqOpt != None) {
                installName = pair[0..eqOpt.getOrThrow()]
                installPath = pair[eqOpt.getOrThrow() + 1..pair.size]
            } else {
                println(uiText("--install 参数格式：<库名>=<相对路径>（如 --install mylib=../mylib）"))
                return 1
            }
            i += 2
        } else {
            i += 1
        }
    }

    // ① 提取 public API（排序去重）
    let ids = extractPublicApi(crateDir)
    if (ids.isEmpty()) {
        println(uiTextF("未在 {0} 的 .cj 源码中发现 public 声明", [crateDir]))
        return 1
    }

    // ② 生成 crates/<库名>.toml（恒等映射；["模块路径"] 节留待人工补充）
    let name = crateNameOf(crateDir)
    var content = "# 由 zhc mapping auto 生成（${name}）——值 = 官方原名，\n" +
        "# 待人工润色为母语（质量由 mapping check 把关）。import 路径映射请在\n" +
        "# [\"模块路径\"] 节补充。\n"
    content = "${content}[\"标识符\"]\n"
    for (id in ids) {
        content = "${content}\"${id}\" = \"${id}\"\n"
    }
    let packRoot = packRootOf(resolveLang())
    let cratesDir = "${packRoot}/lang-packs/${resolveLang()}/crates"
    try {
        ensureDir(cratesDir)
        File.writeTo("${cratesDir}/${name}.toml", content.toArray())
    } catch (e: Exception) {
        println(uiTextF("写入失败（语言包目录只读？）：{0}/{1}.toml", [cratesDir, name]))
        println(uiText("请复制内容到语言包 crates/ 目录，或用可写语言包根（ZHC_LANG_PACKS 或 ~/.zhc/）"))
        return 1
    }
    println(uiTextF("已生成：{0}/{1}.toml（{2} 个公开标识符）", [cratesDir, name, ids.size.toString()]))
    println(uiText("值当前为官方原名恒等；润色后经 zhc mapping check 验证即生效"))

    // ③ --install：追加依赖到当前项目 cjpm.toml
    if (!installName.isEmpty()) {
        let rootOpt = findProjectRoot(".")
        if (rootOpt == None) {
            println(uiText("未找到项目根（cjpm.toml），跳过 --install"))
            return 1
        }
        appendDep(rootOpt.getOrThrow(), installName, "\"${installName}\" = { path = \"${installPath}\" }")
    }
    return 0
}
