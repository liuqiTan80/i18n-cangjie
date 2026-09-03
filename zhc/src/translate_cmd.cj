package zhc

import std.collection.*
import std.fs.*
import std.sort.*

/**
 * zhc translate（设计 §17.2）：用 AI 把第三方仓颉库的公开 API 自动翻译成
 * 当前方言的 crates 映射（crates/<库名>.toml，键 = 母语名，值 = 官方名）。
 *
 * 流程（§17.2 六步）：
 *   ① 提取带上下文的公开 API（复用 mapping auto 的注释剥离/逐行声明扫描）；
 *   ② AI 批量润色：方言保留词约束 + 一次请求返回 {"官方名":"母语名"} JSON，
 *      响应容错（剥围栏/坏条目恒等保留）；
 *   ③ 本地质量门禁：母语名撞关键字/宏/已有映射键或条目间重复 → 携带冲突
 *      清单自动重试一次，仍冲突则该条恒等保留并逐条警告；
 *   ④ 模块路径翻译：库含子目录时把相对路径段交给 AI 译为母语段，写
 *      ["模块路径"] 节（键 = <库名>.<母语段>，值 = <库名>.<官方段>；
 *      import 整段最长前缀匹配见 import_path.cj；库名保持官方名，母语化
 *      可人工编辑本节）；
 *   ⑤ 产出 crates/<库名>.toml（语言包根，同 mapping auto；可重跑覆盖）；
 *   ⑥ 选择性共享：仅显式 --share 时导出 zhc-共享-<导出名>/（lang-packs/
 *      <代码>/crates/ + README 安装说明），不共享则不导出（映射仅留本机）。
 *
 * 传输/配置走公共模块 ai_client.cj（§17.1/§17.4）；无模型或网络失败时
 * 由 cmdTranslate 统一报错，不影响其他命令。
 */

/** zhc translate 子命令入口（main.cj case "translate" 分发）。 */
public func cmdTranslate(args: Array<String>): Int64 {
    if (args.size < 2) {
        println(uiText("用法：zhc translate <库目录> [--share [导出名]]"))
        println(uiText("  自动翻译第三方库公开 API → crates/<库名>.toml（当前方言映射）"))
        println(uiText("  需配置 AI：ZHC_AI_BASE / ZHC_AI_KEY / ZHC_AI_MODEL，或 ~/.zhc/ai.toml 的 [ai] 节"))
        return 1
    }
    let crateDir = args[1]
    if (!exists(Path(crateDir))) {
        println(uiTextF("库目录不存在：{0}", [crateDir]))
        return 1
    }
    // 解析可选 --share [导出名]（缺省导出名 = 库名）
    var shareFlag = false
    var shareName = ""
    var i: Int64 = 2
    while (i < args.size) {
        if (args[i] == "--share") {
            shareFlag = true
            if (i + 1 < args.size && !args[i + 1].startsWith("--")) {
                shareName = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        } else {
            i += 1
        }
    }
    try {
        return translateLib(crateDir, shareFlag, shareName)
    } catch (e: Exception) {
        println(uiTextF("translate 失败：{0}", [snippet(e.message, 300)]))
        return 1
    }
}

/** translate 主流程（§17.2）。 */
private func translateLib(crateDir: String, shareFlag: Bool, shareName: String): Int64 {
    let lang = resolveLangPack(resolveLang())   // 冲突集与语言信息
    let cfg = loadAiConfig()                    // model 缺失在 llmChat 报错引导
    let crate = crateNameOf(crateDir)
    // ① 提取带上下文的公开 API（字典序；ctx = 前导注释 + 声明行）
    let decls = extractPublicApiWithCtx(crateDir)
    if (decls.isEmpty()) {
        println(uiTextF("未在 {0} 的 .cj 源码中发现 public 声明", [crateDir]))
        return 1
    }
    if (decls.size > 400) {
        println(uiTextF("公开标识符过多（{0} > 400）：建议改用 zhc mapping auto 生成恒等映射后人工润色", [decls.size.toString()]))
        return 1
    }
    // ②+③ AI 批量润色 + 本地质量门禁（冲突自动重试一次）
    let packRoot = packRootOf(resolveLang())   // 提前：门禁剔除本库旧映射用
    let reserved = buildReserved(lang, crate, packRoot)
    let (finalMap, keptList) = aiPolishIds(cfg, lang, crate, decls, reserved)
    var translated: Int64 = 0
    var kept: Int64 = 0
    for (d in decls) {
        let v = finalMap.get(d.name).getOrThrow()
        if (v == d.name) {
            kept += 1
        } else {
            translated += 1
        }
    }
    for (line in keptList) {
        println(uiTextF("  [恒等保留] {0}", [line]))
    }
    // ④ 模块路径翻译（仅库含子目录时）
    let subPaths = collectSubPaths(crateDir)
    var modToml = ArrayList<String>()
    var modCount: Int64 = 0
    if (!subPaths.isEmpty()) {
        let segTrans = aiTranslateSegs(cfg, lang, crate, subPaths)
        for (official in subPaths) {
            // 官方段逐个替换为母语段；缺译的段保持官方名
            let segs = official.split(".")
            var zh = ""
            var first = true
            for (s in segs) {
                if (!first) {
                    zh = "${zh}."
                }
                first = false
                let t = segTrans.get(s)
                zh = "${zh}${if (t != None) { t.getOrThrow() } else { s }}"
            }
            let keyPath = "${crate}.${zh}"
            let valPath = "${crate}.${official}"
            modToml.add("${tomlQuote(keyPath)} = ${tomlQuote(valPath)}")
        }
        modCount = modToml.size
        if (modCount > 0) {
            println(uiTextF("模块路径映射 {0} 条：import {1}.〈母语段〉.* 可用母语书写", [modCount.toString(), crate]))
        }
    } else {
        println(uiTextF("库内无子目录：import {0}.〈符号〉无需模块路径映射", [crate]))
    }
    // ⑤ 写 crates/<库名>.toml（语言包根；与 mapping auto 相同定位与失败提示）
    var content = "# 由 zhc translate 生成（${crate} → ${lang.code} 方言，设计 §17.2）：键 = 母语名，值 = 官方名。\n" +
        "# 重新运行 zhc translate 会覆盖本文件；人工润色后请用 zhc mapping check 把关。\n"
    content = "${content}[\"标识符\"]\n"
    for (d in decls) {
        let v = finalMap.get(d.name).getOrThrow()
        content = "${content}${tomlQuote(v)} = ${tomlQuote(d.name)}\n"
    }
    if (!modToml.isEmpty()) {
        content = "${content}[\"模块路径\"]\n"
        for (m in modToml) {
            content = "${content}${m}\n"
        }
    }
    let cratesDir = "${packRoot}/lang-packs/${lang.code}/crates"
    try {
        ensureDir(cratesDir)
        File.writeTo("${cratesDir}/${crate}.toml", content.toArray())
    } catch (e: Exception) {
        println(uiTextF("写入失败（语言包目录只读？）：{0}/{1}.toml", [cratesDir, crate]))
        println(uiText("请复制内容到语言包 crates/ 目录，或用可写语言包根（ZHC_LANG_PACKS 或 ~/.zhc/）"))
        return 1
    }
    println(uiTextF("已生成：{0}/{1}.toml（公开标识符 {2} 个：翻译 {3}，恒等保留 {4}）", [cratesDir, crate, decls.size.toString(), translated.toString(), kept.toString()]))
    // ⑥ --share 选择性共享导出
    if (shareFlag) {
        exportShare(crateDir, crate, content, lang, shareName, decls.size, modCount)
    } else {
        println(uiText("映射已写入本机语言包（未共享）。如需共享给他人，加 --share 重新运行"))
    }
    return 0
}

/**
 * 冲突集：当前语言包关键字/宏/已有映射的键（方言词），防转译歧义（§17.2 门禁）。
 * 剔除本库旧 crates 映射的键：重跑 zhc translate 覆盖更新时，旧产物不当作
 * 冲突——同名键覆盖是 crates 后载的允许语义（§6.3），否则第二次运行会把
 * 第一次的产物全部误判为冲突而恒等保留。
 */
private func buildReserved(lang: LangPack, crate: String, packRoot: String): HashSet<String> {
    let selfKeys = HashSet<String>()
    let oldPath = "${packRoot}/lang-packs/${lang.code}/crates/${crate}.toml"
    if (exists(Path(oldPath))) {
        try {
            let tables = parseToml(readTextFile(oldPath))
            for (sec in ["标识符", "宏"]) {
                match (tables.get(sec)) {
                    case None => ()
                    case Some(section) =>
                        for (k in section.keys()) {
                            selfKeys.add(k)
                        }
                }
            }
        } catch (e: Exception) {
            ()   // 旧文件解析失败：不剔除（保守门禁）
        }
    }
    let reserved = HashSet<String>()
    for (k in lang.keywords.keys()) {
        reserved.add(k)
    }
    for (k in lang.macros.keys()) {
        if (!selfKeys.contains(k)) {
            reserved.add(k)
        }
    }
    for (k in lang.aliases.keys()) {
        if (!selfKeys.contains(k)) {
            reserved.add(k)
        }
    }
    return reserved
}

/**
 * ②③ AI 批量润色 + 门禁重试：返回 (官方名 → 最终母语名, 恒等保留清单)。
 * 首轮 system 携带保留词表（关键字+宏全量；stdlib 别名表量大不注入，由门禁
 * 重试反馈兜底）；冲突（撞保留词/条目间重复）时携带清单重试一次，仍冲突的
 * 条目恒等保留并逐条警告。
 */
private func aiPolishIds(cfg: AiConfig, lang: LangPack, crate: String,
                         decls: ArrayList<ApiDecl>, reserved: HashSet<String>):
                         (HashMap<String, String>, ArrayList<String>) {
    var system = aiSystemPrompt(lang)
    // user：条目列表（上下文压平截断，Rune 级 120）
    var user = "第三方库：${crate}。逐条翻译以下 ${decls.size.toString()} 个公开 API（每行：官方名 | 声明与上下文）：\n"
    for (d in decls) {
        user = "${user}- ${d.name} | ${snippet(d.ctx, 120)}\n"
    }
    var attempt: Int64 = 0
    while (attempt < 2) {
        let msgs = ArrayList<ChatMsg>()
        msgs.add(ChatMsg("system", system))
        msgs.add(ChatMsg("user", user))
        let resp = llmChat(cfg, msgs)
        let parsed = parseJsonObj(resp)
        // 逐条取值：缺键/空值 → 恒等（官方名）
        var picked = HashMap<String, String>()
        for (d in decls) {
            var name = d.name
            let v = parsed.get(d.name)
            if (v != None) {
                let t = v.getOrThrow().trimAscii()
                if (!t.isEmpty()) {
                    name = t
                }
            }
            picked.add(d.name, name)
        }
        let (clean, conflicts) = gateMappings(picked, decls, reserved)
        if (conflicts.isEmpty() || attempt >= 1) {
            return (clean, conflicts)
        }
        // 携带冲突清单重试一次（仅冲突条目的换名要求 + 保持完整 JSON）
        println(uiTextF("检测到 {0} 条映射冲突（撞关键字/宏/已有映射或条目间重复），携带清单重试一次…", [conflicts.size.toString()]))
        var fix = ""
        for (c in conflicts) {
            fix = "${fix}- ${c}\n"
        }
        system = "${system}\n上一轮有 ${conflicts.size.toString()} 条映射不合规，请为这些官方名另选母语名（其余保持）：\n${fix}仍输出完整 JSON 对象，不要输出其它文字。"
        attempt += 1
    }
    // 不可达（attempt 最多 2 轮）：给编译器确定返回
    return (HashMap<String, String>(), ArrayList<String>())
}

/**
 * 门禁（§17.2 ③）：按 decls 字典序依次收编；母语名撞保留词或已被占用
 * （条目间重复，含撞恒等条目）→ 该条恒等降级并记入清单。返回 (最终表, 清单)。
 */
private func gateMappings(picked: HashMap<String, String>, decls: ArrayList<ApiDecl>,
                          reserved: HashSet<String>): (HashMap<String, String>, ArrayList<String>) {
    let clean = HashMap<String, String>()
    let used = HashSet<String>()
    let conflicts = ArrayList<String>()
    for (d in decls) {
        let v = picked.get(d.name).getOrThrow()
        if (v == d.name) {
            // 恒等（AI 主动保留）：占位防撞，不记冲突
            clean.add(d.name, v)
            used.add(v)
        } else if (reserved.contains(v)) {
            clean.add(d.name, d.name)
            used.add(d.name)
            conflicts.add("${d.name} → ${v}（撞关键字/宏/已有映射）")
        } else if (used.contains(v)) {
            clean.add(d.name, d.name)
            used.add(d.name)
            conflicts.add("${d.name} → ${v}（与其它条目重复）")
        } else {
            clean.add(d.name, v)
            used.add(v)
        }
    }
    return (clean, conflicts)
}

/** AI 系统提示词：JSON 输出约束 + 保留词表（关键字+宏，排序保证确定性）。 */
private func aiSystemPrompt(lang: LangPack): String {
    var reservedWords = ArrayList<String>()
    for (k in lang.keywords.keys()) {
        reservedWords.add(k)
    }
    for (k in lang.macros.keys()) {
        reservedWords.add(k)
    }
    sort(reservedWords)
    var rw = ""
    var first = true
    for (w in reservedWords) {
        if (!first) {
            rw = "${rw}、"
        }
        first = false
        rw = "${rw}${w}"
    }
    return "你是「仓颉母语方言」映射翻译助手：用户用自己的母语（${lang.name}，代码 ${lang.code}）书写仓颉程序，" +
        "映射表把第三方库公开 API（官方英文名）翻译成 ${lang.name} 的母语标识符名。规则：\n" +
        "1. 只输出一个 JSON 对象 {\"官方名\": \"母语名\"}，不要输出任何其它文字或 markdown 围栏；\n" +
        "2. 母语名要简洁常用单义、贴合声明上下文；不含空格与标点；\n" +
        "3. 禁止使用下列 ${lang.code} 保留词：${rw}；\n" +
        "4. 拿不准时让键值相同（保持官方名）。"
}

/**
 * 模块路径段翻译：收集库内相对路径段（官方 import 子模块路径，点号连接），
 * AI 返回 {"官方段":"母语段"}；译段含 . / 空白或为空的条目丢弃（保持官方段）。
 */
private func aiTranslateSegs(cfg: AiConfig, lang: LangPack, crate: String,
                             subPaths: ArrayList<String>): HashMap<String, String> {
    let out = HashMap<String, String>()
    let msgs = ArrayList<ChatMsg>()
    msgs.add(ChatMsg("system",
        "你是「仓颉母语方言」路径翻译助手：把仓颉库 import 路径的子模块段翻译成 ${lang.name}（代码 ${lang.code}）。" +
        "只输出 JSON 对象 {\"官方段\": \"母语段\"}，无其它文字；译名应简短（一个名词）、不含 . / 空格与标点；" +
        "拿不准时键值相同。"))
    var user = "第三方库 ${crate} 的子模块目录段（官方 import 路径 ${crate}.〈段〉），逐段翻译：\n"
    for (p in subPaths) {
        user = "${user}- ${p}\n"
    }
    msgs.add(ChatMsg("user", user))
    let parsed = parseJsonObj(llmChat(cfg, msgs))
    for (k in parsed.keys()) {
        let v = parsed.get(k).getOrThrow().trimAscii()
        var ok = !v.isEmpty() && v.indexOf(".") == None && v.indexOf("/") == None &&
            v.indexOf(" ") == None && v.indexOf("\t") == None
        if (ok) {
            out.add(k, v)
        }
    }
    return out
}

/**
 * 收集库内 .cj 的相对目录（官方 import 子模块路径，点号连接、去重排序）。
 * 扫描根 = 库的 src/（cjpm 标准布局，存在时）否则库根；根目录（空路径）
 * 不参与；单文件库返回空表。
 */
private func collectSubPaths(root: String): ArrayList<String> {
    let scanRoot = if (exists(Path("${root}/src"))) { "${root}/src" } else { root }
    let found = HashSet<String>()
    let entries = ArrayList<SourceEntry>()
    collectSourceFiles(scanRoot, "", entries)
    for (e in entries) {
        if (!e.absPath.endsWith(".cj")) {
            continue
        }
        let rel = e.relPath
        let slashOpt = rel.lastIndexOf("/")
        if (slashOpt == None) {
            continue   // 根目录文件
        }
        let dirPart = rel[0..slashOpt.getOrThrow()]
        if (dirPart.isEmpty()) {
            continue
        }
        found.add(dirPart.replace("/", "."))
    }
    let out = ArrayList<String>()
    for (p in found) {
        out.add(p)
    }
    sort(out)
    return out
}

/**
 * ⑥ --share 导出共享目录 zhc-共享-<导出名>/：lang-packs/<代码>/crates/<库>.toml
 * + README.md（安装说明，界面语言跟随）。导出名非法（含 / 或 ..）时回退库名。
 */
private func exportShare(crateDir: String, crate: String, content: String, lang: LangPack,
                         shareName: String, idCount: Int64, modCount: Int64): Unit {
    var name = shareName
    if (name.isEmpty() || name.contains("/") || name.contains("..")) {
        if (!name.isEmpty()) {
            println(uiTextF("警告：--share 导出名不合法（{0}），已用默认名 {1}", [name, crate]))
        }
        name = crate
    }
    let outDir = "zhc-共享-${name}"
    let crateFile = "${outDir}/lang-packs/${lang.code}/crates/${crate}.toml"
    try {
        ensureDir(dirOf(crateFile))
        File.writeTo(crateFile, content.toArray())
    } catch (e: Exception) {
        println(uiTextF("共享导出失败（{0} 不可写？）：{1}", [outDir, e.message]))
        return
    }
    // README（模板经 uiText 查询，语言跟随）
    var readme = ""
    readme = "${readme}${uiTextF("# zhc 共享语言映射：{0}（{1} 方言）", [crate, lang.name])}\n"
    readme = "${readme}\n"
    readme = "${readme}${uiTextF("由 zhc translate 生成，可自由分享给使用 {0} 方言编写仓颉程序的开发者。", [lang.name])}\n"
    readme = "${readme}${uiText("安装（接收方）：")}\n"
    readme = "${readme}${uiText("1. 把 lang-packs/ 目录并入 ~/.zhc/（用户目录覆盖内置）或 ZHC_LANG_PACKS 指向的语言包根；")}\n"
    readme = "${readme}${uiText("2. 运行 zhc mapping check 验证映射质量；")}\n"
    readme = "${readme}${uiText("3. 在 cjpm.toml [dependencies] 添加该库依赖后，即可用母语 import 该库符号。")}\n"
    readme = "${readme}\n"
    readme = "${readme}${uiTextF("对应官方库：{0}（公开 API {1} 个标识符；模块路径映射 {2} 条）。", [crateDir, idCount.toString(), modCount.toString()])}\n"
    File.writeTo("${outDir}/README.md", readme.toArray())
    println(uiTextF("已导出共享目录：{0}/（接收方把 lang-packs/ 并入 ~/.zhc/ 或语言包根即生效）", [outDir]))
}
