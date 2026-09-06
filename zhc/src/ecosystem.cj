package zhc

import std.collection.*
import std.env.*
import std.fs.*
import std.sort.*

/**
 * 阶段 5 生态工具（设计 §8 CLI 表 / §3.11 / §6.3）：
 *   - zhc add <库> [--git <URL> | --path <目录>]：向 cjpm.toml [dependencies]
 *     追加依赖条目（cjpm 无 add 命令，TOML 追加写不重排）；
 *   - zhc lang list / install <目录> / remove <代码>：语言包管理，用户安装
 *     目录 ~/.zhc/lang-packs（§6.3 覆盖内置），install 校验扩展名冲突（§8）。
 *
 * 1.0 实测（§13.1 第 25 条）：顶层 removeIfExists(path, recursive: true) 删除
 * 目录树、copy(src, to: dst, overwrite: true) 复制文件，均可用。
 */

/** 用户语言包安装根：~/.zhc/lang-packs；无 HOME 时返回 None。 */
func userPackRoot(): ?String {
    let home = getVariable("HOME")
    if (home == None || home.getOrThrow().isEmpty()) {
        return None
    }
    return "${home.getOrThrow()}/.zhc/lang-packs"
}

// ==================== zhc add（§3.11）====================

/**
 * zhc add <库> [--git <URL> | --path <目录>]。
 * 裸库名缺 URL/路径时报用法并提示 crates/ 映射存在性（§3.11：提示 mapping auto）。
 */
public func cmdAdd(args: Array<String>): Int64 {
    let name = args[1]
    var gitUrl = ""
    var pathDir = ""
    var i: Int64 = 2
    while (i < args.size) {
        if (args[i] == "--git" && i + 1 < args.size) {
            gitUrl = args[i + 1]
            i += 2
        } else if (args[i] == "--path" && i + 1 < args.size) {
            pathDir = args[i + 1]
            i += 2
        } else {
            i += 1
        }
    }
    // 库名合法性：TOML 键为双引号字符串，禁止引号与等号
    if (name.contains("\"") || name.contains("=") || name.isEmpty()) {
        println(uiTextF("库名不合法（不能含引号/等号）：{0}", [name]))
        return 1
    }
    if (gitUrl.isEmpty() && pathDir.isEmpty()) {
        println(uiText("用法：zhc add <库> --git <URL> | --path <目录>"))
        println(uiTextF("  crates/ 映射：{0}", [crateMappingHint(name)]))
        return 1
    }
    let rootOpt = findProjectRoot(".")
    if (rootOpt == None) {
        println(uiText("未找到项目根（cjpm.toml）：请先 zhc init"))
        return 1
    }
    let root = rootOpt.getOrThrow()
    let cjpmPath = "${root}/cjpm.toml"
    let text = readTextFile(cjpmPath)
    // 重复条目检查：逐行匹配 `"<name>" =`
    for (line in text.split("\n")) {
        let t = line.trimAscii()
        if (t.startsWith("\"${name}\"")) {
            println(uiTextF("依赖已存在：{0}（{1}/cjpm.toml）", [name, root]))
            return 1
        }
    }
    let entry = if (!gitUrl.isEmpty()) {
        "\"${name}\" = { git = \"${gitUrl}\" }"
    } else {
        "\"${name}\" = { path = \"${pathDir}\" }"
    }
    // 插入到 [dependencies] 节内（下一个节标题之前；节不在则文件尾建节）
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
        // 无 [dependencies] 节：文件尾追加
        newText = "${text}\n[dependencies]\n${entry}\n"
    } else if (nextSection < 0) {
        // [dependencies] 是最后节：节尾追加
        newText = "${text}\n${entry}\n"
    } else {
        // 插入到下一个节标题之前（拼接按 \n 字节偏移，行边界 ASCII 安全）
        var offset: Int64 = 0
        var li: Int64 = 0
        while (li < nextSection) {
            offset += lines[li].size + 1
            li += 1
        }
        newText = "${text[0..offset]}${entry}\n${text[offset..text.size]}"
    }
    File.writeTo(cjpmPath, newText.toArray())
    println(uiTextF("已添加依赖：{0}（{1}）", [entry, cjpmPath]))
    println("  ${crateMappingHint(name)}")
    return 0
}

/** crates/ 映射存在性提示（§3.11）：扫描候选根下 crates/<库>.toml。 */
func crateMappingHint(name: String): String {
    for (base in packRootCandidates()) {
        let p = "${base}/lang-packs/crates/${name}.toml"
        if (exists(Path(p))) {
            return uiTextF("已找到映射 {0}（zhc 转译自动生效）", [p])
        }
        let p2 = "${base}/crates/${name}.toml"
        if (exists(Path(p2))) {
            return uiTextF("已找到映射 {0}（zhc 转译自动生效）", [p2])
        }
    }
    return uiTextF("未找到 crates/{0}.toml 映射，可运行 zhc mapping auto {0} 生成", [name])
}

// ==================== zhc lang（§8）====================

/** zhc lang 子命令分发。 */
public func cmdLang(args: Array<String>): Int64 {
    let sub = args[1]
    if (sub == "list") {
        return langList()
    }
    if (sub == "install") {
        if (args.size < 3) {
            println(uiText("用法：zhc lang install <语言包目录>"))
            return 1
        }
        return langInstall(args[2])
    }
    if (sub == "remove") {
        if (args.size < 3) {
            println(uiText("用法：zhc lang remove <语言包代码>"))
            return 1
        }
        return langRemove(args[2])
    }
    println(uiText("用法：zhc lang list | install <目录> | remove <代码>"))
    return 1
}

/** 列出全部语言包（跨候选根按代码去重：来源 = 生效根（首个命中），其余副本标注未生效）。 */
func langList(): Int64 {
    // 收集：代码 → 出现过的候选根（顺序 = packRootCandidates 加载优先级）
    let byCode = HashMap<String, ArrayList<String>>()
    for (base in packRootCandidates()) {
        let lpDir = "${base}/lang-packs"
        if (!exists(Path(lpDir))) {
            continue
        }
        let list = Directory.readFrom(lpDir)
        let codes = ArrayList<String>()
        for (f in list) {
            if (f.isDirectory() && !f.name.startsWith(".")) {
                codes.add(f.name)
            }
        }
        sortCodes(codes)
        for (code in codes) {
            let infoPath = "${lpDir}/${code}/lang_info.toml"
            if (!exists(Path(infoPath))) {
                continue
            }
            let roots = byCode.get(code)
            match (roots) {
                case None =>
                    let fresh = ArrayList<String>()
                    fresh.add(lpDir)
                    byCode.add(code, fresh)
                case Some(r) => r.add(lpDir)
            }
        }
    }
    // 输出：唯一代码排序；来源 = 生效候选根（首个命中，与 resolveLangPack 同序），
    // 其余候选根同名包为未生效副本（如 lang install 后当前目录也有同名包）
    let codes = ArrayList<String>()
    for (k in byCode.keys()) {
        codes.add(k)
    }
    sortCodes(codes)
    for (code in codes) {
        let sources = byCode.get(code).getOrThrow()
        let lpDir = sources[0]
        var display = code
        try {
            let info = parseToml(readTextFile("${lpDir}/${code}/lang_info.toml"))
            match (info.get("语言包")) {
                case None => ()
                case Some(section) =>
                    let vName = section.get("名称")
                    let vExt = section.get("扩展名")
                    var name = code
                    var ext = ""
                    if (vName != None) {
                        name = vName.getOrThrow()
                    }
                    if (vExt != None) {
                        ext = vExt.getOrThrow()
                    }
                    display = uiTextF("{0}（{1}）扩展名：{2}", [name, code, ext])
                    // 档位声明（schema 1，全球化路线图 ③）：诚实公布成熟度
                    let vTier = section.get("档位")
                    if (vTier != None) {
                        let vCov = section.get("界面覆盖率")
                        let cov = if (vCov != None) { vCov.getOrThrow() } else { "-" }
                        display = "${display}" + uiTextF("（{0}，界面 {1}）", [vTier.getOrThrow(), cov])
                    }
            }
        } catch (e: Exception) {
            display = uiTextF("{0}（lang_info.toml 解析失败：{1}）", [code, e.message])
        }
        var srcText = lpDir
        if (sources.size > 1) {
            var extra = ""
            var first = true
            for (i in 1..sources.size) {
                extra = if (first) { sources[i] } else { "${extra}、${sources[i]}" }
                first = false
            }
            let dup = (sources.size - 1).toString()
            srcText = "${lpDir}（另有副本 ${dup} 处：${extra}，未生效）"
        }
        println(uiTextF("  [{0}] {1}    来源：{2}", [code, display, srcText]))
        // 词条统计（文件缺失显示 -；教学可用性 = 五类文件齐全且词条数与 zh 相当）
        let kw = countQuoteKeys("${lpDir}/${code}/keywords.toml")
        let st = countQuoteKeys("${lpDir}/${code}/stdlib.toml")
        let mp = countQuoteKeys("${lpDir}/${code}/module_paths.toml")
        let ui = countQuoteKeys("${lpDir}/${code}/ui.toml")
        let diag = countSubSections("${lpDir}/${code}/errors.toml", "诊断码")
        let msg = countSubSections("${lpDir}/${code}/errors.toml", "消息翻译")
        println(uiTextF("      词条：关键字 {0} / 标准库 {1} / 模块路径 {2}", [fmtEntry(kw), fmtEntry(st), fmtEntry(mp)]))
        println(uiTextF("            诊断码 {0} / 消息兜底 {1} / 界面 {2}", [fmtEntry(diag), fmtEntry(msg), fmtEntry(ui)]))
    }
    if (codes.size == 0) {
        println(uiText("未找到任何语言包（候选根均无 lang-packs/）"))
    } else {
        println(uiTextF("共 {0} 个语言包", [codes.size.toString()]))
    }
    return 0
}

/** 语言包代码列表排序（std.sort 顶层 sort）。 */
func sortCodes(codes: ArrayList<String>) {
    sort(codes)
}

/** 词条计数：行首引号开头的键值行数（keywords/stdlib/module_paths/ui）；文件缺失返回 -1。 */
func countQuoteKeys(path: String): Int64 {
    if (!exists(Path(path))) {
        return -1
    }
    var n: Int64 = 0
    for (line in readTextFile(path).split("\n")) {
        let t = line.trimAscii()
        if (!t.isEmpty() && !t.startsWith("#") && t.startsWith("\"")) {
            n += 1
        }
    }
    return n
}

/** 二级节计数（errors.toml 的 ["诊断码"."xxx"] 等）；文件缺失返回 -1。 */
func countSubSections(path: String, section: String): Int64 {
    if (!exists(Path(path))) {
        return -1
    }
    var n: Int64 = 0
    for (line in readTextFile(path).split("\n")) {
        if (line.trimAscii().startsWith("[\"${section}\".\"")) {
            n += 1
        }
    }
    return n
}

/** 词条数显示：负数（文件缺失）显示 -。 */
func fmtEntry(n: Int64): String {
    return if (n < 0) { "-" } else { "${n}" }
}

/**
 * zhc lang install <目录>：复制到用户目录 ~/.zhc/lang-packs/<代码>/。
 * 校验：① 目录含 lang_info.toml；② 扩展名与已安装语言包冲突则拒绝（§8）。
 */
func langInstall(dir: String): Int64 {
    let infoPath = "${dir}/lang_info.toml"
    if (!exists(Path(infoPath))) {
        println(uiTextF("不是语言包目录（缺少 lang_info.toml）：{0}", [dir]))
        return 1
    }
    var code = ""
    var ext = ""
    try {
        let info = parseToml(readTextFile(infoPath))
        match (info.get("语言包")) {
            case None => ()
            case Some(section) =>
                let vCode = section.get("代码")
                let vExt = section.get("扩展名")
                if (vCode != None) {
                    code = vCode.getOrThrow()
                }
                if (vExt != None) {
                    ext = vExt.getOrThrow()
                }
        }
    } catch (e: Exception) {
        println(uiTextF("lang_info.toml 解析失败：{0}", [e.message]))
        return 1
    }
    if (code.isEmpty()) {
        println(uiTextF("语言包缺少 [语言包] 代码 字段：{0}", [dir]))
        return 1
    }
    // 扩展名冲突校验：与所有候选根已安装包（不同代码）比较
    if (!ext.isEmpty()) {
        for (base in packRootCandidates()) {
            let lpDir = "${base}/lang-packs"
            if (!exists(Path(lpDir))) {
                continue
            }
            for (f in Directory.readFrom(lpDir)) {
                if (!f.isDirectory() || f.name == code || f.name.startsWith(".")) {
                    continue
                }
                let otherInfo = "${lpDir}/${f.name}/lang_info.toml"
                if (!exists(Path(otherInfo))) {
                    continue
                }
                try {
                    let tables = parseToml(readTextFile(otherInfo))
                    match (tables.get("语言包")) {
                        case None => ()
                        case Some(section) =>
                            let vExt = section.get("扩展名")
                            if (vExt != None && vExt.getOrThrow() == ext) {
                                println(uiTextF("扩展名冲突：{0} 已被语言包 {1} 声明（{2}），拒绝安装", [ext, f.name, otherInfo]))
                                return 1
                            }
                    }
                } catch (e: Exception) {
                    ()   // 损坏包跳过（mapping check 会报告）
                }
            }
        }
    }
    let rootOpt = userPackRoot()
    if (rootOpt == None) {
        println(uiText("无法确定用户目录（HOME 未设置）"))
        return 1
    }
    let dst = "${rootOpt.getOrThrow()}/${code}"
    if (exists(Path(dst))) {
        println(uiTextF("已安装同代码语言包：{0}（先 zhc lang remove {1} 再安装）", [dst, code]))
        return 1
    }
    copyDirRecursive(dir, dst)
    println(uiTextF("已安装语言包：{0} → {1}", [code, dst]))
    if (!ext.isEmpty()) {
        println(uiTextF("  扩展名：{0}（.{0} 文件将被路由到该语言包）", [ext]))
    }
    return 0
}

/** zhc lang remove <代码>：仅删除用户目录安装的语言包（内置包不可删）。 */
func langRemove(code: String): Int64 {
    let rootOpt = userPackRoot()
    if (rootOpt == None) {
        println(uiText("无法确定用户目录（HOME 未设置）"))
        return 1
    }
    let dst = "${rootOpt.getOrThrow()}/${code}"
    if (!exists(Path(dst))) {
        println(uiTextF("用户目录未安装语言包 {0}（内置包不可删除）：{1}", [code, dst]))
        return 1
    }
    let ok = removeIfExists(dst, recursive: true)
    if (ok) {
        println(uiTextF("已删除用户语言包：{0}", [code]))
        return 0
    }
    println(uiTextF("删除失败：{0}", [dst]))
    return 1
}

/** 递归复制目录（语言包目录结构：顶层 toml + crates/ 子目录）。 */
func copyDirRecursive(src: String, dst: String): Unit {
    ensureDir(dst)
    let list = Directory.readFrom(src)
    for (f in list) {
        if (f.name.startsWith(".")) {
            continue
        }
        let s = "${src}/${f.name}"
        let d = "${dst}/${f.name}"
        if (f.isDirectory()) {
            copyDirRecursive(s, d)
        } else {
            File.writeTo(d, File.readFrom(s))
        }
    }
}
