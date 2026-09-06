package zhc

import std.collection.*
import std.env.*
import std.fs.*
import std.sort.*

/**
 * 语言包模型与加载（对应设计 §6 数据层）。
 *
 * 阶段 0 最小集：
 *   - lang_info.toml ：语言包元信息（代码/名称/扩展名）
 *   - keywords.toml  ：关键字映射，除 [宏] 节外的所有节合并为关键字表，
 *                      [宏] 节独立为宏表（@ 后专用，见 §5.1 第 4 条）
 *   - ui.toml        ：["界面消息"] 节 → 界面文案表（引擎自国际化最小集）
 *
 * 阶段 2 增量（设计 §5.2/§5.3）：
 *   - module_paths.toml ：["模块路径"] 节 → import 语句态路径段映射
 *   - stdlib.toml        ：["模块路径"] 节并入 modulePaths（后载覆盖同名键），
 *                          ["标识符"] 节 → 别名表（两遍扫描 + 豁免集保护）
 * 阶段 3 增量（设计 §7.2）：
 *   - errors.toml       ：["诊断码"]（键 = cjc JSON 的 DiagKind 字段，实测稳定）
 *                          与 ["消息翻译"]（精确/最长前缀/~后缀）两类条目，
 *                          每条目含 消息模板/教学提示/修复示例（parseTomlNested）
 * 查找顺序（调用方决定）：环境变量 ZHC_LANG_PACKS → ./lang-packs → 可执行文件旁。
 * 合并规则（§6.3）：节按名排序后依次合并，后节覆盖同名键；
 *
 * 1.0 适配记录（本机 cjc 1.0.5 实测）：
 *   - Path.of 不存在，Path("...") 构造；
 *   - Directory.exists/File.exists 不存在，用顶层 exists(Path)；
 *   - ArrayList.sort 成员已废弃，用 std.sort 顶层 sort；
 *   - File.open/readToEnd 不存在，用 File.readFrom + String.fromUtf8。
 */

public class DiagEntry {
    public var template: String
    public var tip: String
    public var fix: String

    public init(template: String, tip: String, fix: String) {
        this.template = template
        this.tip = tip
        this.fix = fix
    }
}

public class LangPack {
    public var code: String
    public var name: String
    public var extensions: ArrayList<String>
    public var keywords: HashMap<String, String>
    public var macros: HashMap<String, String>
    public var modulePaths: HashMap<String, String>
    public var aliases: HashMap<String, String>
    public var diagKinds: HashMap<String, DiagEntry>
    public var msgEntries: HashMap<String, DiagEntry>
    public var ui: HashMap<String, String>
    public var testDict: HashMap<String, String>

    public init(code: String, name: String, extensions: ArrayList<String>,
                keywords: HashMap<String, String>, macros: HashMap<String, String>,
                modulePaths: HashMap<String, String>, aliases: HashMap<String, String>,
                diagKinds: HashMap<String, DiagEntry>, msgEntries: HashMap<String, DiagEntry>,
                ui: HashMap<String, String>, testDict: HashMap<String, String>) {
        this.code = code
        this.name = name
        this.extensions = extensions
        this.keywords = keywords
        this.macros = macros
        this.modulePaths = modulePaths
        this.aliases = aliases
        this.diagKinds = diagKinds
        this.msgEntries = msgEntries
        this.ui = ui
        this.testDict = testDict
    }

    /** 界面文案；缺键回退到给定默认值（引擎自身 i18n 最小集，§5.5）。 */
    public func uiText(key: String, defaultText: String): String {
        let v = this.ui.get(key)
        if (v == None) {
            return defaultText
        }
        return v.getOrThrow()
    }
}

/** 在给定语言包根目录下加载指定代码的语言包；目录不存在返回 None。 */
public func loadLangPack(baseDir: String, code: String): ?LangPack {
    let packRoot = "${baseDir}/lang-packs/${code}"
    if (!exists(Path(packRoot))) {
        return None
    }
    let infoPath = "${packRoot}/lang_info.toml"
    if (!exists(Path(infoPath))) {
        throw TomlParseError("语言包缺少 lang_info.toml：${packRoot}")
    }
    let info = parseToml(readTextFile(infoPath))

    // 注：Option<HashMap> 无 == 比较（1.0），用模式匹配解包
    var name = code
    var extensions = ArrayList<String>()
    match (info.get("语言包")) {
        case None => ()
        case Some(infoSection) =>
            let vName = infoSection.get("名称")
            if (vName != None) {
                name = vName.getOrThrow()
            }
            let vExt = infoSection.get("扩展名")
            if (vExt != None) {
                for (e in vExt.getOrThrow().split(",")) {
                    let t = e.trimAscii()
                    if (!t.isEmpty()) {
                        extensions.add(t)
                    }
                }
            }
    }
    if (extensions.isEmpty()) {
        extensions.add(code)
    }

    // §16.7：编码可插拔——lang_info.toml 的 [语言包] 格式 字段声明编码
    // （默认 toml；json 时各表用同名 .json 文件，结构同 TOML）
    var format = "toml"
    match (info.get("语言包")) {
        case None => ()
        case Some(infoSection) =>
            let vFormat = infoSection.get("格式")
            if (vFormat != None) {
                format = vFormat.getOrThrow()
            }
    }
    if (format == "json") {
        return loadPackJson(packRoot, code, name, extensions)
    }
    if (format != "toml") {
        throw TomlParseError("不支持的语言包编码格式：${format}（lang_info.toml [语言包] 格式 字段，可选 toml/json）")
    }
    return loadPackToml(packRoot, code, name, extensions)
}

/** TOML 编码语言包加载（默认；§6.3 各表合并规则见 loadLangPack 头注）。 */
private func loadPackToml(packRoot: String, code: String, name: String,
                          extensions: ArrayList<String>): LangPack {
    // keywords.toml：非 [宏] 节合并为关键字表；[宏] 节独立
    let kwPath = "${packRoot}/keywords.toml"
    let keywords = HashMap<String, String>()
    let macros = HashMap<String, String>()
    if (exists(Path(kwPath))) {
        let tables = parseToml(readTextFile(kwPath))
        let sectionNames = ArrayList<String>()
        for (s in tables.keys()) {
            sectionNames.add(s)
        }
        sort(sectionNames)               // §6.3：合并前排序，后节覆盖同名键
        for (section in sectionNames) {
            let table = tables.get(section).getOrThrow()
            if (section == "宏") {
                for (k in table.keys()) {
                    macros.add(normalizeKey(k), table.get(k).getOrThrow())
                }
            } else {
                for (k in table.keys()) {
                    keywords.add(normalizeKey(k), table.get(k).getOrThrow())
                }
            }
        }
    }

    // ui.toml：["界面消息"] 节 + ["测试输出"] 节（zhc test 对 cjpm 文本输出的
    // 本地化词典：键 = 官方英文锚点，值 = 母语；缺节/缺键即不替换，原样透传）
    let uiPath = "${packRoot}/ui.toml"
    let ui = HashMap<String, String>()
    let testDict = HashMap<String, String>()
    if (exists(Path(uiPath))) {
        let tables = parseToml(readTextFile(uiPath))
        match (tables.get("界面消息")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    ui.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
        match (tables.get("测试输出")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    testDict.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
    }

    // 阶段 2：module_paths.toml + stdlib.toml（§6.3 最后加载覆盖同名键）
    let modulePaths = HashMap<String, String>()
    let aliases = HashMap<String, String>()
    let mpPath = "${packRoot}/module_paths.toml"
    if (exists(Path(mpPath))) {
        let tables = parseToml(readTextFile(mpPath))
        match (tables.get("模块路径")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    modulePaths.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
    }
    let slPath = "${packRoot}/stdlib.toml"
    if (exists(Path(slPath))) {
        let tables = parseToml(readTextFile(slPath))
        match (tables.get("模块路径")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    modulePaths.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
        match (tables.get("标识符")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    aliases.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
    }

    // 阶段 2b：crates/ 第三方库映射（§6.3/§10：与 stdlib.toml 同格式，
    // 最后加载覆盖同名键——社区映射优先于内置，含宏节（§16.4 expand 宏名））
    loadCratesToml(packRoot, modulePaths, aliases, macros)

    // 阶段 3：errors.toml（parseTomlNested 三级表）
    let diagKinds = HashMap<String, DiagEntry>()
    let msgEntries = HashMap<String, DiagEntry>()
    let errPath = "${packRoot}/errors.toml"
    if (exists(Path(errPath))) {
        let nested = parseTomlNested(readTextFile(errPath))
        let kindEntries = nested.get("诊断码")
        if (kindEntries != None) {
            for (k in kindEntries.getOrThrow().keys()) {
                let fields = kindEntries.getOrThrow().get(k).getOrThrow()
                diagKinds.add(normalizeKey(k), entryOf(fields))
            }
        }
        let msgEntries2 = nested.get("消息翻译")
        if (msgEntries2 != None) {
            for (k in msgEntries2.getOrThrow().keys()) {
                let fields = msgEntries2.getOrThrow().get(k).getOrThrow()
                msgEntries.add(normalizeKey(k), entryOf(fields))
            }
        }
    }

    return LangPack(code, name, extensions, keywords, macros, modulePaths, aliases, diagKinds, msgEntries, ui, testDict)
}

/**
 * JSON 编码语言包加载（§16.7：lang_info.toml 格式 = "json"）。
 * 文件结构同 TOML：keywords.json 两级（节 → 键值），errors.json 三级。
 */
private func loadPackJson(packRoot: String, code: String, name: String,
                          extensions: ArrayList<String>): LangPack {
    let keywords = HashMap<String, String>()
    let macros = HashMap<String, String>()
    let kwPath = "${packRoot}/keywords.json"
    if (exists(Path(kwPath))) {
        match (parseJsonValue(readTextFile(kwPath))) {
            case None => ()
            case Some(root) =>
                if (root.kind == 0) {
                    for (s in root.obj.keys()) {
                        let table = root.obj.get(s).getOrThrow()
                        if (table.kind != 0) {
                            continue
                        }
                        if (s == "宏") {
                            for (k in table.obj.keys()) {
                                macros.add(normalizeKey(k), jstr(table, k).getOrThrow())
                            }
                        } else {
                            for (k in table.obj.keys()) {
                                keywords.add(normalizeKey(k), jstr(table, k).getOrThrow())
                            }
                        }
                    }
                }
        }
    }

    let ui = HashMap<String, String>()
    let testDict = HashMap<String, String>()
    let uiPath = "${packRoot}/ui.json"
    if (exists(Path(uiPath))) {
        match (parseJsonValue(readTextFile(uiPath))) {
            case None => ()
            case Some(root) =>
                if (root.kind == 0) {
                    match (root.obj.get("界面消息")) {
                        case None => ()
                        case Some(section) =>
                            if (section.kind == 0) {
                                for (k in section.obj.keys()) {
                                    ui.add(normalizeKey(k), jstr(section, k).getOrThrow())
                                }
                            }
                    }
                    match (root.obj.get("测试输出")) {
                        case None => ()
                        case Some(section) =>
                            if (section.kind == 0) {
                                for (k in section.obj.keys()) {
                                    testDict.add(normalizeKey(k), jstr(section, k).getOrThrow())
                                }
                            }
                    }
                }
        }
    }

    let modulePaths = HashMap<String, String>()
    let aliases = HashMap<String, String>()
    let mpPath = "${packRoot}/module_paths.json"
    if (exists(Path(mpPath))) {
        match (parseJsonValue(readTextFile(mpPath))) {
            case None => ()
            case Some(root) =>
                if (root.kind == 0) {
                    match (root.obj.get("模块路径")) {
                        case None => ()
                        case Some(section) =>
                            if (section.kind == 0) {
                                for (k in section.obj.keys()) {
                                    modulePaths.add(normalizeKey(k), jstr(section, k).getOrThrow())
                                }
                            }
                    }
                }
        }
    }
    let slPath = "${packRoot}/stdlib.json"
    if (exists(Path(slPath))) {
        match (parseJsonValue(readTextFile(slPath))) {
            case None => ()
            case Some(root) =>
                if (root.kind == 0) {
                    match (root.obj.get("模块路径")) {
                        case None => ()
                        case Some(section) =>
                            if (section.kind == 0) {
                                for (k in section.obj.keys()) {
                                    modulePaths.add(normalizeKey(k), jstr(section, k).getOrThrow())
                                }
                            }
                    }
                    match (root.obj.get("标识符")) {
                        case None => ()
                        case Some(section) =>
                            if (section.kind == 0) {
                                for (k in section.obj.keys()) {
                                    aliases.add(normalizeKey(k), jstr(section, k).getOrThrow())
                                }
                            }
                    }
                }
        }
    }

    // 阶段 2b：crates/ 第三方库映射（JSON 编码语言包；最后加载覆盖，含宏节）
    loadCratesJson(packRoot, modulePaths, aliases, macros)

    let diagKinds = HashMap<String, DiagEntry>()
    let msgEntries = HashMap<String, DiagEntry>()
    let errPath = "${packRoot}/errors.json"
    if (exists(Path(errPath))) {
        match (parseJsonValue(readTextFile(errPath))) {
            case None => ()
            case Some(root) =>
                if (root.kind == 0) {
                    for (secName in root.obj.keys()) {
                        let sec = root.obj.get(secName).getOrThrow()
                        if (sec.kind != 0) {
                            continue
                        }
                        for (entryKey in sec.obj.keys()) {
                            let fields = sec.obj.get(entryKey).getOrThrow()
                            if (fields.kind != 0) {
                                continue
                            }
                            let entry = DiagEntry(jstrOr(fields, "消息模板"),
                                                  jstrOr(fields, "教学提示"),
                                                  jstrOr(fields, "修复示例"))
                            if (secName == "诊断码") {
                                diagKinds.add(normalizeKey(entryKey), entry)
                            } else {
                                msgEntries.add(normalizeKey(entryKey), entry)
                            }
                        }
                    }
                }
        }
    }

    return LangPack(code, name, extensions, keywords, macros, modulePaths, aliases, diagKinds, msgEntries, ui, testDict)
}

/** JSON 对象节点取字符串字段；字段缺失/非字符串返回 None。 */
public func jstr(node: JsonNode, key: String): ?String {
    match (node.obj.get(key)) {
        case None => return None
        case Some(v) =>
            if (v.kind != 1) {
                return None
            }
            return v.str
    }
}

/** jstr 的容错版：缺失/非字符串时返回空串（与 entryOf 语义一致）。 */
private func jstrOr(node: JsonNode, key: String): String {
    match (jstr(node, key)) {
        case None => return ""
        case Some(v) => return v
    }
}

/**
 * 映射键加载时归一（§16.7）：运行期查表零归一开销。
 * 注：仓颉 1.0 std.unicode 无 normalize/isNormalized（实测，§13.1 第 34 条），
 * 此处为可插拔点：未来标准库提供 NFC 时替换实现即可，调用方不变。
 */
public func normalizeKey(k: String): String {
    return k
}

/** 从条目字段表构建 DiagEntry（缺字段用空串）。 */
private func entryOf(fields: HashMap<String, String>): DiagEntry {
    let t = fields.get("消息模板")
    let tip = fields.get("教学提示")
    let fix = fields.get("修复示例")
    var template = ""
    if (t != None) {
        template = t.getOrThrow()
    }
    var tipText = ""
    if (tip != None) {
        tipText = tip.getOrThrow()
    }
    var fixText = ""
    if (fix != None) {
        fixText = fix.getOrThrow()
    }
    return DiagEntry(template, tipText, fixText)
}

/**
 * 方言/界面语言选择（§5.5 升级 2026-09：语言无关化，向 i18n 迈进）。
 * 环境变量 ZHCLANG 指定语言包代码（如 ru/en/ja…），未设置或为空回退 "zh"。
 * 支持任意国家母语编写仓颉：提供对应 lang-packs/<代码>/ 语言包即可，
 * 转译/反向转译/诊断翻译/类型本地化全部由所选语言包驱动。
 */
public func resolveLang(): String {
    let v = getVariable("ZHCLANG")
    match (v) {
        case None => return "zh"
        case Some(s) =>
            if (s.isEmpty()) {
                return "zh"
            }
            return s
    }
}

/**
 * P-2 扩展名反查（i18n 2026-09）：目标文件扩展名命中某已安装语言包
 * lang_info.toml 的“扩展名”声明（支持逗号分隔多值）时返回该语言代码，
 * 否则 None。候选根与 packRootCandidates 一致（env → 当前目录 →
 * 可执行文件旁 → ~/.zhc）；同名冲突由 ecosystem install 的扩展名冲突
 * 校验保证实际唯一。任何读取/解析失败静默跳过（返回 None）。
 */
public func langCodeByExt(path: String, bases: ArrayList<String>): ?String {
    let dotOpt = path.lastIndexOf(".")
    if (dotOpt == None) {
        return None
    }
    let dot = dotOpt.getOrThrow()
    if (dot + 1 >= path.size) {
        return None
    }
    let ext = path[dot + 1..path.size]
    if (ext.isEmpty()) {
        return None
    }
    for (base in bases) {
        let packsDir = "${base}/lang-packs"
        if (!exists(Path(packsDir))) {
            continue
        }
        try {
            var codes = ArrayList<String>()
            for (f in Directory.readFrom(packsDir)) {
                if (f.isDirectory()) {
                    codes.add(f.name)
                }
            }
            sort(codes)   // 确定性（坑 ①）：目录序参与扩展名归属判定
            for (code in codes) {
                let infoPath = "${packsDir}/${code}/lang_info.toml"
                if (!exists(Path(infoPath))) {
                    continue
                }
                let info = parseToml(readTextFile(infoPath))
                match (info.get("语言包")) {
                    case None => ()
                    case Some(section) =>
                        let vExt = section.get("扩展名")
                        if (vExt != None) {
                            for (e in vExt.getOrThrow().split(",")) {
                                if (e.trimAscii() == ext) {
                                    return Some(code)
                                }
                            }
                        }
                }
            }
        } catch (e: Exception) {
            ()   // 某根解析失败 → 静默试下一候选根
        }
    }
    return None
}

/**
 * P-2 文件级语言决议：单文件命令（run/check/eject/compare/lint/fmt/expand）
 * 按目标文件扩展名优先选语言——VS Code 扩展与终端均可直接运行各母语方言
 * 文件而无需手设 ZHCLANG；目录/项目参数无扩展名时回退环境决议（workspace
 * 内按单语言处理，与 resolveLangPack 同链）。
 */
public func resolveLangForFile(path: String): String {
    match (langCodeByExt(path, packRootCandidates())) {
        case None => return resolveLang()
        case Some(code) => return code
    }
}

/** 读取文本文件（UTF-8）。文件不存在/不可读时抛异常。 */
public func readTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

/**
 * 加载语言包 crates/ 目录的第三方库映射（TOML 编码，§10/s5t9b）。
 * 与 stdlib.toml 同格式（["模块路径"] + ["标识符"] 两节）；文件名即库展示名；
 * 名字排序保证确定性（坑 ①），最后加载覆盖同名键（社区映射优先）。
 */
private func loadCratesToml(packRoot: String, modulePaths: HashMap<String, String>,
                            aliases: HashMap<String, String>, macros: HashMap<String, String>): Unit {
    let cratesDir = "${packRoot}/crates"
    if (!exists(Path(cratesDir))) {
        return
    }
    let names = ArrayList<String>()
    for (f in Directory.readFrom(cratesDir)) {
        if (!f.isDirectory() && f.name.endsWith(".toml")) {
            names.add(f.name)
        }
    }
    sort(names)
    for (name in names) {
        let tables = parseToml(readTextFile("${cratesDir}/${name}"))
        match (tables.get("模块路径")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    modulePaths.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
        match (tables.get("标识符")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    aliases.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
        match (tables.get("宏")) {
            case None => ()
            case Some(section) =>
                for (k in section.keys()) {
                    macros.add(normalizeKey(k), section.get(k).getOrThrow())
                }
        }
    }
}

/** 加载 crates/ 目录的第三方库映射（JSON 编码语言包，§16.7）。 */
private func loadCratesJson(packRoot: String, modulePaths: HashMap<String, String>,
                            aliases: HashMap<String, String>, macros: HashMap<String, String>): Unit {
    let cratesDir = "${packRoot}/crates"
    if (!exists(Path(cratesDir))) {
        return
    }
    let names = ArrayList<String>()
    for (f in Directory.readFrom(cratesDir)) {
        if (!f.isDirectory() && f.name.endsWith(".json")) {
            names.add(f.name)
        }
    }
    sort(names)
    for (name in names) {
        match (parseJsonValue(readTextFile("${cratesDir}/${name}"))) {
            case None => ()
            case Some(root) =>
                if (root.kind != 0) {
                    continue
                }
                match (root.obj.get("模块路径")) {
                    case None => ()
                    case Some(section) =>
                        if (section.kind == 0) {
                            for (k in section.obj.keys()) {
                                modulePaths.add(normalizeKey(k), jstr(section, k).getOrThrow())
                            }
                        }
                }
                match (root.obj.get("标识符")) {
                    case None => ()
                    case Some(section) =>
                        if (section.kind == 0) {
                            for (k in section.obj.keys()) {
                                aliases.add(normalizeKey(k), jstr(section, k).getOrThrow())
                            }
                        }
                }
                match (root.obj.get("宏")) {
                    case None => ()
                    case Some(section) =>
                        if (section.kind == 0) {
                            for (k in section.obj.keys()) {
                                macros.add(normalizeKey(k), jstr(section, k).getOrThrow())
                            }
                        }
                }
        }
    }
}

// ============ 全局界面文案上下文（§5.5 扩展，2026-09） ============
// 入口 resolveLangPack 成功后调用 setUiLang；此后全部 UI 输出经
// uiText/uiTextF 查询当前语言包 ["界面消息"] 表——zh 语言包界面消息跟随方言，
// en/ru 等语言包提供同键翻译；缺键时回退 key 本身（zh 原文模板），保证
// 「用户用什么语言写代码，工具就用什么语言提示」。
var uiLang: ?LangPack = None
// P-3 运行时三级回退（demo 档缺键 → en → zh 原文）：
// demo 档生成物滞后于源码新增键时，回退 en 包（门禁保证 en 与源码键集对齐），
// 避免非中文用户直接看到中文模板串；en/zh 自身缺键回退 key（zh 模板即 key）。
var uiEnFallback: ?LangPack = None

public func setUiLang(lang: LangPack) {
    uiLang = lang
}

/** 设置界面语言并加载同根目录 en 包作为兜底（resolveLangPack 成功路径调用）。 */
public func setUiLangWithRoot(lang: LangPack, packRoot: String) {
    uiLang = lang
    if (lang.code == "en" || lang.code == "zh") {
        uiEnFallback = None
        return
    }
    match (loadLangPack(packRoot, "en")) {
        case None => uiEnFallback = None
        case Some(en) => uiEnFallback = en
    }
}

/** 界面文案（无占位）：当前语言 → en 兜底（demo 档）→ zh 原文（key）。 */
public func uiText(key: String): String {
    match (uiLang) {
        case None => return key
        case Some(l) =>
            match (l.ui.get(key)) {
                case Some(v) => return v
                case None => ()
            }
            if (l.code != "en" && l.code != "zh") {
                match (uiEnFallback) {
                    case None => ()
                    case Some(en) =>
                        match (en.ui.get(key)) {
                            case Some(ev) => return ev
                            case None => ()
                        }
                }
            }
            return key
    }
}

/** 界面文案（{0}/{1}…占位顺序替换）：跟随当前语言包；缺键回退 key 模板本身。 */
public func uiTextF(key: String, parts: Array<String>): String {
    var out = uiText(key)
    for (i in 0..parts.size) {
        out = out.replace("{${i}}", parts[i])
    }
    return out
}
