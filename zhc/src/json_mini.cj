package zhc

import std.collection.*

/**
 * 极简 JSON 工具集（LSP 代理专用，阶段 4）。
 *
 * 仓颉 1.0 标准库无 std.json（模块清单实测），且 LSP 帧为紧凑单行 JSON、
 * 值可能含 \n 等转义（didOpen 的 text 字段），阶段 3 的行级 extractField
 * （仅去 \" 转义）不适用——这里提供完整转义处理的提取与构造原语：
 *   - extractJsonStr / extractJsonNum：按键取值（任意嵌套深度，取首个）
 *   - splitJsonArray：括号配对切分 JSON 数组顶层元素
 *   - escapeJson / jsonQuote：JSON 字符串转义与封装
 *
 * 1.0 适配：全部基于 Rune 数组操作（中文安全）；\uXXXX 转义还原为码点
 * 拼接（String(Rune) 构造单字符）。
 */

/** 从 JSON 文本中找 `"key"` 后跟随的 JSON 字符串值（完整转义处理）。
 * 返回解码后的字符串；键不存在或值非字符串返回 None。 */
public func extractJsonStr(text: String, key: String): ?String {
    let runes = text.toRuneArray()
    let keyRunes = "\"${key}\"".toRuneArray()
    var i = findKey(runes, keyRunes)
    if (i < 0) {
        return None
    }
    var j = i + keyRunes.size
    while (j < runes.size && (runes[j] == r' ' || runes[j] == r'\t')) {
        j += 1
    }
    if (j >= runes.size || runes[j] != r':') {
        return None
    }
    j += 1
    while (j < runes.size && (runes[j] == r' ' || runes[j] == r'\t')) {
        j += 1
    }
    if (j >= runes.size || runes[j] != r'"') {
        return None
    }
    return parseJsonString(runes, j + 1)
}

/** 从 JSON 文本中找 `"key"` 后跟随的 JSON 数字值（含负数）。
 * 返回数字原文；不存在或非数字返回 None。 */
public func extractJsonNum(text: String, key: String): ?String {
    let runes = text.toRuneArray()
    let keyRunes = "\"${key}\"".toRuneArray()
    var i = findKey(runes, keyRunes)
    if (i < 0) {
        return None
    }
    var j = i + keyRunes.size
    while (j < runes.size && (runes[j] == r' ' || runes[j] == r'\t')) {
        j += 1
    }
    if (j >= runes.size || runes[j] != r':') {
        return None
    }
    j += 1
    while (j < runes.size && (runes[j] == r' ' || runes[j] == r'\t')) {
        j += 1
    }
    var sb = ""
    if (j < runes.size && runes[j] == r'-') {
        sb = "${sb}-"
        j += 1
    }
    var any = false
    while (j < runes.size && runes[j] >= r'0' && runes[j] <= r'9') {
        sb = "${sb}${runes[j]}"
        j += 1
        any = true
    }
    if (!any) {
        return None
    }
    return sb
}

/**
 * 切分 JSON 数组的顶层元素（输入从 `[` 开始）：括号配对（引号内不计）、
 * 顶层逗号分界。返回各元素原文（不含外层括号与分隔逗号，trim 后）。
 * 无法配对或未以 `[` 开头时返回空列表。
 */
public func splitJsonArray(text: String): ArrayList<String> {
    let out = ArrayList<String>()
    let runes = text.toRuneArray()
    if (runes.size == 0 || runes[0] != r'[') {
        return out
    }
    var depth: Int64 = 0
    var inStr = false
    var elemStart: Int64 = -1
    var i: Int64 = 0
    while (i < runes.size) {
        let c = runes[i]
        if (inStr) {
            if (c == r'\\') {
                i += 2
                continue
            }
            if (c == r'"') {
                inStr = false
            }
        } else {
            if (c == r'"') {
                inStr = true
            } else if (c == r'{' || c == r'[') {
                depth += 1
                if (elemStart < 0) {
                    elemStart = i
                }
            } else if (c == r'}' || c == r']') {
                depth -= 1
                if (depth == 0) {
                    // 数组闭合（元素可能以嵌套对象结束）
                    if (elemStart >= 0) {
                        out.add(String(runes[elemStart..i + 1]).trimAscii())
                    }
                    return out
                }
            } else if (c == r',' && depth == 1) {
                if (elemStart >= 0) {
                    out.add(String(runes[elemStart..i]).trimAscii())
                }
                elemStart = -1
            } else if (elemStart < 0 && c != r' ' && c != r'\t' && c != r'\n' && c != r'\r') {
                elemStart = i
            }
        }
        i += 1
    }
    return out
}

/* ===== §16.7：通用 JSON 值解析器（语言包 JSON 编码专用） ===== */

/** JSON 值节点：kind 0=对象 1=字符串 2=数字 3=布尔 4=null 5=数组。
 * end 为解析结束的 Rune 下标（含最后字符），供父节点续扫。 */
public class JsonNode {
    public var kind: Int64
    public var end: Int64
    public var obj: HashMap<String, JsonNode>
    public var str: String
    public var arr: ArrayList<JsonNode>

    public init(kind: Int64, end: Int64, obj: HashMap<String, JsonNode>,
                str: String, arr: ArrayList<JsonNode>) {
        this.kind = kind
        this.end = end
        this.obj = obj
        this.str = str
        this.arr = arr
    }
}

/** 解析完整 JSON 值；输入非合法 JSON 值返回 None。 */
public func parseJsonValue(text: String): ?JsonNode {
    let runes = text.toRuneArray()
    if (runes.size == 0) {
        return None
    }
    return parseJsonNode(runes, 0)
}

/** 递归下降解析（对象/字符串/数字/布尔/null/数组）。 */
private func parseJsonNode(runes: Array<Rune>, start: Int64): ?JsonNode {
    var i = start
    while (i < runes.size && isJsonWs(runes[i])) {
        i += 1
    }
    if (i >= runes.size) {
        return None
    }
    let c = runes[i]
    if (c == r'{') {
        let obj = HashMap<String, JsonNode>()
        var j = i + 1
        while (true) {
            while (j < runes.size && isJsonWs(runes[j])) {
                j += 1
            }
            if (j >= runes.size) {
                return None
            }
            if (runes[j] == r'}') {
                return JsonNode(0, j, obj, "", ArrayList<JsonNode>())
            }
            if (runes[j] != r'"') {
                return None
            }
            let keyOpt = parseJsonString(runes, j + 1)
            if (keyOpt == None) {
                return None
            }
            let key = keyOpt.getOrThrow()
            let keyEnd = jsonStringEnd(runes, j)
            if (keyEnd < 0) {
                return None
            }
            j = keyEnd + 1
            while (j < runes.size && isJsonWs(runes[j])) {
                j += 1
            }
            if (j >= runes.size || runes[j] != r':') {
                return None
            }
            j += 1
            match (parseJsonNode(runes, j)) {
                case None => return None
                case Some(v) =>
                    obj.add(key, v)
                    j = v.end + 1
            }
            while (j < runes.size && isJsonWs(runes[j])) {
                j += 1
            }
            if (j < runes.size && runes[j] == r',') {
                j += 1
                continue
            }
            if (j < runes.size && runes[j] == r'}') {
                return JsonNode(0, j, obj, "", ArrayList<JsonNode>())
            }
            return None
        }
    }
    if (c == r'"') {
        let sOpt = parseJsonString(runes, i + 1)
        if (sOpt == None) {
            return None
        }
        let end = jsonStringEnd(runes, i)
        if (end < 0) {
            return None
        }
        return JsonNode(1, end, HashMap<String, JsonNode>(), sOpt.getOrThrow(), ArrayList<JsonNode>())
    }
    if (c == r'[') {
        let arr = ArrayList<JsonNode>()
        var j = i + 1
        while (true) {
            while (j < runes.size && isJsonWs(runes[j])) {
                j += 1
            }
            if (j >= runes.size) {
                return None
            }
            if (runes[j] == r']') {
                return JsonNode(5, j, HashMap<String, JsonNode>(), "", arr)
            }
            match (parseJsonNode(runes, j)) {
                case None => return None
                case Some(v) =>
                    arr.add(v)
                    j = v.end + 1
            }
            while (j < runes.size && isJsonWs(runes[j])) {
                j += 1
            }
            if (j < runes.size && runes[j] == r',') {
                j += 1
                continue
            }
            if (j < runes.size && runes[j] == r']') {
                return JsonNode(5, j, HashMap<String, JsonNode>(), "", arr)
            }
            return None
        }
    }
    // 数字 / true / false / null
    var j = i
    while (j < runes.size && !isJsonWs(runes[j]) &&
           runes[j] != r',' && runes[j] != r'}' && runes[j] != r']') {
        j += 1
    }
    if (j == i) {
        return None
    }
    let word = String(runes[i..j])
    if (word == "true" || word == "false") {
        return JsonNode(3, j - 1, HashMap<String, JsonNode>(), word, ArrayList<JsonNode>())
    }
    if (word == "null") {
        return JsonNode(4, j - 1, HashMap<String, JsonNode>(), "", ArrayList<JsonNode>())
    }
    return JsonNode(2, j - 1, HashMap<String, JsonNode>(), word, ArrayList<JsonNode>())
}

private func isJsonWs(c: Rune): Bool {
    return c == r' ' || c == r'\t' || c == r'\n' || c == r'\r'
}

/** 给定开引号位置，返回闭引号 Rune 下标（跳过 \ 转义）；未闭合返回 -1。 */
private func jsonStringEnd(runes: Array<Rune>, qpos: Int64): Int64 {
    var i = qpos + 1
    while (i < runes.size) {
        if (runes[i] == r'\\') {
            i += 2
            continue
        }
        if (runes[i] == r'"') {
            return i
        }
        i += 1
    }
    return -1
}

/** JSON 字符串转义（" \ 与常用控制字符；其余字符原样）。 */
public func escapeJson(s: String): String {
    var sb = ""
    for (r in s.toRuneArray()) {
        if (r == r'"') {
            sb = "${sb}\\\""
        } else if (r == r'\\') {
            sb = "${sb}\\\\"
        } else if (r == r'\n') {
            sb = "${sb}\\n"
        } else if (r == r'\r') {
            sb = "${sb}\\r"
        } else if (r == r'\t') {
            sb = "${sb}\\t"
        } else if (r < r' ') {
            // 其他控制字符转 \uXXXX
            let code = u4hex(r)
            sb = "${sb}\\u${code}"
        } else {
            sb = "${sb}${r}"
        }
    }
    return sb
}

/** JSON 字符串值封装（含引号与转义）。 */
public func jsonQuote(s: String): String {
    return "\"${escapeJson(s)}\""
}

/** 在 runes 中找键 `"key"`（含引号）首次出现的 Rune 偏移；找不到返回 -1。 */
private func findKey(runes: Array<Rune>, keyRunes: Array<Rune>): Int64 {
    let klen = keyRunes.size
    if (klen == 0 || runes.size < klen) {
        return -1
    }
    var i: Int64 = 0
    while (i + klen <= runes.size) {
        var matched = true
        var k = 0
        while (k < klen) {
            if (runes[i + k] != keyRunes[k]) {
                matched = false
                break
            }
            k += 1
        }
        if (matched) {
            return i
        }
        i += 1
    }
    return -1
}

/** 解析 JSON 字符串值（runes 起点为开引号后一位），完整转义处理；
 * 返回解码后的字符串；未闭合返回 None。 */
private func parseJsonString(runes: Array<Rune>, start: Int64): ?String {
    var sb = ""
    var i = start
    while (i < runes.size) {
        let c = runes[i]
        if (c == r'"') {
            return sb
        } else if (c == r'\\') {
            if (i + 1 >= runes.size) {
                return None
            }
            let e = runes[i + 1]
            if (e == r'"') {
                sb = "${sb}\""
            } else if (e == r'\\') {
                sb = "${sb}\\"
            } else if (e == r'/') {
                sb = "${sb}/"
            } else if (e == r'b') {
                sb = "${sb}\b"
            } else if (e == r'f') {
                sb = "${sb}\u{0C}"
            } else if (e == r'n') {
                sb = "${sb}\n"
            } else if (e == r'r') {
                sb = "${sb}\r"
            } else if (e == r't') {
                sb = "${sb}\t"
            } else if (e == r'u') {
                // \uXXXX → 码点
                if (i + 5 >= runes.size) {
                    return None
                }
                var code: Int64 = 0
                var k = 0
                while (k < 4) {
                    let h = hexVal(runes[i + 2 + k])
                    if (h < 0) {
                        return None
                    }
                    code = code * 16 + h
                    k += 1
                }
                sb = "${sb}${Rune(code)}"
                i += 4
            } else {
                // 未知转义：原样保留反斜杠与字符（宽松）
                sb = "${sb}\\${e}"
            }
            i += 2
        } else {
            sb = "${sb}${c}"
            i += 1
        }
    }
    return None
}

/** 十六进制字符 → 数值；非十六进制返回 -1。 */
public func hexVal(r: Rune): Int64 {
    let v = runeValue(r)
    if (v >= 48 && v <= 57) {
        return v - 48
    }
    if (v >= 97 && v <= 102) {
        return v - 87
    }
    if (v >= 65 && v <= 70) {
        return v - 55
    }
    return -1
}

/** Rune 的码点值（无内置 toInt64，用字节构造辅助——Rune 与 Int64 互转
 * 通过 String 中转不可行，这里用比较法区间求和：仅用于控制字符判定）。 */
private func u4hex(r: Rune): String {
    let v = runeValue(r)
    var hex = ""
    var x = v
    var i = 0
    while (i < 4) {
        let d = x % 16
        let ch = if (d < 10) { Rune(48 + d) } else { Rune(87 + d) }
        hex = "${ch}${hex}"
        x = x / 16
        i += 1
    }
    return hex
}

/** Rune → Int64 码点（无 toInt64：经 String 中转，按 UTF-8 字节解析）。 */
private func runeValue(r: Rune): Int64 {
    let s = "${r}"
    let bytes = s.toArray()
    var v: Int64 = 0
    for (b in bytes) {
        v = v * 256 + Int64(b)
    }
    return v
}
