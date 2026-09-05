# csv4cj 移植说明（方言映射：libs/zh/crates/csv4cj.toml）

- 上游：<https://gitcode.com/Cangjie-TPC/csv4cj>（v1.0.4，Apache-2.0）
- 功能：CSV 文件的仓颉操作工具库——读写、解析，支持中文与自定义格式。
- 映射规模：["模块路径"] 1 条 + ["标识符"] 72 条（测试脚本全部命中源码）。

## 1. 功能模块分析

| 模块（源文件） | 职责 | 关键公开类型 |
|---|---|---|
| 解析核心 | 把字符流切成记录 | `CSVParser`（Iterable）、`Lexer`、`Token` |
| 记录模型 | 一行数据的容器 | `CSVRecord`（Iterable + Serializable）、`CSVRecordIterator` |
| 读取层 | 字符读取抽象 | `CSVReader`、`CharReader`、`StringStream`、`UTF8ReaderStream`、`GBKReaderStream` |
| 格式控制 | 分隔符/引号/注释/表头策略 | `CSVParseFormat`（解析方向）、`CSVOutFormat` + `QuoteMode`（输出方向） |
| 输出层 | 记录写回文本 | `CSVPrinter`、`Appendable` |
| 常量 | 分隔/转义用字符 | `Constants`（COMMA、LF、TAB…） |

## 2. 核心接口（官方原名 → 方言名）

- 读三步：`UTF8ReaderStream`（UTF8读取流）→ `CSVReader`（CSV读取器）→
  `CSVParser.nextRecord()`（下一条记录）拿 `Option<CSVRecord>`；
- 写两步：`CSVOutFormat`（CSV输出格式）+ `CSVPrinter.print(record, out)`；
- 格式链式配置：`CSVParseFormat.DEFAULT.setSkipHeaderRecord(true).setFirstLineAsHeader(true)`
  → `CSV解析格式.DEFAULT.设跳过表头记录(true).设首行为表头(true)`；
- 常量：`Constants.COMMA` → `CSV常量.逗号符`。

## 3. 依赖关系

- 仅依赖官方 `std.collection / std.env / std.fs / std.io / std.math`
  与 `stdx.serialization.serialization`（`CSVRecord.serialize()`）；
- 引入项目需配置 `CANGJIE_STDX_PATH`（stdx 标准扩展库）；
- 编译目标映射 ohos/windows/linux 均走 stdx 动态库路径（见其 `cjpm.toml`）。

## 4. 差异处理说明

- **类型系统**：`CharReader` 是库自定义接口（非 std.io.InputStream），
  `StringStream`/`UTF8ReaderStream`/`GBKReaderStream` 均实现它——方言侧不做
  包装，按原名直译；`CSVRecord <: Iterable<String> & Serializable<CSVRecord>`
  多接口约束保持原样。
- **错误处理**：解析失败返回 `Option<CSVRecord>`（None = 流结束），不抛异常；
  方言侧用 `选项`/`有值`/`无` 原生表达，映射只译标识符不改语义。
- **恒等保留**：`get/size/print/printLine/next/iterator/read/readLine/
  lookAhead` 不译——它们是跨库通用方法名，全局翻译会波及 std.collection 等；
  `CSV解析格式.DEFAULT` 里的 `DEFAULT` 为静态 prop，保持原名。

## 5. 方言使用示例（.zc）

```zc
导入 标准集合.*
导入 标准文件系统.*
导入 CSV工具.*

主函数() {
    让 流 = UTF8读取流(文件("成绩.csv", OpenMode.读))
    让 读取器 = CSV读取器(流)
    让 解析器 = CSV解析器(读取器, CSV解析格式.DEFAULT
        .设跳过表头记录(true).设首行为表头(true))
    // 逐条读取（None = 结束）
    循环 (让 记录 = 解析器.下一条记录()) {
        匹配 (记录) {
            有值(行) => 打印行("第${行.取记录号()}行：${行.取值列表()}")
            无 => 中断
        }
    }
}
```

## 6. 测试

- 映射级（无 SDK 可跑）：`python3 scripts/verify-libs-api.py`——72 个
  官方原名全词命中 csv4cj 源码；`check-libs.py` 守格式与撞词表；
- 语义级（需 SDK + csv4cj 依赖）：方言断言测试示例——

```zc
导入 标准断言.*          // std.unittest（示意，工程测试按 cjpm test 组织）
导入 CSV工具.*

测试取常量() {
    断言相等(CSV常量.逗号符, r',')
    断言相等(CSV常量.回车换行, "\r\n")
}
```
