package zhc

import std.collection.*

/**
 * TOML 子集解析器（对应设计 §6 语言包数据规范）。
 *
 * 支持的语法（语言包专用子集）：
 *   - 节标题： [节名]
 *   - 键值对： "键" = "值"   （键值均为双引号字符串，值可含空格/转义 \n 等）
 *   - 注释：   # 开头整行（行内注释暂不支持）
 *   - 空行
 *
 * 不支持的语法（超出语言包需求，解析到即忽略并告警）：
 *   数组、内联表、多行字符串、裸键、布尔/数字字面量。
 *
 * 解析结果为 节名 → (键 → 值) 的两级表。
 * parseTomlNested：支持 `[a.b]` 两级嵌套节（errors.toml 的消息条目专用），
 * 返回 节名 → (子节名 → (键 → 值)) 的三级表。
 *
 * 1.0 适配记录（本机 cjc 1.0.5 实测）：
 *   - String 无 trim()/substring()，改用 trimAscii() 与字节切片 s[a..b]；
 *   - indexOf 返回 ?Int64（字节偏移），需解包 Option；
 *   - HashMap 写入用 add(key, value)（put/insert 均不存在）；
 *   - 单引号字面量 'x' 是 String，Rune 字面量是 r'x'。
 */

public class TomlParseError <: Exception {
    public init(message: String) {
        super(message)
    }
}

public func parseToml(text: String): HashMap<String, HashMap<String, String>> {
    let tables = HashMap<String, HashMap<String, String>>()
    var section = ""                      // 空串 = 顶层（语言包不使用顶层键值）
    let lines = text.split("\n")
    for (line in lines) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        if (trimmed.startsWith("#")) {
            continue
        }
        if (trimmed.startsWith("[")) {
            if (!trimmed.endsWith("]")) {
                throw TomlParseError("行格式错误（节标题未闭合）：${trimmed}")
            }
            // 字节切片剥括号；节名兼容两种写法：带引号（"声明"）与裸键（语言包）
            let rawSection = trimmed[1..trimmed.size - 1].trimAscii()
            if (rawSection.startsWith("\"")) {
                section = unquote(rawSection)
            } else {
                section = rawSection
            }
            if (section.isEmpty()) {
                throw TomlParseError("行格式错误（空节名）：${trimmed}")
            }
            if (!tables.contains(section)) {
                tables.add(section, HashMap<String, String>())
            }
            continue
        }
        let eqOpt = trimmed.indexOf("=")
        if (eqOpt == None) {
            throw TomlParseError("行格式错误（缺少 `=`）：${trimmed}")
        }
        let eqIndex = eqOpt.getOrThrow()              // 字节偏移，'=' 为单字节 ASCII
        // 键：语言包规范要求引号包裹（unquote）；cjpm.toml 等外部 TOML 允许裸键
        let keyRaw = trimmed[0..eqIndex].trimAscii()
        let key = if (keyRaw.startsWith("\"")) { unquote(keyRaw) } else { keyRaw }
        // 值：双引号字符串优先；内联表 { ... }（cjpm.toml 依赖/配置）存原始文本
        // （嵌套大括号配对计数，忽略字符串内 { }——配置场景足够）
        let valueRaw = trimmed[eqIndex + 1..trimmed.size].trimAscii()
        var value = ""
        if (valueRaw.startsWith("{")) {
            var depth: Int64 = 0
            var done = false
            for (c in valueRaw.toRuneArray()) {
                if (c == r'{') {
                    depth += 1
                } else if (c == r'}') {
                    depth -= 1
                    if (depth == 0) {
                        done = true
                        break
                    }
                }
            }
            if (!done) {
                throw TomlParseError("内联表未闭合：${valueRaw}")
            }
            value = valueRaw
        } else {
            // 行尾注释支持（TOML 规范，审计 E1 测试驱动）：双引号值闭合后的
            // `#`（trim 后）视为注释截断；闭合引号 = 行内最后一个 `"`（转义
            // 引号在值中部，最后引号必为闭合）。裸值不处理（unquote 自会拒绝）。
            var vRaw = valueRaw
            if (vRaw.startsWith("\"")) {
                let lastQ = vRaw.lastIndexOf("\"")
                if (lastQ != None && lastQ.getOrThrow() > 0) {
                    let after = vRaw[lastQ.getOrThrow() + 1..vRaw.size].trimAscii()
                    if (after.isEmpty() || after.startsWith("#")) {
                        vRaw = vRaw[0..lastQ.getOrThrow() + 1]
                    }
                }
            }
            value = unquote(vRaw)
        }
        if (section.isEmpty()) {
            throw TomlParseError("顶层键值对不支持（语言包要求分节）：${trimmed}")
        }
        let table = tables.get(section).getOrThrow()
        if (table.contains(key)) {
            throw TomlParseError("重复键：节 [${section}] 键 ${key}")
        }
        table.add(key, value)
    }
    return tables
}

/**
 * 三级表解析（errors.toml 专用）：节标题可为 `[a]` 或 `[a.b]`（两级嵌套）。
 * 结果：外层节 → 子节 → (键 → 值)。键值对必须在叶子节内；
 * `[a]` 声明后若直接跟键值对（a 同时是叶子），把 a 当作空子节名的叶子处理。
 */
public func parseTomlNested(text: String): HashMap<String, HashMap<String, HashMap<String, String>>> {
    let outer = HashMap<String, HashMap<String, HashMap<String, String>>>()
    var section = ""            // 当前外层节名
    var subsection = ""         // 当前子节名（空 = 键值直接属于外层节）
    let lines = text.split("\n")
    for (line in lines) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty() || trimmed.startsWith("#")) {
            continue
        }
        if (trimmed.startsWith("[")) {
            if (!trimmed.endsWith("]")) {
                throw TomlParseError("行格式错误（节标题未闭合）：${trimmed}")
            }
            let rawSection = trimmed[1..trimmed.size - 1].trimAscii()
            let dotOpt = rawSection.indexOf(".")
            if (dotOpt == None) {
                section = unquote(rawSection)
                subsection = ""
            } else {
                let dot = dotOpt.getOrThrow()
                section = unquote(rawSection[0..dot].trimAscii())
                subsection = unquote(rawSection[dot + 1..rawSection.size].trimAscii())
            }
            if (section.isEmpty()) {
                throw TomlParseError("行格式错误（空节名）：${trimmed}")
            }
            if (!outer.contains(section)) {
                outer.add(section, HashMap<String, HashMap<String, String>>())
            }
            if (!subsection.isEmpty() && !outer.get(section).getOrThrow().contains(subsection)) {
                outer.get(section).getOrThrow().add(subsection, HashMap<String, String>())
            }
            continue
        }
        let eqOpt = trimmed.indexOf("=")
        if (eqOpt == None) {
            throw TomlParseError("行格式错误（缺少 `=`）：${trimmed}")
        }
        let eqIndex = eqOpt.getOrThrow()
        let key = unquote(trimmed[0..eqIndex].trimAscii())
        let value = unquote(trimmed[eqIndex + 1..trimmed.size].trimAscii())
        if (section.isEmpty()) {
            throw TomlParseError("顶层键值对不支持（语言包要求分节）：${trimmed}")
        }
        let leafKey = if (subsection.isEmpty()) { "" } else { subsection }
        let table = outer.get(section).getOrThrow()
        let leaf = table.get(leafKey)
        match (leaf) {
            case None =>
                let fresh = HashMap<String, String>()
                fresh.add(key, value)
                table.add(leafKey, fresh)
            case Some(t) =>
                if (t.contains(key)) {
                    throw TomlParseError("重复键：节 [${section}] 键 ${key}")
                }
                t.add(key, value)
        }
    }
    return outer
}

/** 剥离双引号并处理 \\n 转义；非引号包裹的值视为错误（语言包规范强制引号）。 */
private func unquote(raw: String): String {
    let runes = raw.toRuneArray()         // Rune 数组：避免字节下标切坏中文
    if (runes.size < 2 || runes[0] != r'"' || runes[runes.size - 1] != r'"') {
        throw TomlParseError("值必须是双引号字符串：${raw}")
    }
    var sb = ""
    var i = 1
    let n = runes.size - 1
    while (i < n) {
        let ch = runes[i]
        if (ch == r'\\' && i + 1 < n) {
            let next = runes[i + 1]
            if (next == r'n') {
                sb = "${sb}\n"
                i += 2
            } else if (next == r't') {
                sb = "${sb}\t"
                i += 2
            } else if (next == r'"') {
                sb = "${sb}\""
                i += 2
            } else if (next == r'\\') {
                sb = "${sb}\\"
                i += 2
            } else {
                sb = "${sb}${next}"
                i += 2
            }
        } else {
            sb = "${sb}${ch}"
            i += 1
        }
    }
    return sb
}
