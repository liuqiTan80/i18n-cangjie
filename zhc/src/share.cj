package zhc

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.process.*
import std.sort.*

/**
 * zhc share（设计 §18）：翻译资源共享 —— 第三方库方言映射的「按需下载 + 上传共享」。
 *
 * 两个核心场景：
 *   ① 按需下载（share list / search / fetch）：先取共享仓库的 index.json 元数据
 *      清单浏览/搜索，再只下载所需的那一个 crates/<语言>/<库名>.toml（非全量），
 *      下载后做完整性校验（校验和）+ 本地门禁（TOML 解析 / 键格式 / 撞词表），
 *      通过后装入语言包 crates/ 目录；
 *   ② 上传共享（share publish）：本地翻译好的映射 toml 先过同一套门禁，组装
 *      JSON（内容 + 元数据 + 校验和）后提交到共享仓库——base 为本地目录时直接
 *      落盘并幂等更新 index.json（读改写，同名同语言覆盖）；为 HTTP 端点时
 *      POST {base}/share-publish（配套服务端 tools/share_server.py，零依赖）；
 *      网络/服务端失败时降级导出 zhc-共享-<名>/ 提交包，指引走 libs/ 众包 PR 渠道。
 *
 * 共享源（base）解析顺序：--base 参数 > 环境变量 ZHC_SHARE_BASE >
 * ~/.zhc/share.toml [share] base > 默认官方仓库 libs/ 目录（GitCode raw 直链）。
 * base 既可以是本地目录（离线共享盘/团队 NAS），也可以是 http(s) 端点。
 *
 * 注册表布局（与 libs/ 众包平台同构，libs/index.json 即种子数据）：
 *   <base>/index.json                 {"版本":1,"库":[{名称/语言/描述/作者/键数/校验和/时间}]}
 *   <base>/crates/<语言>/<库名>.toml  键 = 母语名，值 = 官方名（libs/README.md 守则）
 *
 * 数据交互可靠性：
 *   - HTTP 传输复用 ai_client 通道结论（std.net 1.0 无 HTTP 客户端）：curl 优先、
 *     python3 urllib 降级，响应协议统一 <body>\n<http_code>；
 *   - 完整性校验用 hash64/hexOf（cache.cj 同款 64 位混合哈希，纯位运算无溢出，
 *     防传输损坏；非密码学强度）；
 *   - 名称净化（禁 / \ .. 空格）防路径穿越；index 读改写失败即中止（不覆盖坏文件）。
 */

/** 官方默认共享仓库（libs/ 众包平台目录，raw.gitcode.com 直链，main 分支）。
 * 注：GitCode raw 对匿名请求可能返回网页/403（登录态限制）——此时命令会给出
 * 明确诊断；团队与离线场景建议用 ZHC_SHARE_BASE 指向自建 share_server 或本地
 * 镜像目录，GitHub 镜像 raw（liuqiTan80/i18n-cangjie）亦可作共享源。 */
public let DEFAULT_SHARE_BASE = "https://raw.gitcode.com/tan80/zwCangjie/raw/main/libs"

/** 合法映射节名（与 scripts/check-libs.py 平台约定一致）。 */
public let SHARE_SECTIONS = ["标识符", "模块路径", "宏"]

/** 共享仓库条目元数据。 */
public class ShareEntry {
    public var name: String
    public var lang: String
    public var desc: String
    public var author: String
    public var keyCount: Int64
    public var checksum: String
    public var time: String

    public init(name: String, lang: String, desc: String, author: String,
                keyCount: Int64, checksum: String, time: String) {
        this.name = name
        this.lang = lang
        this.desc = desc
        this.author = author
        this.keyCount = keyCount
        this.checksum = checksum
        this.time = time
    }
}

// ==================== 入口与子命令 ====================

/** zhc share 子命令入口（main.cj case "share" 分发）。 */
public func cmdShare(args: Array<String>): Int64 {
    if (args.size < 2) {
        return shareUsage()
    }
    let sub = args[1]
    let rest = args[2..args.size]
    let baseOpt = extractShareOpt(rest, "--base")
    var base = resolveShareBase()
    if (baseOpt != None) {
        base = baseOpt.getOrThrow()
    }
    match (sub) {
        case "list" => return cmdShareList(base)
        case "search" =>
            if (rest.isEmpty()) {
                println(uiText("用法：zhc share search <关键词> [--base <目录或URL>]"))
                return 1
            }
            return cmdShareSearch(base, rest[0])
        case "fetch" => return cmdShareFetch(rest, base)
        case "publish" => return cmdSharePublish(rest, base)
        case "help" => return shareUsage()
        case _ =>
            println(uiTextF("未知子命令：share {0}", [sub]))
            return shareUsage()
    }
}

func shareUsage(): Int64 {
    println(uiText("用法：zhc share list | search <关键词> | fetch <库名> [选项] | publish <文件.toml> [选项]"))
    println(uiText("  翻译资源共享：按需下载所需映射（非全量），或把自译的第三方库映射上传共享仓库"))
    println(uiText("  fetch   [--lang <代码>] [--dir <目录>] [--force] [--base <目录或URL>]"))
    println(uiText("  publish [--name <库名>] [--lang <代码>] [--desc <描述>] [--author <作者>] [--base <目录或URL>]"))
    println(uiText("  共享源：ZHC_SHARE_BASE 或 ~/.zhc/share.toml [share] base（缺省官方 libs/ 目录）"))
    return 1
}

/** 从参数数组提取 <flag> <值>（返回值并从数组语义上忽略；不影响原数组）。 */
public func extractShareOpt(args: Array<String>, flag: String): ?String {
    var i: Int64 = 0
    while (i < args.size) {
        if (args[i] == flag && i + 1 < args.size) {
            return args[i + 1]
        }
        i += 1
    }
    return None
}

/** 共享源解析：环境变量 > ~/.zhc/share.toml [share] base > 默认官方地址。 */
public func resolveShareBase(): String {
    let env = getVariable("ZHC_SHARE_BASE")
    if (env != None && !env.getOrThrow().isEmpty()) {
        return env.getOrThrow()
    }
    let home = getVariable("HOME")
    if (home != None && !home.getOrThrow().isEmpty()) {
        let cfgPath = "${home.getOrThrow()}/.zhc/share.toml"
        if (exists(Path(cfgPath))) {
            try {
                let tables = parseToml(readTextFile(cfgPath))
                match (tables.get("share")) {
                    case None => ()
                    case Some(section) =>
                        let v = section.get("base")
                        if (v != None && !v.getOrThrow().isEmpty()) {
                            return v.getOrThrow()
                        }
                }
            } catch (e: Exception) {
                ()   // 配置损坏：回退默认
            }
        }
    }
    return DEFAULT_SHARE_BASE
}

/** base 是否本地目录（否则按 http(s) 端点处理）。 */
public func isLocalShareBase(base: String): Bool {
    return !base.startsWith("http://") && !base.startsWith("https://")
}

/** 拼接 base 与相对路径（容忍 base 尾随 /）。 */
public func shareJoinUrl(base: String, path: String): String {
    var b = base
    while (b.endsWith("/")) {
        b = b[0..b.size - 1]
    }
    return "${b}/${path}"
}

// ==================== 纯函数：校验/索引/JSON（可单测） ====================

/**
 * 共享名称净化：空、含 / \\ .. 或空白字符 → ""（拒绝）；其余返回原样。
 * 防 fetch/publish 的路径穿越与文件名歧义。
 */
public func sanitizeShareName(name: String): String {
    let t = name.trimAscii()
    if (t.isEmpty() || t.contains("/") || t.contains("\\") ||
        t.contains("..") || t.contains(" ") || t.contains("\t")) {
        return ""
    }
    return t
}

/**
 * 映射 toml 内容校验（fetch 安装前 / publish 提交前共用，check-libs 平台口径）：
 * TOML 可解析、节名合法、键值均带引号、文件内无重复键、标识符值 = 官方名格式。
 * 返回错误清单（空 = 通过）。
 */
public func validateMappingToml(text: String): ArrayList<String> {
    let errors = ArrayList<String>()
    // ① 文件内重复键（parseToml 用 HashMap 会静默合并，需按行扫描）
    let seen = HashMap<String, String>()
    var section = ""
    var lineNo: Int64 = 0
    for (raw in text.split("\n")) {
        lineNo += 1
        let line = raw.trimAscii()
        if (line.isEmpty() || line.startsWith("#")) {
            continue
        }
        if (line.startsWith("[") && line.endsWith("]")) {
            section = trimQuote(line[1..line.size - 1].trimAscii())
            if (!shareSectionOk(section)) {
                errors.add("第 ${lineNo} 行非法节名 [${section}]（允许：标识符/模块路径/宏）")
            }
            continue
        }
        let kv = parseShareKvLine(line)
        match (kv) {
            case None =>
                errors.add("第 ${lineNo} 行无法解析（键/值须引号包裹且无行内注释）：${snippet(line, 40)}")
            case Some(pair) =>
                if (section.isEmpty()) {
                    errors.add("第 ${lineNo} 行键值出现在节声明之前")
                } else if (seen.contains(pair[0])) {
                    errors.add("第 ${lineNo} 行重复键 \"${pair[0]}\"（首次见于 [${seen.get(pair[0]).getOrThrow()}] 节）")
                } else {
                    seen.add(pair[0], section)
                    if (pair[1].isEmpty()) {
                        errors.add("第 ${lineNo} 行键 \"${pair[0]}\" 的值为空")
                    } else if (section == "标识符" && !shareOfficialIdOk(pair[1])) {
                        errors.add("第 ${lineNo} 行键 \"${pair[0]}\" 的值非官方标识符：${pair[1]}")
                    }
                }
        }
    }
    // ② 整体可解析（行级扫描无错时才跑：parseToml 对重复键/节前键值会抛异常，
    // 与行级扫描重复计数；此处仅兜底罕见 TOML 语法问题）
    if (errors.isEmpty()) {
        try {
            parseToml(text)
        } catch (e: Exception) {
            errors.add("TOML 解析失败：${snippet(e.message, 80)}")
        }
    }
    return errors
}

/** 节名是否合法。 */
func shareSectionOk(section: String): Bool {
    for (s in SHARE_SECTIONS) {
        if (s == section) {
            return true
        }
    }
    return false
}

/** 解析一行 "k" = "v"（严格引号包裹）；不合法返回 None。Rune 扫描避免
 * indexOf(起,始下标) 重载（1.0 未在仓库内实测）。 */
func parseShareKvLine(line: String): ?Array<String> {
    let runes = line.toRuneArray()
    if (runes.size < 3 || runes[0] != r'"') {
        return None
    }
    var endK: Int64 = -1
    var i: Int64 = 1
    while (i < runes.size) {
        if (runes[i] == r'"') {
            endK = i
            break
        }
        i += 1
    }
    if (endK < 0) {
        return None
    }
    let k = String(runes[1..endK])
    var j = endK + 1
    while (j < runes.size && (runes[j] == r' ' || runes[j] == r'\t')) {
        j += 1
    }
    if (j >= runes.size || runes[j] != r'=') {
        return None
    }
    j += 1
    while (j < runes.size && (runes[j] == r' ' || runes[j] == r'\t')) {
        j += 1
    }
    if (j >= runes.size || runes[j] != r'"' ||
        runes[runes.size - 1] != r'"' || runes.size - j < 2) {
        return None
    }
    let v = String(runes[j + 1..runes.size - 1])
    return [k, v]
}

/** 官方标识符格式（值）：^[A-Za-z_][A-Za-z0-9_]*$ 或点分段模块路径。 */
func shareOfficialIdOk(v: String): Bool {
    if (v.isEmpty()) {
        return false
    }
    let runes = v.toRuneArray()
    for (i in 0..runes.size) {
        let c = runes[i]
        let isAlpha = (c >= r'a' && c <= r'z') || (c >= r'A' && c <= r'Z') || c == r'_'
        let isDigit = c >= r'0' && c <= r'9'
        if (i == 0) {
            if (!isAlpha) {
                return false
            }
        } else if (!isAlpha && !isDigit) {
            return false
        }
    }
    return true
}

/** 去除首尾成对引号（节名解析辅助）。 */
func trimQuote(s: String): String {
    if (s.size >= 2 && s.startsWith("\"") && s.endsWith("\"")) {
        return s[1..s.size - 1]
    }
    return s
}

/**
 * 解析 index.json → 条目清单（json_mini 完整 JSON 解析；缺 "库" 节或结构
 * 不合法返回空清单，条目缺字段以空串/0 补齐——容错优先）。
 */
public func parseShareIndex(text: String): ArrayList<ShareEntry> {
    let out = ArrayList<ShareEntry>()
    match (parseJsonValue(text)) {
        case None => ()
        case Some(root) =>
            if (root.kind != 0) {
                return out
            }
            match (root.obj.get("库")) {
                case None => ()
                case Some(list) =>
                    if (list.kind == 5) {
                        for (item in list.arr) {
                            if (item.kind != 0) {
                                continue
                            }
                            out.add(ShareEntry(
                                shareJsonStr(item, "名称"),
                                shareJsonStr(item, "语言"),
                                shareJsonStr(item, "描述"),
                                shareJsonStr(item, "作者"),
                                shareJsonNum(item, "键数"),
                                shareJsonStr(item, "校验和"),
                                shareJsonStr(item, "时间")))
                        }
                    }
            }
    }
    return out
}

/** 取对象节点字符串字段（缺/非字符串返回 ""）。 */
func shareJsonStr(node: JsonNode, key: String): String {
    match (node.obj.get(key)) {
        case None => return ""
        case Some(v) =>
            if (v.kind == 1) {
                return v.str
            }
            return ""
    }
}

/** 取对象节点数字字段（kind 2 原文或字符串数字）；缺/非法返回 0。 */
func shareJsonNum(node: JsonNode, key: String): Int64 {
    match (node.obj.get(key)) {
        case None => return 0
        case Some(v) =>
            if (v.kind == 2) {
                try {
                    return Int64.parse(v.str)
                } catch (e: Exception) {
                    return 0
                }
            }
            if (v.kind == 1) {
                try {
                    return Int64.parse(v.str)
                } catch (e: Exception) {
                    return 0
                }
            }
            return 0
    }
}

/** 条目 → JSON 对象文本（字段顺序固定，便于 diff 与重建 index）。 */
public func shareEntryJson(e: ShareEntry): String {
    return "{\"名称\": ${jsonQuote(e.name)}, \"语言\": ${jsonQuote(e.lang)}, " +
        "\"描述\": ${jsonQuote(e.desc)}, \"作者\": ${jsonQuote(e.author)}, " +
        "\"键数\": ${e.keyCount}, \"校验和\": ${jsonQuote(e.checksum)}, " +
        "\"时间\": ${jsonQuote(e.time)}}"
}

/**
 * 重建 index.json（按 语言+名称 字典序，确定性输出便于审校与幂等更新）。
 * 排序用字符串键映射（std.sort 自定义比较器未在仓库内实测，避坑）。
 * index 头部保留 "版本": 1。
 */
public func buildShareIndexJson(entries: ArrayList<ShareEntry>): String {
    let keyed = HashMap<String, ShareEntry>()
    let keys = ArrayList<String>()
    for (e in entries) {
        let key = "${e.lang}\u{1}${e.name}"
        keyed.add(key, e)
        keys.add(key)
    }
    sort(keys)
    var sb = "{\n\"版本\": 1,\n\"库\": [\n"
    var first = true
    for (key in keys) {
        if (!first) {
            sb = "${sb},\n"
        }
        first = false
        sb = "${sb}${shareEntryJson(keyed.get(key).getOrThrow())}"
    }
    sb = "${sb}\n]\n}\n"
    return sb
}

/**
 * 组装 publish 请求体（HTTP 端点提交）：内容 + 元数据 + 校验和。
 * 纯字符串函数，可单测 round-trip。
 */
public func buildPublishJson(name: String, lang: String, desc: String,
                             author: String, keyCount: Int64,
                             checksum: String, time: String, content: String): String {
    return "{\"名称\": ${jsonQuote(name)}, \"语言\": ${jsonQuote(lang)}, " +
        "\"描述\": ${jsonQuote(desc)}, \"作者\": ${jsonQuote(author)}, " +
        "\"键数\": ${keyCount}, \"校验和\": ${jsonQuote(checksum)}, " +
        "\"时间\": ${jsonQuote(time)}, \"内容\": ${jsonQuote(content)}}"
}

/** 映射内容校验和（cache.cj 同款 hash64 的 16 位十六进制；防传输损坏）。 */
public func shareChecksum(content: String): String {
    return hexOf(hash64(content))
}

// ==================== HTTP 传输（curl → python3 降级，同 ai_client 结论） ====================

var shareCurlProbed: Bool = false
var shareCurlOk: Bool = false

/** curl 可用性探测（独立静态缓存，与 AI 通道互不干扰）。 */
func shareHaveCurl(): Bool {
    if (!shareCurlProbed) {
        let (code, _, _) = executeWithOutput("curl", ["--version"])
        shareCurlOk = code == 0
        shareCurlProbed = true
    }
    return shareCurlOk
}

var sharePyProbed: Bool = false
var sharePyOk: Bool = false

/** python3 可用性探测（静态缓存）。 */
func shareHavePython3(): Bool {
    if (!sharePyProbed) {
        let (code, _, _) = executeWithOutput("python3", ["--version"])
        sharePyOk = code == 0
        sharePyProbed = true
    }
    return sharePyOk
}

/** HTTP GET：返回 (httpCode, body)；传输失败 httpCode = -1（body = 错误摘要）。 */
func shareHttpGet(url: String): (Int64, String) {
    if (shareHaveCurl()) {
        let (code, outB, errB) = executeWithOutput("curl", [
            "-sS", "-m", "60", "-w", "\n%{http_code}", url])
        return parseShareHttpResp(code, outB, errB)
    }
    if (shareHavePython3()) {
        let py = "import sys, urllib.request, urllib.error\n" +
            "u = sys.argv[1]\n" +
            "try:\n" +
            "    r = urllib.request.urlopen(u, timeout=60)\n" +
            "    sys.stdout.write(r.read().decode('utf-8', 'replace'))\n" +
            "    sys.stdout.write('\\n')\n" +
            "    sys.stdout.write(str(r.status))\n" +
            "except urllib.error.HTTPError as e:\n" +
            "    sys.stdout.write(e.read().decode('utf-8', 'replace'))\n" +
            "    sys.stdout.write('\\n')\n" +
            "    sys.stdout.write(str(e.code))\n" +
            "except Exception as e:\n" +
            "    sys.stdout.write(str(e))\n" +
            "    sys.stdout.write('\\n-1')\n"
        let pyFile = "${getTempDirectory()}/zhc-share-${getProcessId()}-get.py"
        File.writeTo(pyFile, py.toArray())
        let (code, outB, errB) = executeWithOutput("python3", [pyFile, url])
        return parseShareHttpResp(code, outB, errB)
    }
    return (-1, "未找到 curl 与 python3（至少其一用于 HTTP 访问）")
}

/** HTTP POST JSON：返回 (httpCode, body)；传输失败 httpCode = -1。 */
func shareHttpPost(url: String, bodyFile: String): (Int64, String) {
    if (shareHaveCurl()) {
        let (code, outB, errB) = executeWithOutput("curl", [
            "-sS", "-m", "60", "-w", "\n%{http_code}", "-X", "POST", url,
            "-H", "Content-Type: application/json",
            "--data-binary", "@${bodyFile}"])
        return parseShareHttpResp(code, outB, errB)
    }
    if (shareHavePython3()) {
        let py = "import sys, urllib.request, urllib.error\n" +
            "p, u = sys.argv[1], sys.argv[2]\n" +
            "req = urllib.request.Request(u, data=open(p, 'rb').read(), method='POST')\n" +
            "req.add_header('Content-Type', 'application/json')\n" +
            "try:\n" +
            "    r = urllib.request.urlopen(req, timeout=60)\n" +
            "    sys.stdout.write(r.read().decode('utf-8', 'replace'))\n" +
            "    sys.stdout.write('\\n')\n" +
            "    sys.stdout.write(str(r.status))\n" +
            "except urllib.error.HTTPError as e:\n" +
            "    sys.stdout.write(e.read().decode('utf-8', 'replace'))\n" +
            "    sys.stdout.write('\\n')\n" +
            "    sys.stdout.write(str(e.code))\n" +
            "except Exception as e:\n" +
            "    sys.stdout.write(str(e))\n" +
            "    sys.stdout.write('\\n-1')\n"
        let pyFile = "${getTempDirectory()}/zhc-share-${getProcessId()}-post.py"
        File.writeTo(pyFile, py.toArray())
        let (code, outB, errB) = executeWithOutput("python3", [pyFile, bodyFile, url])
        return parseShareHttpResp(code, outB, errB)
    }
    return (-1, "未找到 curl 与 python3（至少其一用于 HTTP 访问）")
}

/** 解析 <body>\n<http_code> 响应协议（ai_client 同款）；进程失败 → (-1, stderr)。 */
func parseShareHttpResp(procCode: Int64, outB: Array<Byte>, errB: Array<Byte>): (Int64, String) {
    let out = String.fromUtf8(outB)
    if (procCode != 0) {
        return (-1, snippet(String.fromUtf8(errB), 200))
    }
    match (out.lastIndexOf("\n")) {
        case None => return (-1, snippet(out, 200))
        case Some(nl) =>
            var httpCode: Int64 = -1
            try {
                httpCode = Int64.parse(out[nl + 1..out.size].trimAscii())
            } catch (e: Exception) {
                httpCode = -1
            }
            return (httpCode, out[0..nl])
    }
}

// ==================== index 读取（本地/HTTP 统一） ====================

/** 读取共享仓库 index.json；失败抛异常（消息含 base 与原因）。 */
func shareReadIndex(base: String): String {
    if (isLocalShareBase(base)) {
        let p = shareJoinUrl(base, "index.json")
        if (!exists(Path(p))) {
            throw TomlParseError("共享仓库缺少 index.json：${base}（初始化见 libs/README.md 或 share publish 首次提交）")
        }
        return readTextFile(p)
    }
    let (httpCode, body) = shareHttpGet(shareJoinUrl(base, "index.json"))
    if (httpCode == 404) {
        throw TomlParseError("共享仓库缺少 index.json（HTTP 404）：${base}")
    }
    if (httpCode < 200 || httpCode >= 300) {
        throw TomlParseError("共享仓库不可达（HTTP ${httpCode}）：${snippet(body, 120)}")
    }
    // 非 JSON 响应诊断（网页/登录页/预览限制页都会以 200 返回 HTML）
    match (parseJsonValue(body)) {
        case None =>
            throw TomlParseError("共享源返回的不是有效 index.json（HTTP ${httpCode}）：可能被重定向到网页或需要登录态（${snippet(body, 80)}）。请检查 base 地址，或改用 ZHC_SHARE_BASE 指向自建 share_server / 本地镜像目录")
        case Some(_) => ()
    }
    return body
}

/** 注册表内映射文件路径（相对 base）。 */
func shareCratePath(lang: String, name: String): String {
    return "crates/${lang}/${name}.toml"
}

// ==================== 场景 ①：浏览 / 搜索 / 按需下载 ====================

/** share list：列出共享仓库全部映射（语言/名称/键数/描述）。 */
func cmdShareList(base: String): Int64 {
    try {
        let entries = parseShareIndex(shareReadIndex(base))
        if (entries.isEmpty()) {
            println(uiTextF("共享仓库为空：{0}", [base]))
            return 1
        }
        println(uiTextF("共享仓库 {0}（{1} 个映射）：", [base, entries.size.toString()]))
        for (e in entries) {
            println(uiTextF("  [{0}] {1}  键 {2}  {3}{4}",
                [e.lang, e.name, e.keyCount.toString(), e.desc,
                 if (e.author.isEmpty()) { "" } else { "（作者：${e.author}）" }]))
        }
        println(uiText("按需下载：zhc share fetch <库名> [--lang <代码>]"))
        return 0
    } catch (e: Exception) {
        println(uiTextF("share list 失败：{0}", [snippet(e.message, 200)]))
        return 1
    }
}

/** share search <关键词>：按名称/描述/作者过滤（大小写敏感的包含匹配）。 */
func cmdShareSearch(base: String, kw: String): Int64 {
    try {
        let entries = parseShareIndex(shareReadIndex(base))
        let hits = ArrayList<ShareEntry>()
        for (e in entries) {
            if (e.name.contains(kw) || e.desc.contains(kw) ||
                e.author.contains(kw) || e.lang.contains(kw)) {
                hits.add(e)
            }
        }
        if (hits.isEmpty()) {
            println(uiTextF("未搜索到匹配 \"{0}\" 的共享映射（仓库 {1}，共 {2} 个）",
                [kw, base, entries.size.toString()]))
            return 1
        }
        println(uiTextF("搜索 \"{0}\" 命中 {1} 个：", [kw, hits.size.toString()]))
        for (e in hits) {
            println(uiTextF("  [{0}] {1}  键 {2}  {3}",
                [e.lang, e.name, e.keyCount.toString(), e.desc]))
        }
        return 0
    } catch (e: Exception) {
        println(uiTextF("share search 失败：{0}", [snippet(e.message, 200)]))
        return 1
    }
}

/**
 * share fetch <库名>：按需下载单个映射。
 * 流程：index 定位条目 → 只下载该 toml → 校验和比对 → 内容门禁 → 撞词表
 * （--force 跳过）→ 写入目标 crates 目录（默认当前语言包，只写单文件）。
 */
func cmdShareFetch(rest: Array<String>, base: String): Int64 {
    if (rest.isEmpty() || rest[0].startsWith("--")) {
        println(uiText("用法：zhc share fetch <库名> [--lang <代码>] [--dir <目录>] [--force] [--base <目录或URL>]"))
        return 1
    }
    let name = sanitizeShareName(rest[0])
    if (name.isEmpty()) {
        println(uiTextF("库名不合法：{0}", [rest[0]]))
        return 1
    }
    let langOpt = extractShareOpt(rest, "--lang")
    let dirOpt = extractShareOpt(rest, "--dir")
    var force = false
    for (a in rest) {
        if (a == "--force") {
            force = true
        }
    }
    var lang = resolveLang()
    if (langOpt != None) {
        lang = langOpt.getOrThrow()
    }
    // ① index 定位
    var entry: ShareEntry
    try {
        let entries = parseShareIndex(shareReadIndex(base))
        let found = ArrayList<ShareEntry>()
        for (e in entries) {
            if (e.name == name) {
                found.add(e)
            }
        }
        if (found.isEmpty()) {
            println(uiTextF("共享仓库中不存在 \"{0}\"（zhc share search <关键词> 先搜索）", [name]))
            return 1
        }
        var picked: ?ShareEntry = None
        for (e in found) {
            if (e.lang == lang) {
                picked = e
            }
        }
        if (isNoneOpt(picked)) {
            var langs = ""
            for (e in found) {
                langs = "${langs}[${e.lang}] "
            }
            println(uiTextF("{0} 存在但无 {1} 方言版本；已有：{2}（用 --lang 指定）",
                [name, lang, langs]))
            return 1
        }
        entry = picked.getOrThrow()
    } catch (e: Exception) {
        println(uiTextF("share fetch 失败：{0}", [snippet(e.message, 200)]))
        return 1
    }
    // ② 只下载该映射文件（本地读 / HTTP GET 单文件）
    var content = ""
    let relPath = shareCratePath(entry.lang, name)
    if (isLocalShareBase(base)) {
        let p = shareJoinUrl(base, relPath)
        if (!exists(Path(p))) {
            println(uiTextF("共享仓库缺少映射文件：{0}", [p]))
            return 1
        }
        content = readTextFile(p)
    } else {
        let (httpCode, body) = shareHttpGet(shareJoinUrl(base, relPath))
        if (httpCode < 200 || httpCode >= 300) {
            println(uiTextF("下载失败（HTTP {0}）：{1}", [httpCode.toString(), snippet(body, 120)]))
            return 1
        }
        content = body
    }
    // ③ 完整性校验（校验和缺失时警告跳过）
    if (!entry.checksum.isEmpty()) {
        let actual = shareChecksum(content)
        if (actual != entry.checksum) {
            println(uiTextF("完整性校验失败：期望 {0}，实际 {1}（传输损坏？重试或联系维护者）",
                [entry.checksum, actual]))
            return 1
        }
    } else {
        println(uiText("警告：index 未含校验和，跳过完整性校验"))
    }
    // ④ 内容门禁（格式与键值）
    let errs = validateMappingToml(content)
    if (!errs.isEmpty()) {
        println(uiTextF("下载的映射未通过质量门禁（{0} 项）：", [errs.size.toString()]))
        for (er in errs) {
            println("    ${er}")
        }
        return 1
    }
    // ⑤ 撞词表检查（当前语言包保留词；--force 跳过）
    if (!force) {
        let collide = shareCollideReserved(content, lang, name)
        if (!collide.isEmpty()) {
            println(uiTextF("映射键与 {0} 语言包保留词冲突（{1} 项）——crates 为全局别名，安装会改义：",
                [lang, collide.size.toString()]))
            for (c in collide) {
                println("    ${c}")
            }
            println(uiText("确认无误可用 --force 强制安装；建议先反馈维护者修订"))
            return 1
        }
    }
    // ⑥ 安装：--dir 显式目录 > 当前语言包 crates（packRootOf 定位失败回退 ~/.zhc）
    var targetDir = ""
    match (dirOpt) {
        case Some(d) => targetDir = d
        case None =>
            try {
                targetDir = "${packRootOf(lang)}/lang-packs/${lang}/crates"
            } catch (e: Exception) {
                let home = getVariable("HOME")
                if (home != None && !home.getOrThrow().isEmpty()) {
                    targetDir = "${home.getOrThrow()}/.zhc/lang-packs/${lang}/crates"
                } else {
                    targetDir = "./lang-packs/${lang}/crates"
                }
            }
    }
    let target = shareJoinUrl(targetDir, "${name}.toml")
    try {
        ensureParentDir(target)
        File.writeTo(target, content.toArray())
    } catch (e: Exception) {
        println(uiTextF("安装失败（{0} 不可写？）：{1}", [targetDir, e.message]))
        return 1
    }
    println(uiTextF("已安装：{0}（{1} 方言，键 {2} 个，仅下载所需单文件）",
        [target, lang, entry.keyCount.toString()]))
    println(uiText("下一步：zhc mapping check 验证后即可用母语 import 该库（cjpm 依赖需自行添加）"))
    return 0
}

/** 撞词表检查：映射键 ∩ 当前语言包保留词（关键字/宏/别名/模块路径）。 */
func shareCollideReserved(content: String, lang: String, selfName: String): ArrayList<String> {
    let hits = ArrayList<String>()
    let reserved = HashSet<String>()
    try {
        let l = resolveLangPack(lang)
        for (k in l.keywords.keys()) {
            reserved.add(k)
        }
        for (k in l.macros.keys()) {
            reserved.add(k)
        }
        for (k in l.aliases.keys()) {
            reserved.add(k)
        }
        for (k in l.modulePaths.keys()) {
            reserved.add(k)
        }
    } catch (e: Exception) {
        return hits   // 语言包不可用：跳过检查（fetch 已尽量装载）
    }
    // 同库旧映射的键豁免（覆盖更新允许同名键，§6.3 后载覆盖）：先收集再跳过
    // （避免依赖 HashSet.remove，与 buildReserved 同思路）
    let selfKeys = HashSet<String>()
    var packRoot = ""
    try {
        packRoot = packRootOf(lang)
    } catch (e: Exception) {
        packRoot = ""
    }
    if (!packRoot.isEmpty()) {
        let oldPath = "${packRoot}/lang-packs/${lang}/crates/${selfName}.toml"
        if (exists(Path(oldPath))) {
            try {
                let old = parseToml(readTextFile(oldPath))
                for (sec in ["标识符", "宏"]) {
                    match (old.get(sec)) {
                        case None => ()
                        case Some(section) =>
                            for (k in section.keys()) {
                                selfKeys.add(k)
                            }
                    }
                }
            } catch (e: Exception) {
                ()   // 旧文件损坏：不豁免（保守）
            }
        }
    }
    var section = ""
    for (raw in content.split("\n")) {
        let line = raw.trimAscii()
        if (line.isEmpty() || line.startsWith("#")) {
            continue
        }
        if (line.startsWith("[") && line.endsWith("]")) {
            section = trimQuote(line[1..line.size - 1].trimAscii())
            continue
        }
        let kv = parseShareKvLine(line)
        match (kv) {
            case None => ()
            case Some(pair) =>
                if (reserved.contains(pair[0]) && !selfKeys.contains(pair[0])) {
                    hits.add("${pair[0]} → ${pair[1]}（撞 [${section}] 保留词）")
                }
        }
    }
    return hits
}

// ==================== 场景 ②：上传共享 ====================

/**
 * share publish <文件.toml>：上传自译映射。
 * 门禁 → 组装 JSON → 本地目录落盘（幂等 upsert index）/ HTTP POST →
 * 失败降级导出 zhc-共享-<名>/ 提交包（走 libs/ 众包 PR 渠道）。
 */
func cmdSharePublish(rest: Array<String>, base: String): Int64 {
    if (rest.isEmpty() || rest[0].startsWith("--")) {
        println(uiText("用法：zhc share publish <文件.toml> [--name <库名>] [--lang <代码>] [--desc <描述>] [--author <作者>] [--base <目录或URL>]"))
        return 1
    }
    let filePath = rest[0]
    if (!exists(Path(filePath))) {
        println(uiTextF("映射文件不存在：{0}", [filePath]))
        return 1
    }
    let nameOpt = extractShareOpt(rest, "--name")
    let langOpt = extractShareOpt(rest, "--lang")
    let descOpt = extractShareOpt(rest, "--desc")
    let authorOpt = extractShareOpt(rest, "--author")
    var rawName = shareBaseName(filePath)
    if (nameOpt != None) {
        rawName = nameOpt.getOrThrow()
    }
    let name = sanitizeShareName(rawName)
    if (name.isEmpty()) {
        println(uiTextF("库名不合法：{0}（用 --name 指定合法名称）", [rawName]))
        return 1
    }
    var lang = resolveLang()
    if (langOpt != None) {
        lang = langOpt.getOrThrow()
    }
    var desc = ""
    if (descOpt != None) {
        desc = descOpt.getOrThrow()
    }
    var author = ""
    let userEnv = getVariable("USER")
    if (userEnv != None) {
        author = userEnv.getOrThrow()
    }
    if (authorOpt != None) {
        author = authorOpt.getOrThrow()
    }
    // ① 门禁：格式 + 撞词表（发布前把关，与 libs/ 平台守则一致）
    let content = readTextFile(filePath)
    let errs = validateMappingToml(content)
    if (!errs.isEmpty()) {
        println(uiTextF("映射未通过质量门禁（{0} 项），请修订后重试：", [errs.size.toString()]))
        for (er in errs) {
            println("    ${er}")
        }
        return 1
    }
    let collide = shareCollideReserved(content, lang, name)
    if (!collide.isEmpty()) {
        println(uiTextF("映射键与 {0} 语言包保留词冲突（{1} 项），不得发布：", [lang, collide.size.toString()]))
        for (c in collide) {
            println("    ${c}")
        }
        println(uiText("请为冲突键另选母语名（键 = 母语名，值 = 官方名，见 libs/README.md 守则）"))
        return 1
    }
    // ② 元数据：键数（节名合法性与格式由 validateMappingToml 把关，此处只计数）
    var keyCount: Int64 = 0
    for (raw in content.split("\n")) {
        let line = raw.trimAscii()
        if (line.isEmpty() || line.startsWith("#")) {
            continue
        }
        if (line.startsWith("[") && line.endsWith("]")) {
            continue
        }
        if (parseShareKvLine(line) != None) {
            keyCount += 1
        }
    }
    let checksum = shareChecksum(content)
    let time = shareNowStamp()
    // ③ 本地目录：直接落盘 + 幂等 upsert index
    if (isLocalShareBase(base)) {
        try {
            let cratePath = shareJoinUrl(base, shareCratePath(lang, name))
            ensureParentDir(cratePath)
            File.writeTo(cratePath, content.toArray())
            upsertLocalIndex(base, ShareEntry(name, lang, desc, author, keyCount, checksum, time))
        } catch (e: Exception) {
            println(uiTextF("publish 失败（本地共享仓库 {0} 不可写？）：{1}", [base, e.message]))
            return 1
        }
        println(uiTextF("已发布到本地共享仓库：{0}/crates/{1}/{2}.toml（键 {3} 个，校验和 {4}）",
            [base, lang, name, keyCount.toString(), checksum]))
        println(uiText("其他用户：zhc share fetch " + "${name} --lang ${lang} --base ${base}"))
        return 0
    }
    // ④ HTTP 端点：POST {base}/share-publish
    let body = buildPublishJson(name, lang, desc, author, keyCount, checksum, time, content)
    let reqFile = "${getTempDirectory()}/zhc-share-${getProcessId()}-pub.json"
    try {
        File.writeTo(reqFile, body.toArray())
    } catch (e: Exception) {
        println(uiTextF("publish 失败（临时文件不可写）：{0}", [e.message]))
        return 1
    }
    let (httpCode, respBody) = shareHttpPost(shareJoinUrl(base, "share-publish"), reqFile)
    if (httpCode >= 200 && httpCode < 300) {
        println(uiTextF("已发布到共享仓库：{0}（键 {1} 个，校验和 {2}）", [base, keyCount.toString(), checksum]))
        println(uiText("其他用户：zhc share search " + "${name} && zhc share fetch ${name} --lang ${lang}"))
        return 0
    }
    // ⑤ 降级：导出提交包（网络/服务端失败不丢成果）
    println(uiTextF("上传失败（HTTP {0}）：{1}", [httpCode.toString(), snippet(respBody, 160)]))
    exportShareSubmitPackage(name, lang, desc, author, keyCount, checksum, content)
    println(uiText("已降级导出提交包；可把其中 crates/ 内容提交到 libs/ 众包平台（fork → PR → 门禁自动把关）"))
    return 1
}

/** 文件基名（去目录与 .toml 后缀）。 */
func shareBaseName(path: String): String {
    var p = path
    let slash = p.lastIndexOf("/")
    if (slash != None) {
        p = p[slash.getOrThrow() + 1..p.size]
    }
    if (p.endsWith(".toml")) {
        p = p[0..p.size - 5]
    }
    return p
}

/** 当前时间戳（date 命令；失败返回空串——时间非关键元数据）。 */
func shareNowStamp(): String {
    let (code, outB, _) = executeWithOutput("date", ["+%Y-%m-%dT%H:%M:%S%z"])
    if (code != 0) {
        return ""
    }
    return String.fromUtf8(outB).trimAscii()
}

/**
 * 本地注册表 index 幂等更新：读 → 删同名同语言 → 追加 → 写回。
 * index 解析失败即中止（宁可失败也不覆盖坏文件）。
 */
func upsertLocalIndex(base: String, entry: ShareEntry): Unit {
    let indexPath = shareJoinUrl(base, "index.json")
    var entries = ArrayList<ShareEntry>()
    if (exists(Path(indexPath))) {
        let old = parseShareIndex(readTextFile(indexPath))
        if (old.isEmpty()) {
            // 空仓库合法（首次发布）；但损坏 index 也会解析为空——用解析异常区分：
            // parseShareIndex 对坏 JSON 返回空，这里再探一次原文结构
            let raw = readTextFile(indexPath)
            match (parseJsonValue(raw)) {
                case None =>
                    throw TomlParseError("index.json 损坏（非法 JSON），请先修复：${indexPath}")
                case Some(root) =>
                    if (root.kind == 0 && isSomeOpt(root.obj.get("库"))) {
                        throw TomlParseError("index.json 条目均不可解析，请先修复：${indexPath}")
                    }
                    // 合法但确无 "库" 节：视为初始仓库，继续
            }
        }
        for (e in old) {
            if (!(e.name == entry.name && e.lang == entry.lang)) {
                entries.add(e)
            }
        }
    }
    entries.add(entry)
    File.writeTo(indexPath, buildShareIndexJson(entries).toArray())
}

/**
 * 降级导出提交包 zhc-共享-<名>/：crates/<lang>/<名>.toml + 元数据 JSON +
 * README（libs/ 众包 PR 指引）。与 translate --share 导出同族，接收方安装方式一致。
 */
func exportShareSubmitPackage(name: String, lang: String, desc: String, author: String,
                              keyCount: Int64, checksum: String, content: String): Unit {
    let outDir = "zhc-共享-${name}"
    let crateFile = "${outDir}/lang-packs/${lang}/crates/${name}.toml"
    try {
        ensureParentDir(crateFile)
        File.writeTo(crateFile, content.toArray())
        let meta = buildPublishJson(name, lang, desc, author, keyCount, checksum, shareNowStamp(), content)
        File.writeTo("${outDir}/元数据.json", meta.toArray())
        var readme = "# zhc 共享映射提交包：${name}（${lang} 方言）\n\n"
        readme = "${readme}上传 HTTP 共享仓库失败时的降级产物，两种去路：\n"
        readme = "${readme}1. 提交到 libs/ 众包平台：把 lang-packs/${lang}/crates/${name}.toml 复制到\n"
        readme = "${readme}   仓库 libs/${lang}/crates/，fork → PR → check-libs 门禁自动把关；\n"
        readme = "${readme}2. 直接分享：接收方把 lang-packs/ 并入 ~/.zhc/ 或语言包根即生效。\n"
        File.writeTo("${outDir}/README.md", readme.toArray())
        println(uiTextF("已导出提交包：{0}/（含映射、元数据与 PR 指引）", [outDir]))
    } catch (e: Exception) {
        println(uiTextF("提交包导出失败：{0}", [e.message]))
    }
}
