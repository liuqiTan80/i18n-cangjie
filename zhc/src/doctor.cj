package zhc

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.process.*

/**
 * zhc doctor（易用性 P0，全球化路线图 ①-6）：环境一键自检。
 *
 * 检查项（按新手第一次报错的频率排序）：
 *   ① 编译器 cjc（SDK 是否安装/版本是否匹配）
 *   ② 构建器 cjpm（tools/bin 是否在 PATH）
 *   ③ 语言包定位（定位链 ZHC_LANG_PACKS → ./lang-packs → exe 旁 → ~/.zhc）
 *      附档位/界面覆盖率（来自 lang_info.toml 的 schema 1 声明）
 *   ④ 工作目录可写（.zhc 编译缓存与产物的前提）
 *   ⑤ 共享源可达（share fetch/publish 的前提；⚠ 级——离线使用不受影响）
 *   ⑥ cjlint（可选：zhc lint 的 cjlint 集成）
 *
 * 退出码：失败（✗）计 1；警告（⚠）不计——SDK/语言包是硬前提，共享源与
 * cjlint 缺失只影响部分功能。每项失败都给出母语化修复指引（uiText）。
 */

/** 单项检查结果：状态（通过/失败/警告）+ 文案（已本地化）。 */
struct DoctorItem {
    var ok: Bool
    var warn: Bool
    var text: String

    init(ok: Bool, warn: Bool, text: String) {
        this.ok = ok
        this.warn = warn
        this.text = text
    }
}

/** 读语言包元信息里的档位声明（schema 1）；缺省返回 "未声明"。 */
func doctorReadMeta(infoPath: String, key: String): String {
    try {
        let tables = parseToml(readTextFile(infoPath))
        match (tables.get("语言包")) {
            case None => ()
            case Some(section) =>
                let v = section.get(key)
                if (v != None) {
                    return v.getOrThrow()
                }
        }
    } catch (e: Exception) {
        return "未声明"
    }
    return "未声明"
}

/** ①② SDK：cjc 版本 + cjpm 可用性。 */
func doctorCheckSdk(items: ArrayList<DoctorItem>): Unit {
    let v = probeCjcVersion()
    if (v == None) {
        items.add(DoctorItem(false, false, uiText("✗ 未找到编译器 cjc：请 source 仓颉 SDK 的 envsetup.sh（或设置 CANGJIE_HOME 与 PATH，见 README ②）")))
    } else {
        let home = getVariable("CANGJIE_HOME")
        let homeText = if (home == None || home.getOrThrow().isEmpty()) { "?" } else { home.getOrThrow() }
        items.add(DoctorItem(true, false, uiTextF("✓ 编译器 cjc {0}（CANGJIE_HOME={1}）", [v.getOrThrow(), homeText])))
    }
    let (code, _, _) = executeWithOutput("cjpm", ["--version"])
    if (code == 0) {
        items.add(DoctorItem(true, false, uiText("✓ 构建器 cjpm 可用")))
    } else {
        items.add(DoctorItem(false, false, uiText("✗ 未找到 cjpm：SDK 的 tools/bin 目录需在 PATH（见 README ②）")))
    }
}

/** ③ 语言包定位 + 档位显示。返回找到的包代码（未找到返回空串）。 */
func doctorCheckLangPack(items: ArrayList<DoctorItem>): String {
    let lang = resolveLang()
    for (base in packRootCandidates()) {
        let loaded = loadLangPack(base, lang)
        match (loaded) {
            case None => ()
            case Some(pack) =>
                let infoPath = "${base}/lang-packs/${lang}/lang_info.toml"
                let tier = doctorReadMeta(infoPath, "档位")
                let cov = doctorReadMeta(infoPath, "界面覆盖率")
                items.add(DoctorItem(true, false, uiTextF("✓ 语言包 {0}（{1}，档位 {2}，界面 {3}，来源 {4}）",
                    [lang, pack.name, tier, cov, base])))
                return lang
        }
    }
    items.add(DoctorItem(false, false, uiTextF("✗ 未找到语言包 {0}：设置 ZHC_LANG_PACKS，在当前目录提供 lang-packs/{0}，或安装到 ~/.zhc/lang-packs", [lang])))
    return ""
}

/** ④ 工作目录可写（.zhc 缓存前提）。 */
func doctorCheckWorkdir(items: ArrayList<DoctorItem>): Unit {
    let probe = "./.zhc-doctor-probe"
    try {
        File.writeTo(Path(probe), "probe".toArray())
        removeFileBestEffort(probe)
        items.add(DoctorItem(true, false, uiText("✓ 工作目录可写（.zhc 编译缓存可用）")))
    } catch (e: Exception) {
        items.add(DoctorItem(false, false, uiText("✗ 当前目录不可写：无法生成 .zhc 编译缓存——换到可写目录或检查权限")))
    }
}

/** ⑤ 共享源可达（⚠ 级：离线使用不受影响）。 */
func doctorCheckShare(items: ArrayList<DoctorItem>): Unit {
    try {
        let text = shareReadIndex(DEFAULT_SHARE_BASE)
        let entries = parseShareIndex(text)
        items.add(DoctorItem(true, false, uiTextF("✓ 共享源可达（{0} 个映射，{1}）",
            [entries.size.toString(), DEFAULT_SHARE_BASE])))
    } catch (e: Exception) {
        items.add(DoctorItem(true, true, uiTextF("⚠ 共享源不可达：{0}（离线使用不受影响；可用 ZHC_SHARE_BASE 指向本地目录或自建 share_server）", [e.message])))
    }
}

/** ⑥ cjlint（可选：zhc lint 的 cjlint 集成）。 */
func doctorCheckCjlint(items: ArrayList<DoctorItem>): Unit {
    let (code, _, _) = executeWithOutput("bash", ["-c", "command -v cjlint"])
    if (code == 0) {
        items.add(DoctorItem(true, false, uiText("✓ cjlint 可用（zhc lint 集成就绪）")))
    } else {
        items.add(DoctorItem(true, true, uiText("⚠ cjlint 未检出：zhc lint 的 cjlint 集成不可用（其余命令不受影响）")))
    }
}

/** doctor 入口：跑全部检查并汇总。返回码：有失败（✗）= 1，否则 0。 */
public func cmdDoctor(args: Array<String>): Int64 {
    println(uiText("zhc doctor（环境自检）："))
    let items = ArrayList<DoctorItem>()
    doctorCheckSdk(items)
    let lang = doctorCheckLangPack(items)
    doctorCheckWorkdir(items)
    doctorCheckShare(items)
    doctorCheckCjlint(items)
    var pass = 0
    var fail = 0
    var warn = 0
    for (item in items) {
        println(item.text)
        if (item.warn) {
            warn += 1
        } else if (item.ok) {
            pass += 1
        } else {
            fail += 1
        }
    }
    println(uiTextF("结果：{0} 通过 / {1} 失败 / {2} 警告（语言包 {3}）",
        [pass.toString(), fail.toString(), warn.toString(), if (lang.isEmpty()) { "-" } else { lang }]))
    return if (fail > 0) { 1 } else { 0 }
}
