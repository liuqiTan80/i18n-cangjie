package zhc

import std.collection.*

/**
 * 类型名本地化（设计 §7.3）：把官方诊断中的类型名译为方言。
 *
 * 处理链（对单个类型名，按序）：
 *   1. 可空标记：`?` 前缀原样保留（`?整数`）；
 *   2. 种类前缀：Struct-/Class-/Interface-/Enum-/EnumCase- 译为母语概念
 *      （§16.3 不剥离：值类型/引用类型的语义教学点），如 `结构体-字符串`；
 *   3. 泛型递归：`<...>` 内参数按顶层逗号拆分递归本地化
 *      （`Tuple<Int64, Int64>` → `元组<整数, 整数>`）；
 *   4. 路径段三段式：整名查类型表 → 从长到短试模块路径前缀完整匹配
 *      → 中间段单段映射；未知段原样透传（不崩溃）。
 *
 * 反向表构建（reverse.cj 思路的独立实现）：aliases/keywords/macros 反转
 * （官方 → 母语，首个命中）+ modulePaths 反转（模块路径单独成表）。
 * 过滤纯 ASCII 键的源条目（坑 ② 防御：英文键反向修正条目不参与，
 * 防止官方英文词在诊断里被误当方言词翻译）。
 *
 * 1.0 适配：String 无 substring，用字节切片；索引为字节偏移（ASCII 前缀安全）。
 */

/** 类型本地化反向表：types = 官方类型名 → 母语；modules = 官方路径 → 母语。 */
public class TypeMap {
    public var types: HashMap<String, String>
    public var modules: HashMap<String, String>

    public init(types: HashMap<String, String>, modules: HashMap<String, String>) {
        this.types = types
        this.modules = modules
    }
}

/** 字符串是否纯 ASCII（逐 rune 判断；ASCII 码点 ≤ '~'，空串视为是）。 */
public func isAscii(s: String): Bool {
    for (r in s.toRuneArray()) {
        if (r > r'~') {
            return false
        }
    }
    return true
}

/** 构建类型本地化反向表。键为纯 ASCII 的源条目跳过（坑 ② 防御）。 */
public func buildTypeMap(keywords: HashMap<String, String>, macros: HashMap<String, String>,
                         aliases: HashMap<String, String>,
                         modulePaths: HashMap<String, String>): TypeMap {
    let types = HashMap<String, String>()
    let modules = HashMap<String, String>()
    // 别名表 → 官方类型名 → 母语（首个命中，不覆盖）
    for (k in aliases.keys()) {
        if (isAscii(k)) {
            continue
        }
        let v = aliases.get(k).getOrThrow()
        if (!types.contains(v)) {
            types.add(v, k)
        }
    }
    for (k in keywords.keys()) {
        if (isAscii(k)) {
            continue
        }
        let v = keywords.get(k).getOrThrow()
        if (!types.contains(v)) {
            types.add(v, k)
        }
    }
    for (k in macros.keys()) {
        if (isAscii(k)) {
            continue
        }
        let v = macros.get(k).getOrThrow()
        if (!types.contains(v)) {
            types.add(v, k)
        }
    }
    for (k in modulePaths.keys()) {
        if (isAscii(k)) {
            continue
        }
        let v = modulePaths.get(k).getOrThrow()
        if (!modules.contains(v)) {
            modules.add(v, k)
        }
    }
    return TypeMap(types, modules)
}

/** 种类前缀 → 母语前缀（§16.3：不剥离，保留值/引用语义教学点）。 */
private func kindPrefix(name: String): ?(String, String) {
    if (name.startsWith("Struct-")) {
        return ("结构体-", name["Struct-".size..name.size])
    }
    if (name.startsWith("Class-")) {
        return ("类-", name["Class-".size..name.size])
    }
    if (name.startsWith("Interface-")) {
        return ("接口-", name["Interface-".size..name.size])
    }
    if (name.startsWith("Enum-")) {
        return ("枚举-", name["Enum-".size..name.size])
    }
    if (name.startsWith("EnumCase-")) {
        return ("枚举情况-", name["EnumCase-".size..name.size])
    }
    return None
}

/**
 * 本地化单个类型名。未知类型/无法解析时原样返回（§7.3 第 5 条回退）。
 */
public func localizeType(name: String, map: TypeMap): String {
    // ① 可空标记：? 前缀（可能多个）原样保留
    var nullable = ""
    var body = name
    while (body.startsWith("?")) {
        nullable = "${nullable}?"
        body = body[1..body.size]
    }
    if (body.isEmpty()) {
        return name
    }
    // ② 种类前缀
    let kp = kindPrefix(body)
    match (kp) {
        case None => ()
        case Some((dialectPre, rest)) =>
            return "${nullable}${dialectPre}${localizeType(rest, map)}"
    }
    // ②.5 参数列表括号包裹（如 `(Int64)` / `(Int64, String)`）：剥括号后
    // 按顶层逗号拆分逐个本地化（嵌套泛型内逗号不计），再还原括号
    if (body.startsWith("(") && body.endsWith(")") && body.size > 2) {
        let inner = body[1..body.size - 1]
        var out = "("
        let parts = splitTopLevel(inner)
        for (i in 0..parts.size) {
            if (i > 0) {
                out = "${out}, "
            }
            out = "${out}${localizeType(parts[i].trimAscii(), map)}"
        }
        return "${nullable}${out})"
    }
    // ③ 泛型：< 与匹配的 > 之间递归；无匹配 > 按普通名
    let ltOpt = body.indexOf("<")
    if (ltOpt != None) {
        let lt = ltOpt.getOrThrow()
        let gt = matchAngle(body, lt)
        if (gt != None) {
            let outer = localizeSimpleName(body[0..lt], map)
            let inner = body[lt + 1..gt.getOrThrow()]
            return "${nullable}${outer}<${localizeGenericArgs(inner, map)}>"
        }
    }
    return "${nullable}${localizeSimpleName(body, map)}"
}

/** 找与位置 pos 处 `<` 匹配的 `>` 字节偏移；无返回 None（嵌套 < 深度计数）。 */
private func matchAngle(s: String, pos: Int64): ?Int64 {
    let runes = s.toRuneArray()
    var depth: Int64 = 0
    var i = pos
    while (i < runes.size) {
        let r = runes[i]
        if (r == r'<') {
            depth += 1
        } else if (r == r'>') {
            depth -= 1
            if (depth == 0) {
                return i
            }
        }
        i += 1
    }
    return None
}

/** 泛型实参列表：按顶层逗号拆分（深度计数），逐项递归本地化。 */
private func localizeGenericArgs(inner: String, map: TypeMap): String {
    let parts = splitTopLevel(inner)
    var out = ""
    var first = true
    for (p in parts) {
        out = if (first) { localizeType(p.trimAscii(), map) } else { "${out}, ${localizeType(p.trimAscii(), map)}" }
        first = false
    }
    return out
}

/** 按顶层逗号（深度 0 处）拆分字符串，返回段列表（不去空白）。 */
public func splitTopLevel(s: String): ArrayList<String> {
    let parts = ArrayList<String>()
    let runes = s.toRuneArray()
    var depth: Int64 = 0
    var start = 0
    var i = 0
    while (i < runes.size) {
        let r = runes[i]
        if (r == r'<' || r == r'{' || r == r'(' || r == r'[') {
            depth += 1
        } else if (r == r'>' || r == r'}' || r == r')' || r == r']') {
            depth -= 1
        } else if (r == r',' && depth == 0) {
            parts.add(s[start..i])
            start = i + 1
        }
        i += 1
    }
    parts.add(s[start..s.size])
    return parts
}

/**
 * ④ 路径段三段式（无泛型的完整名）：
 *   整名查类型表 → 从长到短试模块路径前缀 → 中间段单段映射 → 原样回退。
 */
private func localizeSimpleName(name: String, map: TypeMap): String {
    let exact = map.types.get(name)
    if (exact != None) {
        return exact.getOrThrow()
    }
    if (!name.contains(".")) {
        // 无点单段：模块单段 + 类型表都试过，未命中原样
        let m = map.modules.get(name)
        if (m != None) {
            return m.getOrThrow()
        }
        return name
    }
    // 路径段：按 '.' 切分（Rune 数组遍历，字节偏移切回字符串）
    let segments = ArrayList<String>()
    let runes = name.toRuneArray()
    var segStart = 0
    var i = 0
    while (i < runes.size) {
        if (runes[i] == r'.') {
            segments.add(name[segStart..i])
            segStart = i + 1
        }
        i += 1
    }
    segments.add(name[segStart..name.size])
    // 从长到短试模块路径前缀完整匹配
    var best = name
    var matchedSegs: Int64 = 0
    var n = segments.size
    while (n >= 1) {
        var joined = ""
        var first = true
        var k = 0
        while (k < n) {
            joined = if (first) { segments[k] } else { "${joined}.${segments[k]}" }
            first = false
            k += 1
        }
        let m = map.modules.get(joined)
        if (m != None) {
            matchedSegs = n
            best = m.getOrThrow()
            break
        }
        n -= 1
    }
    // 剩余段逐段映射（类型表优先，其次模块单段，未命中原样）
    var rest = ""
    var k2 = matchedSegs
    while (k2 < segments.size) {
        let seg = segments[k2]
        let t = map.types.get(seg)
        var mapped = seg
        if (t != None) {
            mapped = t.getOrThrow()
        } else {
            let m2 = map.modules.get(seg)
            if (m2 != None) {
                mapped = m2.getOrThrow()
            }
        }
        rest = if (rest.isEmpty()) { mapped } else { "${rest}.${mapped}" }
        k2 += 1
    }
    if (matchedSegs == 0 && rest == name) {
        return name
    }
    return if (rest.isEmpty()) { best } else { "${best}.${rest}" }
}

/**
 * 文本级本地化：把文本中单引号/反引号对的内容逐个尝试类型本地化，
 * 内容变化才替换；普通短语/变量名不命中则原样保留。诊断消息里类型
 * 均带引号（`'Int64'`、`` `Struct-String` ``），未命中即透传，安全。
 */
public func localizeText(text: String, map: TypeMap): String {
    var sb = ""
    var pos: Int64 = 0
    let n = text.size
    while (pos < n) {
        // 找下一个引号（' 或 `），String.indexOf 返回字节偏移
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
                sb = "${sb}${text[pos..qi + 1]}"
                let isSingle = (sq != None && qi == sq.getOrThrow())
                let close = if (isSingle) { text.indexOf("'", qi + 1) } else { text.indexOf("`", qi + 1) }
                match (close) {
                    case None =>
                        sb = "${sb}${text[pos..n]}"
                        pos = n
                    case Some(ci) =>
                        let inner = text[qi + 1..ci]
                        let localized = localizeType(inner, map)
                        if (localized != inner) {
                            sb = "${sb}${localized}"
                        } else {
                            sb = "${sb}${inner}"
                        }
                        sb = if (isSingle) { "${sb}'" } else { "${sb}`" }
                        pos = ci + 1
                }
        }
    }
    return sb
}
