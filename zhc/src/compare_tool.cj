package zhc

import std.fs.*

/**
 * compare（③ 方言↔官方对照视图的数据源）：转译 .zc → 官方 .cj，
 * 把对照 JSON 输出到 stdout，供 VS Code 扩展双栏对照视图渲染
 * （lib/compare.js，词级成对高亮 + 逐行对齐）。
 *
 * 输出为单行 JSON（行帧友好，扩展侧 JSON.parse 即可）：
 *   {
 *     "file": <原文件路径>,
 *     "dialect": <方言源码全文>,      // 转义后单行
 *     "official": <官方转译全文>,
 *     "pairs": [ [s, sl, d, dl], ... ]  // 词对；坐标 = UTF-16 code unit
 *   }
 * 每对四元组（转译实际替换处，源/目标双侧绝对偏移）：
 *   s/sl = dialect 中原文词区间 [s, s+sl)，d/dl = official 中译文词区间 [d, d+dl)。
 * 区间由 SourceMap 折算（三阶段管线条目统一源基准 + UTF-16 换算），
 * 扩展侧用 String.slice（同为 UTF-16 单位）直接取词，无需再换算。
 * 行结构：转译逐 token 保行，两侧行数一致（词对绝不跨行）。
 */
public func cmdCompare(path: String): Int64 {
    let lang = resolveLangPack(resolveLang())
    if (!exists(Path(path))) {
        println(uiTextF("文件不存在：{0}", [path]))
        return 1
    }
    let srcRaw = readTextFile(path)
    // ⑥a 用户宏展开：对照视图展示宏展开后的方言（与编译链一致）
    let expOpt = expandUserMacros(srcRaw, lang, path)
    if (expOpt == None) {
        return 1
    }
    let src = expOpt.getOrThrow()
    let result = transpileFull(src, lang)
    // 双侧 UTF-16 坐标 + 行起始表由 SourceMap 一次构造（diagnostic 同源换算）
    let sm = SourceMap(src, result.text, result.map)
    var sb = "{\"file\":${jsonQuote(path)}"
    sb = "${sb},\"dialect\":${jsonQuote(src)}"
    sb = "${sb},\"official\":${jsonQuote(result.text)}"
    sb = "${sb},\"pairs\":["
    var first = true
    for (e in sm.ents) {
        if (!first) {
            sb = "${sb},"
        }
        first = false
        sb = "${sb}[${e.srcStart16.toString()},${e.srcLen16.toString()},${e.dstStart16.toString()},${e.dstLen16.toString()}]"
    }
    sb = "${sb}]}"
    println(sb)
    return 0
}
