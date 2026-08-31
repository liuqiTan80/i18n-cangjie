package zhc

import std.process.*

/**
 * 工具链版本探测（设计 §3.10、§8）：`cjc --version` 动态解析版本号，
 * 供 init 写入 cjpm.toml 的 cjc-version 必需字段（不可硬编码，对应蓝图坑 ⑬）。
 *
 * 1.0 实测输出格式（本机 cjc 1.0.5）：
 *   Cangjie Compiler: 1.0.5 (cjnative)
 *   Target: x86_64-unknown-linux-gnu
 */

/** 探测 cjc 版本号（如 "1.0.5"）；cjc 不可用或输出无法解析时返回 None。 */
public func probeCjcVersion(): ?String {
    let (code, outB, _) = executeWithOutput("cjc", ["--version"])
    if (code != 0) {
        return None
    }
    let text = String.fromUtf8(outB)
    let marker = "Cangjie Compiler:"
    for (line in text.split("\n")) {
        let idxOpt = line.indexOf(marker)
        if (idxOpt == None) {
            continue
        }
        // marker 为纯 ASCII，字节偏移 == Rune 偏移（切片边界安全）
        let runes = line.toRuneArray()
        var j = idxOpt.getOrThrow() + marker.size
        while (j < runes.size && isAsciiSpace(runes[j])) {
            j += 1
        }
        var k = j
        while (k < runes.size && (runes[k].isAsciiNumber() || runes[k] == r'.')) {
            k += 1
        }
        if (k > j) {
            return String(runes[j..k])
        }
    }
    return None
}

private func isAsciiSpace(r: Rune): Bool {
    return r == r' ' || r == r'\t' || r == r'\r' || r == r'\n'
}
