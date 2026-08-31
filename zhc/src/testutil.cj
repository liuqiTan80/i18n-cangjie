package zhc

// 单元测试辅助（§13.1 第 43 条实测）：@Expect 宏展开后 `opt == None` 的
// None 泛型参数无法推断（generic type should be used with type argument），
// 统一用 Option 模式匹配辅助函数断言。

/** Option 是否为 None。 */
public func isNoneOpt<T>(o: Option<T>): Bool {
    match (o) {
        case None => true
        case Some(_) => false
    }
}

/** Option 是否为 Some。 */
public func isSomeOpt<T>(o: Option<T>): Bool {
    match (o) {
        case None => false
        case Some(_) => true
    }
}
