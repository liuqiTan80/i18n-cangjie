// 俄语方言示例（ZHCLANG=ru 时运行）：.rc 扩展名来自 ru 语言包 lang_info.toml
// 注意：главная → main，与官方一致 main 声明不带 func（同中文「主函数」）
main() {
    let имя: String = "Россия"
    println("Привет, ${имя}!")

    // 类型词别名：целое → Int64
    let число: Int64 = 42
    println("Число: ${число}")
}
