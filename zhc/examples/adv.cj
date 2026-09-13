// adv.zc —— 对抗用例（L0 词法转译边界验证）
// 运行：zhc check examples/adv.zc（编译失败属预期，用于检查 .zhc/adv.cj 转译产物）

@Derive
main() {
    let 值 = `let`          // 反引号原始标识符：只剥反引号查表 → `let`
    // 注释里的 打印行 函数 让 可变 绝不替换
    println("字符串里的 让 打印行 函数 不替换")
    if (true) {
        println("条件分支")
    } else if (false) {
        println("否则分支")
    }
}
