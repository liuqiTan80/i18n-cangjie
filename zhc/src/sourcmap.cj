package zhc

import std.collection.*
import std.convert.*

/**
 * 源映射（设计 §5.6 实现版）：转译产物 .cj 坐标 → 方言源码 .zc 坐标。
 *
 * 三阶段管线（词法 → import 路径 → 别名）各自记录替换条目，统一折算到
 * 源文本基准后构建 SourceMap；诊断位置（cjc JSON 的 Line/Column 或 LSP
 * publishDiagnostics 的 range）经 mapBack 反向还原到方言源码坐标。
 *
 * 偏移单位：UTF-16 code unit（与 LSP 位置体系一致，§5.6）。仓颉 String
 * 按 Rune 索引，实现时逐字符累计换算；非 BMP 码点（> r'\u{FFFF}'）计 2。
 *
 * 1.0 适配记录（本机 cjc 1.0.5 实测）：
 *   - Rune 无 toInt64/toUInt32，非 BMP 判断用 Rune 字面量 r'\u{FFFF}' 比较；
 *   - Int64.parse 在 std.convert（import std.convert.* 后可用），解析失败抛异常；
 *   - Array 构造第二参数为初始化函数：Array<UInt8>(n, { _ => 0 })。
 */

/** 字符串的 Rune（码点）数。 */
public func runeLenOf(s: String): Int64 {
    return s.toRuneArray().size
}

/** 字符串的 UTF-16 code unit 数（非 BMP 码点计 2）。 */
public func utf16LenOf(s: String): Int64 {
    var n: Int64 = 0
    for (r in s.toRuneArray()) {
        n += if (r > r'\u{FFFF}') { 2 } else { 1 }
    }
    return n
}

/** 单个 Rune 的 UTF-16 单元数。 */
private func utf16Units(r: Rune): Int64 {
    return if (r > r'\u{FFFF}') { 2 } else { 1 }
}

/**
 * 偏移反推：把"变换后文本"的 Rune 偏移换算为"变换前文本"偏移。
 * entries 描述一组不重叠的替换（offset 为变换前基准，升序）：
 * 输出偏移 X 落在某条目替换区间内 → 映射到该条目起点（超长钳制）；
 * 否则 X 减去此前全部替换的长度差。
 * 用于把阶段 2/3 条目的偏移折算回源文本基准（§4.3 源映射合并）。
 */
public func backShift(entries: ArrayList<MapEntry>, dstOff: Int64): Int64 {
    var delta: Int64 = 0
    var result = dstOff
    for (e in entries) {
        let outStart = e.offset + delta
        if (dstOff < outStart) {
            break
        }
        let outEnd = outStart + runeLenOf(e.replacement)
        if (dstOff < outEnd) {
            var inOff = dstOff - outStart
            let srcLen = runeLenOf(e.original)
            if (inOff > srcLen) {
                inOff = srcLen
            }
            return e.offset + inOff
        }
        delta += runeLenOf(e.replacement) - runeLenOf(e.original)
        result = dstOff - delta
    }
    return result
}

/**
 * 合并三阶段条目到源基准：词法条目（源基准）原样；import 条目（输入1 基准）
 * 经 backShift(词法条目) 折算；别名条目（输入2 基准）先折到输入1 再折到源。
 * 输出保持按源偏移升序（各阶段折算后与词法条目交错，须两两归并——
 * 早期实现直接三段 append，SourceMap 构造器（升序假设）取词错位）。
 */
public func mergeMaps(map1: ArrayList<MapEntry>, map2: ArrayList<MapEntry>,
                      map3: ArrayList<MapEntry>): ArrayList<MapEntry> {
    let m2s = ArrayList<MapEntry>()
    for (e in map2) {
        m2s.add(MapEntry(backShift(map1, e.offset), e.len, e.original, e.replacement))
    }
    let pass2 = mergeSorted(map1, m2s)
    let m3s = ArrayList<MapEntry>()
    for (e in map3) {
        let mid = backShift(map2, e.offset)
        m3s.add(MapEntry(backShift(map1, mid), e.len, e.original, e.replacement))
    }
    return mergeSorted(pass2, m3s)
}

/** 两个按 offset 升序的条目序列归并（同值取 a，稳定）。 */
private func mergeSorted(a: ArrayList<MapEntry>, b: ArrayList<MapEntry>): ArrayList<MapEntry> {
    let out = ArrayList<MapEntry>()
    var i: Int64 = 0
    var j: Int64 = 0
    while (i < a.size && j < b.size) {
        if (a[i].offset <= b[j].offset) {
            out.add(a[i])
            i += 1
        } else {
            out.add(b[j])
            j += 1
        }
    }
    while (i < a.size) {
        out.add(a[i])
        i += 1
    }
    while (j < b.size) {
        out.add(b[j])
        j += 1
    }
    return out
}

/** 折算到 UTF-16 后的映射条目（源/目标双侧坐标）。 */
public class UEntry {
    public var srcStart16: Int64
    public var srcLen16: Int64
    public var dstStart16: Int64
    public var dstLen16: Int64
    public var cumDelta: Int64      // 到该条目为止的目标-源累计长度差

    public init(srcStart16: Int64, srcLen16: Int64, dstStart16: Int64, dstLen16: Int64, cumDelta: Int64) {
        this.srcStart16 = srcStart16
        this.srcLen16 = srcLen16
        this.dstStart16 = dstStart16
        this.dstLen16 = dstLen16
        this.cumDelta = cumDelta
    }
}

/** 每行起始偏移表（UTF-16）。 */
private func lineStarts16(text: String): ArrayList<Int64> {
    let out = ArrayList<Int64>()
    out.add(0)
    var u16: Int64 = 0
    for (r in text.toRuneArray()) {
        if (r == r'\n') {
            out.add(u16 + 1)
        }
        u16 += utf16Units(r)
    }
    return out
}

/**
 * 源映射：目标文本（转译产物）坐标 → 源文本（方言源码）坐标。
 * 构造时把三阶段条目换算为 UTF-16 坐标并构建双侧行起始表；
 * mapBack(line, col)（1-based，UTF-16）返回 (源行, 源列)。
 */
public class SourceMap {
    public var srcText: String
    public var dstText: String
    public var ents: ArrayList<UEntry>
    public var srcLines: ArrayList<Int64>
    public var dstLines: ArrayList<Int64>

    public init(srcText: String, dstText: String, map: ArrayList<MapEntry>) {
        this.srcText = srcText
        this.dstText = dstText
        let srcRunes = srcText.toRuneArray()
        let ents = ArrayList<UEntry>()
        var cursor: Int64 = 0        // 已处理源 Rune 游标
        var u16: Int64 = 0           // 源 UTF-16 游标
        var delta: Int64 = 0         // 目标 UTF-16 - 源 UTF-16 累计
        for (e in map) {
            // 推进游标到条目起点（条目按源偏移升序）
            while (cursor < e.offset) {
                u16 += utf16Units(srcRunes[cursor])
                cursor += 1
            }
            let srcStart = u16
            let srcLen = utf16LenOf(e.original)
            let dstStart = srcStart + delta
            let dstLen = utf16LenOf(e.replacement)
            let nextDelta = delta + dstLen - srcLen
            ents.add(UEntry(srcStart, srcLen, dstStart, dstLen, nextDelta))
            delta = nextDelta
            u16 += srcLen
            cursor += runeLenOf(e.original)
        }
        this.ents = ents
        this.srcLines = lineStarts16(srcText)
        this.dstLines = lineStarts16(dstText)
    }

    /** 目标行列（1-based，UTF-16）→ 源行列（1-based，UTF-16）。 */
    public func mapBack(line: Int64, col: Int64): (Int64, Int64) {
        let li = line - 1
        if (li < 0 || li >= this.dstLines.size) {
            return (line, col)
        }
        var dstAbs = this.dstLines[li] + (col - 1)
        if (dstAbs < 0) {
            dstAbs = 0
        }
        let srcAbs = this.backAbs(dstAbs)
        // 二分源行起始表：最后一个 <= srcAbs
        var lo: Int64 = 0
        var hi: Int64 = this.srcLines.size - 1
        var row: Int64 = 0
        while (lo <= hi) {
            let mid = (lo + hi) / 2
            if (this.srcLines[mid] <= srcAbs) {
                row = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return (row + 1, srcAbs - this.srcLines[row] + 1)
    }

    /** 目标绝对偏移（UTF-16）→ 源绝对偏移：二分定位最后一条起点 ≤ 目标的条目，
     * 命中区间内按等宽折算（超长钳制），间隙按累计长度差平移。 */
    private func backAbs(dstAbs: Int64): Int64 {
        var lo: Int64 = 0
        var hi: Int64 = this.ents.size - 1
        var best: Int64 = -1
        while (lo <= hi) {
            let mid = (lo + hi) / 2
            if (this.ents[mid].dstStart16 <= dstAbs) {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if (best < 0) {
            return dstAbs
        }
        let e = this.ents[best]
        if (dstAbs < e.dstStart16 + e.dstLen16) {
            var inOff = dstAbs - e.dstStart16
            if (inOff > e.srcLen16) {
                inOff = e.srcLen16
            }
            return e.srcStart16 + inOff
        }
        return dstAbs - e.cumDelta
    }
}

/**
 * 诊断位置定位器：按目标产物路径（cjc JSON 的 Location.File / LSP 的 uri）
 * 查找源映射，把行列还原为方言源码坐标；未注册路径原样透传（回退不崩溃）。
 */
public class DiagLocator {
    public var maps: HashMap<String, SourceMap>    // 目标产物路径 → 源映射
    public var srcs: HashMap<String, String>       // 目标产物路径 → 源文件显示路径

    public init(maps: HashMap<String, SourceMap>, srcs: HashMap<String, String>) {
        this.maps = maps
        this.srcs = srcs
    }

    /** 解析诊断位置：返回 (显示路径, 显示行, 显示列)；无映射或解析失败原样。 */
    public func resolve(file: String, line: String, col: String): (String, String, String) {
        let src = this.srcs.get(file)
        match (src) {
            case None =>
                return (file, line, col)
            case Some(srcPath) =>
                let sm = this.maps.get(file)
                match (sm) {
                    case None =>
                        return (srcPath, line, col)
                    case Some(m) =>
                        try {
                            let l = Int64.parse(line)
                            let c = Int64.parse(col)
                            let (rl, rc) = m.mapBack(l, c)
                            return (srcPath, rl.toString(), rc.toString())
                        } catch (e: Exception) {
                            return (srcPath, line, col)
                        }
                }
        }
    }
}
