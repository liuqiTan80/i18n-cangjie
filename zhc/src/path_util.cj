package zhc

import std.fs.*
import std.env.*
import std.collection.*

/**
 * 项目根定位（设计 §8、§2.3 util/path.cj）：从源文件所在目录向上逐级
 * 查找 cjpm.toml；找不到返回 None（调用方给出 init 引导）。
 *
 * 注意：lastIndexOf 返回字节偏移（1.0 实测），但 '/' 为纯 ASCII，
 * 且其左侧均为目录路径字节，切片边界安全（与 baseNameOf 同理）。
 *
 * 相对路径处理：dirOf 对 "../x.zc" 返回 ".."；findProjectRoot 用 PWD
 * 把相对起始目录转绝对（否则 "." 的父目录是自身，无法向上查找）。
 */

/** 路径的目录部分；无目录分隔符时返回 "."。 */
public func dirOf(path: String): String {
    let slashOpt = path.lastIndexOf("/")
    if (slashOpt == None) {
        return "."
    }
    let slash = slashOpt.getOrThrow()
    if (slash == 0) {
        return "/"
    }
    let dir = path[0..slash]
    if (dir == "." && path.startsWith("../")) {
        return ".."   // "../x.zc" 的目录是 ".." 而非 "."
    }
    return dir
}

/** 父目录；根目录或 "." 的父目录是其自身（向上查找终止条件）。 */
public func parentDir(dir: String): String {
    if (dir == "/" || dir == ".") {
        return dir
    }
    let slashOpt = dir.lastIndexOf("/")
    if (slashOpt == None) {
        return "."
    }
    let slash = slashOpt.getOrThrow()
    if (slash == 0) {
        return "/"
    }
    return dir[0..slash]
}

/** 从 startDir 向上查找含 cjpm.toml 的项目根；找不到返回 None。 */
public func findProjectRoot(startDir: String): ?String {
    var dir = startDir
    // 相对路径基于 PWD 转绝对（保证向上查找可达父目录）
    if (!dir.startsWith("/")) {
        let pwd = getVariable("PWD")
        if (pwd != None && !pwd.getOrThrow().isEmpty()) {
            dir = normalizePath("${pwd.getOrThrow()}/${dir}")
        }
    }
    while (true) {
        if (exists(Path("${dir}/cjpm.toml"))) {
            return dir
        }
        let up = parentDir(dir)
        if (up == dir) {
            return None
        }
        dir = up
    }
    return None   // 不可达：终止条件在循环内（编译器要求全路径返回）
}

/** 规范化路径：解析 "." 与 ".." 段（供 PWD 拼接后使用）。 */
public func normalizePath(path: String): String {
    let absolute = path.startsWith("/")
    let parts = path.split("/")
    let stack = ArrayList<String>()
    for (p in parts) {
        if (p.isEmpty() || p == ".") {
            continue
        } else if (p == "..") {
            if (!stack.isEmpty()) {
                stack.remove(stack.size - 1..stack.size)   // 1.0：remove 仅接受 Range
            }
        } else {
            stack.add(p)
        }
    }
    var sb = ""
    for (p in stack) {
        sb = if (sb.isEmpty()) { p } else { "${sb}/${p}" }
    }
    return if (absolute) { "/${sb}" } else { if (sb.isEmpty()) { "." } else { sb } }
}
