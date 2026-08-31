package zhc

import std.collection.*
import std.env.*
import std.fs.*
import std.sort.*

/**
 * 诊断翻译（设计 §7.2 决策链 + §7.4 教学增强 + §16.9 可粘贴修复示例）。
 *
 * 决策链（实测落地：cjc 1.0.5 JSON 诊断含稳定 DiagKind 字段，作为错误码启用）：
 *   ① DiagKind 命中 ["诊断码"] 表 ──────────────→ 模板 + 教学提示 + 修复示例
 *   ② message/content 命中 ["消息翻译"] 表（精确 → 最长前缀 → ~ 后缀）
 *                                              → 模板（{q0}/{q1} 从动态段引号内容捕获）
 *                                              + 动态残段拼接
 *   ③ 均未命中 ─────────────────────────────→ 回退原文（仅类型名本地化，§7.3）
 *
 * 匹配约束（坑 ②/⑦）：前缀/后缀匹配禁用 std.regex（仅 ASCII），用
 * String.startsWith/endsWith 扫描键集合取最长命中；消息表键不得含英文反向修正。
 *
 * 1.0 适配：String.indexOf 返回 ?Int64（字节偏移）；HashMap 无 put 用 add。
 */

/** 翻译结果：主消息 + 详情 + 教学提示 + 修复示例 + 备注行。 */
public class DiagOut {
    public var mainText: String
    public var detail: String
    public var tip: String
    public var fix: String
    public var notes: ArrayList<String>

    public init(mainText: String, detail: String, tip: String, fix: String, notes: ArrayList<String>) {
        this.mainText = mainText
        this.detail = detail
        this.tip = tip
        this.fix = fix
        this.notes = notes
    }
}

/** 消息匹配结果：命中的条目 + 完整消息（{q0}/{q1} 从完整消息提取引号对，
 * 避免前缀截断把闭引号当开引号）。 */
public class Match {
    public var entry: DiagEntry
    public var source: String

    public init(entry: DiagEntry, source: String) {
        this.entry = entry
        this.source = source
    }
}

/**
 * 翻译一条诊断。
 * @param kind    cjc JSON 的 DiagKind 字段（稳定错误码，可空）
 * @param message 主消息（"mismatched types"）
 * @param content MainHint.Content（"expected 'Int64', found 'Struct-String'"）
 * @param notes   Notes/Helps 消息列表（本地化后展示）
 */
public func translateDiag(lang: LangPack, map: TypeMap, kind: String, message: String,
                          content: String, notes: ArrayList<String>): DiagOut {
    let noteLines = ArrayList<String>()
    for (nm in notes) {
        if (!nm.isEmpty()) {
            noteLines.add(localizeText(nm, map))
        }
    }
    // ① DiagKind 错误码表（第一优先级）
    let ke = lang.diagKinds.get(kind)
    match (ke) {
        case None => ()
        case Some(e) =>
            var mainText = e.template
            if (mainText.isEmpty()) {
                mainText = localizeText(message, map)
            } else {
                // 模板填充后同样做类型本地化（{q0} 引号内容如 main/Int64 → 主函数/整数），
                // 与消息表路径、回退路径行为一致（生产级一致性）
                mainText = localizeText(fillQuotes(mainText, message), map)
            }
            var detail = content
            // ② content 消息表（精确/最长前缀/~后缀）
            let cm = matchMessage(lang.msgEntries, content)
            match (cm) {
                case None =>
                    // §16.5：content 未命中消息表 → 记录诊断日志（社区共建闭环）
                    logMiss(content, "")
                    detail = localizeText(detail, map)
                case Some(cmEntry) => detail = renderEntry(cmEntry, map)
            }
            return DiagOut(mainText, detail, e.tip, e.fix, noteLines)
    }
    // ② message 消息表
    let mm = matchMessage(lang.msgEntries, message)
    match (mm) {
        case None => ()
        case Some(mEntry) =>
            return DiagOut(renderEntry(mEntry, map), localizeText(content, map),
                           mEntry.entry.tip, mEntry.entry.fix, noteLines)
    }
    // ③ 回退：原文 + 类型本地化（§16.5：未命中 → 记录诊断日志供 --missing 生成清单）
    logMiss(message, content)
    return DiagOut(localizeText(message, map), localizeText(content, map), "", "", noteLines)
}

/**
 * §16.5 错误字典自生成（社区共建闭环）：未命中消息表的消息原文
 * 追加写入 ~/.zhc/diag-log/diag.log（每行 消息原文<TAB>content），
 * 供 `zhc mapping check --missing` 聚合生成待翻译清单。
 * 日志失败不影响主流程（try 包裹）。
 */
public func logMiss(message: String, content: String) {
    if (message.isEmpty() && content.isEmpty()) {
        return
    }
    try {
        let home = getVariable("HOME")
        if (home == None || home.getOrThrow().isEmpty()) {
            return
        }
        let logDir = "${home.getOrThrow()}/.zhc/diag-log"
        if (!exists(Path(logDir))) {
            Directory.create(Path(logDir))
        }
        let logPath = "${logDir}/diag.log"
        var existing = ""
        if (exists(Path(logPath))) {
            existing = readTextFile(logPath)
        }
        if (!existing.isEmpty() && !existing.endsWith("\n")) {
            existing += "\n"
        }
        File.writeTo(logPath, (existing + message + "\t" + content + "\n").toArray())
    } catch (e: Exception) {
        ()   // 日志失败静默
    }
}

/** 渲染命中条目：模板填充 {q0}/{q1}（完整消息引号对按序捕获）。
 * 模板含占位符时不拼动态残段（占位符已承载动态信息）；无占位符时
 * 剔除引号对后的剩余文本拼在模板后。 */
public func renderEntry(m: Match, map: TypeMap): String {
    var out = fillQuotes(m.entry.template, m.source)
    if (!m.entry.template.contains("{q0}")) {
        let rest = stripQuoted(m.source)
        if (!rest.isEmpty()) {
            out = "${out} ${rest}"
        }
    }
    return localizeText(out, map)
}

/**
 * 消息表匹配（精确 → 最长前缀 → ~ 后缀）。键遍历排序保证最长优先且
 * 等长时结果确定（§6.3 确定性要求）。
 */
public func matchMessage(entries: HashMap<String, DiagEntry>, msg: String): ?Match {
    if (msg.isEmpty()) {
        return None
    }
    let keys = ArrayList<String>()
    for (k in entries.keys()) {
        keys.add(k)
    }
    sort(keys)
    // ① 精确
    let exact = entries.get(msg)
    match (exact) {
        case None => ()
        case Some(e) =>
            return Match(e, msg)
    }
    // ② 最长前缀（键不含 ~ 前缀）
    var bestKey = ""
    var hasBest = false
    for (k in keys) {
        if (k.startsWith("~")) {
            continue
        }
        if (k.size > bestKey.size && msg.startsWith(k)) {
            bestKey = k
            hasBest = true
        }
    }
    if (hasBest) {
        return Match(entries.get(bestKey).getOrThrow(), msg)
    }
    // ③ 最长后缀（键以 ~ 开头，锚定消息尾部）
    var bestSuf = ""
    var hasSuf = false
    for (k in keys) {
        if (!k.startsWith("~")) {
            continue
        }
        let suf = k[1..k.size]
        if (suf.size > bestSuf.size && msg.endsWith(suf)) {
            bestSuf = suf
            hasSuf = true
        }
    }
    if (hasSuf) {
        return Match(entries.get("~${bestSuf}").getOrThrow(), msg)
    }
    return None
}

/**
 * 模板占位符填充：{q0}/{q1}… 按序取 source 中引号对内容（单引号/反引号
 * 统一按出现顺序捕获；实测 cjc 消息以单引号承载动态值）。
 * 占位符缺少对应值时填空串。占位符替换不做类型本地化（模板自身语义完整）。
 * 另支持 {raw}：替换为 source 全文（全集错误码自动条目的原文兜底，§13.1 第 45 条）。
 */
public func fillQuotes(template: String, source: String): String {
    // {raw}：官方消息全文透传（先替换，避免与 {q0} 循环冲突）
    var t = template
    while (true) {
        let ra = t.indexOf("{raw}")
        match (ra) {
            case None => break
            case Some(ri) =>
                t = "${t[0..ri]}${source}${t[ri + 5..t.size]}"
        }
    }
    let quotes = extractQuoted(source)
    var out = t
    var qi: Int64 = 0
    while (true) {
        let ph = "{q${qi}}"
        let at = out.indexOf(ph)
        match (at) {
            case None => break
            case Some(ai) =>
                let v = if (qi < quotes.size) { quotes[qi] } else { "" }
                out = "${out[0..ai]}${v}${out[ai + ph.size..out.size]}"
                qi += 1
        }
    }
    return out
}

/** 按出现顺序提取文本中的引号对内容（'...' 与 `...`，字节偏移）。
 * 注意（1.0 实测）：String 下标返回 UInt8 字节，不能直接取字符参与插值，
 * 配对引号通过 sq/bq 与 next 的关系判断（next 等于 sq 即单引号更早）。 */
public func extractQuoted(text: String): ArrayList<String> {
    let out = ArrayList<String>()
    var pos: Int64 = 0
    let n = text.size
    while (pos < n) {
        let sq = text.indexOf("'", pos)
        let bq = text.indexOf("`", pos)
        var next: ?Int64 = None
        if (sq != None && bq != None) {
            next = if (sq.getOrThrow() < bq.getOrThrow()) { sq } else { bq }
        } else if (sq != None) {
            next = sq
        } else if (bq != None) {
            next = bq
        }
        match (next) {
            case None => pos = n
            case Some(qi) =>
                let isSingle = (sq != None && qi == sq.getOrThrow())
                let close = if (isSingle) { text.indexOf("'", qi + 1) } else { text.indexOf("`", qi + 1) }
                match (close) {
                    case None => pos = n
                    case Some(ci) =>
                        out.add(text[qi + 1..ci])
                        pos = ci + 1
                }
        }
    }
    return out
}

/** 剔除文本中所有引号对及其内容，返回剩余文本（trim 后）。 */
public func stripQuoted(text: String): String {
    var sb = ""
    var pos: Int64 = 0
    let n = text.size
    while (pos < n) {
        let sq = text.indexOf("'", pos)
        let bq = text.indexOf("`", pos)
        var next: ?Int64 = None
        if (sq != None && bq != None) {
            next = if (sq.getOrThrow() < bq.getOrThrow()) { sq } else { bq }
        } else if (sq != None) {
            next = sq
        } else if (bq != None) {
            next = bq
        }
        match (next) {
            case None =>
                sb = "${sb}${text[pos..n]}"
                pos = n
            case Some(qi) =>
                sb = "${sb}${text[pos..qi]}"
                let isSingle = (sq != None && qi == sq.getOrThrow())
                let close = if (isSingle) { text.indexOf("'", qi + 1) } else { text.indexOf("`", qi + 1) }
                match (close) {
                    case None =>
                        sb = "${sb}${text[qi..n]}"
                        pos = n
                    case Some(ci) =>
                        pos = ci + 1
                }
        }
    }
    return sb.trimAscii()
}
