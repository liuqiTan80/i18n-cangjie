package zhc

import std.collection.*
import std.env.*
import std.fs.*
import std.sort.*

/**
 * 阶段 5 映射质量工具链（设计 §10）：
 *   - zhc mapping check：质量门禁五项（同文件重复键 / 关键字碰撞 / 跨文件同键
 *     不同值 / 跨语言条目数一致性 / TOML 解析合法性），逐语言包报告，纳入 CI；
 *   - zhc mapping scaffold <源> <目标>：以成熟语言包为源生成目标语言翻译骨架
 *     （键 = 官方值恒等映射，待人工润色），用于第二自然语言包验证语言无关性。
 * 确定性要求（坑 ①）：一切多文件/多节合并前排序。
 */

/** 候选语言包根（base 目录，其下 lang-packs/<code>），与 resolveLangPack 一致：
 *  ZHC_LANG_PACKS（显式指定时仅此根）→ 当前目录 → 可执行文件旁 → ~/.zhc/lang-packs。 */
public func packRootCandidates(): ArrayList<String> {
    let roots = ArrayList<String>()
    let envDir = getVariable("ZHC_LANG_PACKS")
    if (envDir != None && !envDir.getOrThrow().isEmpty()) {
        roots.add(envDir.getOrThrow())
        return roots
    }
    roots.add(".")
    let exeDir = executableDir()
    if (exeDir != None) {
        roots.add(exeDir.getOrThrow())
    }
    let home = getVariable("HOME")
    if (home != None && !home.getOrThrow().isEmpty()) {
        roots.add("${home.getOrThrow()}/.zhc")
    }
    return roots
}

/** zhc mapping 子命令分发。 */
public func cmdMapping(args: Array<String>): Int64 {
    let sub = args[1]
    if (sub == "check") {
        // §16.5：mapping check --missing 扫描诊断日志生成待翻译清单
        if (args.size >= 3 && args[2] == "--missing") {
            return mappingMissing()
        }
        return mappingCheck()
    }
    if (sub == "scaffold") {
        if (args.size < 4) {
            println("用法：zhc mapping scaffold <源语言> <目标语言>")
            return 1
        }
        return mappingScaffold(args[2], args[3])
    }
    if (sub == "auto") {
        // s5t9b：第三方库映射自动提取（§10）——生成 crates/<库>.toml
        return cmdMappingAuto(args)
    }
    println("用法：zhc mapping check [--missing] | scaffold <源> <目标> | auto <库目录> [--install <库名>=<路径>]")
    return 1
}

/**
 * §16.5 错误字典自生成（社区共建闭环）：扫描 ~/.zhc/diag-log/diag.log
 * （zhc check/run 未命中消息表时由 logMiss 写入，见 diagnostic.cj），
 * 聚合输出待翻译清单：消息原文 + 出现次数 + 示例 content。
 * 清单可直接作为 errors.toml [消息翻译] 精确匹配键的 PR 素材。
 */
public func mappingMissing(): Int64 {
    let home = getVariable("HOME")
    if (home == None || home.getOrThrow().isEmpty()) {
        println("无法确定 HOME，无法读取诊断日志。")
        return 1
    }
    let logPath = "${home.getOrThrow()}/.zhc/diag-log/diag.log"
    if (!exists(Path(logPath))) {
        println("暂无未命中消息记录（${logPath} 不存在）。")
        println("提示：运行 zhc check/run 遇到未翻译消息后会自动记录，再执行本命令生成清单。")
        return 0
    }
    // 统计：消息原文 → (次数, 首个示例 content)
    let counts = HashMap<String, Int64>()
    let samples = HashMap<String, String>()
    for (line in readTextFile(logPath).split("\n")) {
        if (line.isEmpty()) {
            continue
        }
        let tabOpt = line.indexOf("\t")
        let msg = if (tabOpt == None) { line } else { line[0..tabOpt.getOrThrow()] }
        let content = if (tabOpt == None) { "" } else { line[tabOpt.getOrThrow() + 1..line.size] }
        if (msg.isEmpty()) {
            continue
        }
        let c = counts.get(msg)
        if (c == None) {
            counts.add(msg, 1)
            samples.add(msg, content)
        } else {
            counts.add(msg, c.getOrThrow() + 1)
            if (samples.get(msg) == None || samples.get(msg).getOrThrow().isEmpty()) {
                samples.add(msg, content)
            }
        }
    }
    if (counts.isEmpty()) {
        println("诊断日志为空（${logPath}）。")
        return 0
    }
    // 排序：消息原文升序（确定性，坑 ①；次数列在输出中展示）
    let keys = ArrayList<String>()
    for (k in counts.keys()) {
        keys.add(k)
    }
    sort(keys)
    println("=== 待翻译消息清单（来自 ${logPath}）===")
    for (k in keys) {
        println("出现 ${counts.get(k).getOrThrow()} 次：${k}")
        let sample = samples.get(k)
        if (sample != None && !sample.getOrThrow().isEmpty()) {
            println("  示例：${sample.getOrThrow()}")
        }
    }
    println("（消息原文可直接作为 errors.toml [消息翻译] 的精确匹配键提交）")
    return 0
}

// ==================== mapping check（§10 五项）====================

/** 单个语言包的检查统计。 */
class PackStats {
    public var code: String
    public var kwCount: Int64
    public var failCount: Int64

    public init(code: String, kwCount: Int64, failCount: Int64) {
        this.code = code
        this.kwCount = kwCount
        this.failCount = failCount
    }
}

/** 质量门禁：扫描全部语言包执行五项检查，返回退出码（0 = 全过）。 */
public func mappingCheck(): Int64 {
    var packs = ArrayList<PackStats>()
    for (base in packRootCandidates()) {
        let lpDir = "${base}/lang-packs"
        if (!exists(Path(lpDir))) {
            continue
        }
        let codes = ArrayList<String>()
        for (f in Directory.readFrom(lpDir)) {
            if (f.isDirectory() && !f.name.startsWith(".")) {
                codes.add(f.name)
            }
        }
        sort(codes)
        for (code in codes) {
            packs.add(checkOnePack(base, code))
        }
    }
    if (packs.isEmpty()) {
        println("未找到任何语言包，mapping check 无可检查项")
        return 1
    }
    // ④ 跨语言条目数一致性：按官方值覆盖集比较（§10 检查项 ④）。
    // 口径 = 去重后的官方值数：语言包内部允许多对一同义词（如 `是`/`属于` → is），
    // 骨架/新包只要覆盖同一官方语法集即视为一致。
    var maxKw: Int64 = 0
    for (p in packs) {
        if (p.kwCount > maxKw) {
            maxKw = p.kwCount
        }
    }
    var consistent = true
    for (p in packs) {
        if (p.kwCount < maxKw) {
            println("[警告] ${p.code}：关键字/宏条目 ${p.kwCount} < 最多 ${maxKw}（跨语言条目数不一致）")
            consistent = false
        }
    }
    var failed = 0
    for (p in packs) {
        if (p.failCount > 0) {
            failed += 1
        }
    }
    let summary = if (failed == 0 && consistent) { "全部通过" } else { "存在 ${failed} 个失败包 / ${if (consistent) { 0 } else { 1 }} 项一致性警告" }
    println("=== mapping check：${packs.size} 个语言包，${summary} ===")
    return if (failed == 0 && consistent) { 0 } else { 1 }
}

/** 单个语言包五项检查：⑤ TOML 合法性 / ① 重复键 / ③ 跨节同键不同值 / ② 关键字碰撞。 */
func checkOnePack(base: String, code: String): PackStats {
    var fail = 0
    println("--- ${code}（${base}/lang-packs/${code}）---")
    // ⑤ TOML 解析合法性 + ① 节内重复键（parseToml 对重复键抛异常）
    let files = ["lang_info.toml", "keywords.toml", "module_paths.toml", "stdlib.toml", "ui.toml"]
    for (fn in files) {
        let p = "${base}/lang-packs/${code}/${fn}"
        if (!exists(Path(p))) {
            continue
        }
        try {
            parseToml(readTextFile(p))
        } catch (e: Exception) {
            println("  [失败] ${fn}：${e.message}")
            fail += 1
        }
    }
    let errPath = "${base}/lang-packs/${code}/errors.toml"
    if (exists(Path(errPath))) {
        try {
            parseTomlNested(readTextFile(errPath))
        } catch (e: Exception) {
            println("  [失败] errors.toml：${e.message}")
            fail += 1
        }
    }
    // 完整加载（复用 loadLangPack：任何文件解析异常都会抛，补 ⑤ 覆盖）
    var pack: LangPack
    try {
        let loaded = loadLangPack(base, code)
        match (loaded) {
            case None =>
                println("  [失败] 加载失败：缺少 lang_info.toml")
                return PackStats(code, 0, fail + 1)
            case Some(p) =>
                pack = p
        }
    } catch (e: Exception) {
        println("  [失败] 加载失败：${e.message}")
        return PackStats(code, 0, fail + 1)
    }
    // ③ 跨节同键不同值（keywords.toml 各节合并后冲突；§6.3 后载覆盖只允许
    // module_paths → stdlib 模块路径方向，其余同键不同值均属错误）
    let kwPath = "${base}/lang-packs/${code}/keywords.toml"
    if (exists(Path(kwPath))) {
        try {
            let tables = parseToml(readTextFile(kwPath))
            let seen = HashMap<String, String>()
            let sectionNames = ArrayList<String>()
            for (s in tables.keys()) {
                sectionNames.add(s)
            }
            sort(sectionNames)
            for (section in sectionNames) {
                if (section == "宏") {
                    continue   // 宏表独立（@ 后专用），不与关键字表合并
                }
                let table = tables.get(section).getOrThrow()
                let keys = ArrayList<String>()
                for (k in table.keys()) {
                    keys.add(k)
                }
                sort(keys)
                for (k in keys) {
                    let v = table.get(k).getOrThrow()
                    let prev = seen.get(k)
                    match (prev) {
                        case None =>
                            seen.add(k, v)
                        case Some(pv) =>
                            if (pv != v) {
                                println("  [失败] 跨节同键不同值：${k}（${pv} vs ${v}）")
                                fail += 1
                            }
                    }
                }
            }
        } catch (e: Exception) {
            ()   // ⑤ 已报告
        }
    }
    // ② 关键字碰撞：别名/宏键不得与关键字键相同（`让` 不能再当库别名）
    for (k in pack.aliases.keys()) {
        if (pack.keywords.contains(k)) {
            println("  [失败] 别名与关键字碰撞：${k} 既是关键字又是别名")
            fail += 1
        }
    }
    for (k in pack.macros.keys()) {
        if (pack.keywords.contains(k)) {
            println("  [失败] 宏与关键字碰撞：${k} 既是关键字又是宏")
            fail += 1
        }
    }
    // ④ 统计口径：官方值覆盖集（去重），多对一同义词不重复计数
    let kwVals = HashSet<String>()
    for (k in pack.keywords.keys()) {
        kwVals.add(pack.keywords.get(k).getOrThrow())
    }
    for (k in pack.macros.keys()) {
        kwVals.add(pack.macros.get(k).getOrThrow())
    }
    let kwCount = kwVals.size
    if (fail == 0) {
        println("  通过（关键字/宏覆盖 ${kwCount} 个官方值，别名 ${pack.aliases.size} 条，模块路径 ${pack.modulePaths.size} 条）")
    }
    return PackStats(code, kwCount, fail)
}

// ==================== mapping scaffold（§10）====================

/**
 * 生成目标语言翻译骨架：键 = 官方值（恒等映射，待人工润色）。
 * 输出到用户语言包目录 ~/.zhc/lang-packs/<目标>/，保持源包节结构
 * 与确定性排序（坑 ①）。第二语言包用于验证引擎语言无关性。
 */
public func mappingScaffold(srcCode: String, dstCode: String): Int64 {
    // 定位源包
    var srcBase = ""
    var found = false
    for (base in packRootCandidates()) {
        if (exists(Path("${base}/lang-packs/${srcCode}/lang_info.toml"))) {
            srcBase = base
            found = true
            break
        }
    }
    if (!found) {
        println("未找到源语言包：${srcCode}")
        return 1
    }
    let rootOpt = userPackRoot()
    if (rootOpt == None) {
        println("无法确定用户目录（HOME 未设置）")
        return 1
    }
    let dst = "${rootOpt.getOrThrow()}/${dstCode}"
    if (exists(Path(dst))) {
        println("目标语言包已存在：${dst}（先 zhc lang remove ${dstCode} 再生成）")
        return 1
    }
    ensureDir(dst)
    // lang_info.toml
    let info = "[\"语言包\"]\n\"代码\" = \"${dstCode}\"\n\"名称\" = \"${dstCode}\"\n\"扩展名\" = \"${dstCode}\"\n\"版本\" = \"0.1.0\"\n\"作者\" = \"zhc mapping scaffold（源：${srcCode}）\"\n"
    File.writeTo("${dst}/lang_info.toml", info.toArray())
    // keywords.toml：保留源节结构，键 = 官方值
    var kwOut = "# ${dstCode} 语言包骨架（zhc mapping scaffold ${srcCode} ${dstCode} 生成，键 = 官方值恒等映射，待人工润色）\n"
    let kwTables = parseToml(readTextFile("${srcBase}/lang-packs/${srcCode}/keywords.toml"))
    let sectionNames = ArrayList<String>()
    for (s in kwTables.keys()) {
        sectionNames.add(s)
    }
    sort(sectionNames)
    for (section in sectionNames) {
        let table = kwTables.get(section).getOrThrow()
        kwOut = "${kwOut}\n[\"${section}\"]\n"
        let keys = ArrayList<String>()
        for (k in table.keys()) {
            keys.add(k)
        }
        sort(keys)
        // 值去重：源包多个母语键可能映射同一官方值（多对一），骨架键 = 官方值只保留首个
        let seenVals = HashSet<String>()
        for (k in keys) {
            let v = table.get(k).getOrThrow()
            if (seenVals.contains(v)) {
                continue
            }
            seenVals.add(v)
            kwOut = "${kwOut}\"${v}\" = \"${v}\"\n"
        }
    }
    File.writeTo("${dst}/keywords.toml", kwOut.toArray())
    // module_paths.toml + stdlib.toml（标识符键 = 官方值）
    let mpPath = "${srcBase}/lang-packs/${srcCode}/module_paths.toml"
    if (exists(Path(mpPath))) {
        let tables = parseToml(readTextFile(mpPath))
        var out = "# 模块路径骨架（键 = 官方路径，恒等）\n[\"模块路径\"]\n"
        match (tables.get("模块路径")) {
            case None => ()
            case Some(section) =>
                let keys = ArrayList<String>()
                for (k in section.keys()) {
                    keys.add(k)
                }
                sort(keys)
                let seenVals = HashSet<String>()
                for (k in keys) {
                    let v = section.get(k).getOrThrow()
                    if (seenVals.contains(v)) {
                        continue
                    }
                    seenVals.add(v)
                    out = "${out}\"${v}\" = \"${v}\"\n"
                }
        }
        File.writeTo("${dst}/module_paths.toml", out.toArray())
    }
    let slPath = "${srcBase}/lang-packs/${srcCode}/stdlib.toml"
    if (exists(Path(slPath))) {
        let tables = parseToml(readTextFile(slPath))
        var out = "# 标识符骨架（键 = 官方值，恒等，待人工润色）\n[\"标识符\"]\n"
        match (tables.get("标识符")) {
            case None => ()
            case Some(section) =>
                let keys = ArrayList<String>()
                for (k in section.keys()) {
                    keys.add(k)
                }
                sort(keys)
                let seenVals = HashSet<String>()
                for (k in keys) {
                    let v = section.get(k).getOrThrow()
                    if (seenVals.contains(v)) {
                        continue
                    }
                    seenVals.add(v)
                    out = "${out}\"${v}\" = \"${v}\"\n"
                }
        }
        File.writeTo("${dst}/stdlib.toml", out.toArray())
    }
    println("已生成语言包骨架：${dstCode} → ${dst}")
    println("  键 = 官方值（恒等映射）：zhc run 该语言源码即原样转译，验证引擎语言无关性")
    println("  下一步：润色键名后运行 zhc mapping check 验证质量门禁")
    return 0
}
