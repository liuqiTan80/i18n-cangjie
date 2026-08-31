package zhc

import std.collection.*

/**
 * import 语句态路径替换（对应设计 §5.2 module_path.cj）。
 *
 * 输入：词法转译后的文本（`导入` 已由关键字表替换为 `import`，§3.3 管线顺序）。
 * 状态机：遇 `import` token 进入语句态，遇 `;` 退出；语句态内：
 *   - `.` 分隔的路径段查 module_paths.toml（整段匹配优先：`标准集合` 不拆 `标准`+`集合`，
 *     多段路径从最长前缀试匹配）；
 *   - `{` `}` 之间的标识符是导入符号，查别名表（stdlib.toml 标识符节）；
 *   - `*`、`.`、`,`、`{` `}` 原样透传。
 * 语句外的一切 `.` 路径不碰（红线，§3.3）。
 *
 * 字符串/注释/反引号内容整体跳过（import 语句里理论上不出现，防御性处理）。
 */

public class ImportReplaceResult {
    public var text: String
    public var count: Int64
    public var map: ArrayList<MapEntry>   // 替换条目（输入文本 Rune 偏移，供源映射合并）

    public init(text: String, count: Int64, map: ArrayList<MapEntry>) {
        this.text = text
        this.count = count
        this.map = map
    }
}

/** 路径段匹配结果：命中则替换，否则原文输出。 */
private class SegMatch {
    public var ok: Bool
    public var mapped: String
    public var restSegs: ArrayList<String>

    public init(ok: Bool, mapped: String, restSegs: ArrayList<String>) {
        this.ok = ok
        this.mapped = mapped
        this.restSegs = restSegs
    }
}

public func replaceImportPaths(text: String, lang: LangPack): ImportReplaceResult {
    let runes = text.toRuneArray()
    let n = runes.size
    var sb = ""
    var count: Int64 = 0
    let map = ArrayList<MapEntry>()
    var inImport = false
    var inBraces = false
    var i: Int64 = 0

    while (i < n) {
        let ch = runes[i]
        if (ch == r'"' || ch == r'\'') {
            let (piece, next) = scanQuoted(runes, i, n, ch)
            sb = "${sb}${piece}"
            i = next
        } else if (ch == r'/' && i + 1 < n && runes[i + 1] == r'/') {
            let (piece, next) = scanLineComment(runes, i, n)
            sb = "${sb}${piece}"
            i = next
        } else if (ch == r'/' && i + 1 < n && runes[i + 1] == r'*') {
            let (piece, next) = scanBlockComment(runes, i, n)
            sb = "${sb}${piece}"
            i = next
        } else if (ch == r'`') {
            var j = i + 1
            while (j < n && runes[j] != r'`') {
                j += 1
            }
            sb = "${sb}${String(runes[i..if (j < n) { j + 1 } else { n }])}"
            i = if (j < n) { j + 1 } else { n }
        } else if (isIdentStart(ch)) {
            var j = i
            while (j < n && isIdentPart(runes[j])) {
                j += 1
            }
            let token = String(runes[i..j])
            if (!inImport) {
                sb = "${sb}${token}"
                if (token == "import") {
                    inImport = true
                }
                i = j
            } else if (inBraces) {
                // 导入符号列表：查别名表
                let mapped = lang.aliases.get(token)
                if (mapped == None) {
                    sb = "${sb}${token}"
                } else {
                    sb = "${sb}${mapped.getOrThrow()}"
                    count += 1
                    map.add(MapEntry(i, j - i, token, mapped.getOrThrow()))
                }
                i = j
            } else {
                // 路径段：收集 `标识符(.标识符)*` 序列，整段（最长前缀优先）匹配模块路径表
                let segs = ArrayList<String>()
                segs.add(token)
                var k = j
                while (k < n && runes[k] == r'.' && k + 1 < n && isIdentStart(runes[k + 1])) {
                    var m = k + 1
                    while (m < n && isIdentPart(runes[m])) {
                        m += 1
                    }
                    segs.add(String(runes[k + 1..m]))
                    k = m
                }
                let m = matchLongest(segs, lang.modulePaths)
                if (m.ok) {
                    var replaced = "${m.mapped}"
                    for (r in m.restSegs) {
                        replaced = "${replaced}.${r}"
                    }
                    sb = "${sb}${replaced}"
                    count += 1
                    map.add(MapEntry(i, k - i, String(runes[i..k]), replaced))
                } else {
                    // 匹配失败：原样输出（含点号），不做任何替换
                    sb = "${sb}${String(runes[i..k])}"
                }
                i = k
            }
        } else if (ch == r'{') {
            if (inImport) {
                inBraces = true
            }
            sb = "${sb}${ch}"
            i += 1
        } else if (ch == r'}') {
            if (inImport) {
                inBraces = false
            }
            sb = "${sb}${ch}"
            i += 1
        } else if (ch == r';' || ((ch == r'\n' || ch == r'\r') && !inBraces)) {
            // 分号或行尾（不在 import 符号列表内）结束 import 语句：
            // 方言 import 行无分号，靠行尾重置，避免后续代码误入路径段分支
            if (inImport) {
                inImport = false
                inBraces = false
            }
            sb = "${sb}${ch}"
            i += 1
        } else {
            sb = "${sb}${ch}"
            i += 1
        }
    }
    return ImportReplaceResult(sb, count, map)
}

/** 从最长前缀开始试匹配 modulePaths（`标准集合.fs` 先试整串，再试 `标准集合`）。 */
private func matchLongest(segs: ArrayList<String>, modulePaths: HashMap<String, String>): SegMatch {
    var k = segs.size
    while (k >= 1) {
        var cand = ""
        var idx: Int64 = 0
        while (idx < k) {
            if (idx > 0) {
                cand = "${cand}."
            }
            cand = "${cand}${segs[idx]}"
            idx += 1
        }
        let mapped = modulePaths.get(cand)
        if (mapped != None) {
            let rest = ArrayList<String>()
            var r = k
            while (r < segs.size) {
                rest.add(segs[r])
                r += 1
            }
            return SegMatch(true, mapped.getOrThrow(), rest)
        }
        k -= 1
    }
    return SegMatch(false, "", ArrayList<String>())
}
