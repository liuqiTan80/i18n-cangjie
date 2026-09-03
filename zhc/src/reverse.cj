package zhc

import std.collection.*
import std.sort.*

/**
 * 反向映射构建（设计 §5.1 第 7 条、§7.3）：官方词 → 母语候选列表。
 * 用途：eject 碰撞报告（本阶段）、诊断类型名本地化（阶段 3 复用）。
 *
 * 确定性要求（§6.3）：先收集键排序再遍历（HashMap 迭代顺序不确定），
 * 碰撞报告按官方词排序输出，保证多轮执行结果稳定。
 *
 * 碰撞语义（§5.1 第 7 条）：同一官方词对应多个母语词（如 `是`/`属于` 都映射
 * is）时，反向展示存在歧义，报告并采用"首个命中"策略。
 */

public class ReverseMap {
    public var entries: HashMap<String, ArrayList<String>>
    public var collisions: ArrayList<String>

    public init(entries: HashMap<String, ArrayList<String>>, collisions: ArrayList<String>) {
        this.entries = entries
        this.collisions = collisions
    }
}

/** 构建反向映射；同一官方词对应多个母语词时生成碰撞警告行。
 *  阶段 2：并入别名表（stdlib.toml 标识符），官方词与关键字表重叠时优先关键字表。 */
public func buildReverseMap(keywords: HashMap<String, String>, macros: HashMap<String, String>, aliases: HashMap<String, String>): ReverseMap {
    let entries = HashMap<String, ArrayList<String>>()
    let collisions = ArrayList<String>()

    // 合并源表键（关键字表 + 宏表 + 别名表）并去重，排序保证确定性（§6.3）
    let keySet = HashSet<String>()
    for (k in keywords.keys()) {
        keySet.add(k)
    }
    for (k in macros.keys()) {
        keySet.add(k)
    }
    for (k in aliases.keys()) {
        keySet.add(k)
    }
    let allKeys = ArrayList<String>()
    for (k in keySet) {
        allKeys.add(k)
    }
    sort(allKeys)

    for (dialect in allKeys) {
        let kw = keywords.get(dialect)
        var official = ""
        if (kw != None) {
            official = kw.getOrThrow()
        } else {
            let mac = macros.get(dialect)
            if (mac != None) {
                official = mac.getOrThrow()
            } else {
                official = aliases.get(dialect).getOrThrow()
            }
        }
        let list = entries.get(official)
        match (list) {
            case None =>
                let fresh = ArrayList<String>()
                fresh.add(dialect)
                entries.add(official, fresh)
            case Some(l) =>
                l.add(dialect)
        }
    }

    // 碰撞报告：按官方词排序输出，顺序稳定
    let officials = ArrayList<String>()
    for (k in entries.keys()) {
        officials.add(k)
    }
    sort(officials)
    for (official in officials) {
        let candidates = entries.get(official).getOrThrow()
        if (candidates.size >= 2) {
            var candText = ""
            var first = true
            for (c in candidates) {
                candText = if (first) { c } else { "${candText}, ${c}" }
                first = false
            }
            collisions.add(uiTextF("⚠ 反向映射碰撞：`{0}` 对应多个母语词（{1}），反向展示采用首个命中 `{2}`", [official, candText, candidates[0]]))
        }
    }
    return ReverseMap(entries, collisions)
}
