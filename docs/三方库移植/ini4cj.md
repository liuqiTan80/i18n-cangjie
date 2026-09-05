# ini4cj 移植说明（方言映射：libs/zh/crates/ini4cj.toml）

- 上游：<https://gitcode.com/Cangjie-TPC/ini4cj>（v1.0.4，许可见上游 LICENSE）
- 功能：INI 配置文件解析——归一化接口读取字符串/整数/长整数/浮点/布尔五类值，
  内置 Int32/Int64 溢出检查。
- 映射规模：["模块路径"] 1 条 + ["标识符"] 24 条（测试脚本全部命中源码）。

## 1. 功能模块分析

| 模块（源文件） | 职责 | 关键公开类型 |
|---|---|---|
| 数据模型 | 文件 → 节 → 字段 三层容器 | `IniFile`、`IniSection`、`IniField`、`ToIni` |
| 取值层 | 类型安全的值读取 | `IniParser.getString/getInt/getLongInt/getDouble/getBoolean` |
| 值包装 | 五类标量的统一抽象 | `IniValue`（抽象）+ `IniString/IniInt/IniLongInt/IniDouble/IniBoolean`、`IniType` 枚举 |
| 解析器 | 文本 → IniFile | `IniParser.parse()`（路径或全文两种构造）、`IniException` |

## 2. 核心接口（官方原名 → 方言名）

- 解析：`IniParser("配置.ini").parse()` → `INI解析器("配置.ini").解析()`，
  得到 `IniFile`（INI文件）；
- 三层取值：`INI文件.get(节名)` → `INI节.get(键名)` → `INI字段.value`
  （`IniValue`，INI值）；
- 类型安全读取：`INI解析器.取整数值(值)`（类型不符抛 `INI异常`）；
- 值类型判别：`INI值类型.IniTypeInt` → `INI值类型.INI整数型`。

## 3. 依赖关系

- 仅依赖官方 `std.collection / std.convert / std.fs / std.io / std.math`
  与 `stdx.serialization.serialization`；**不依赖任何其他三方库**，
  是零负担的配置解析选型。

## 4. 差异处理说明

- **错误处理**：库定义 `IniException <: Exception`（INI异常），节/键不存在、
  类型不符、整数溢出均以异常形式抛出——方言代码用 `异常`/`捕获` 原生表达；
  与 csv4cj 的 Option 风格不同，属两库各自的既定约定，映射不改变。
- **类型系统**：`IniValue` 为抽象基类 + 五个子类（判别靠 `as` 向下转型，
  源码即如此实现）；`IniType` 枚举成员全大写驼峰（IniTypeString 等），
  方言键取「INI×型」命名与「INI×值」的子类名区分。
- **恒等保留**：`get/toString/parse/getMessage` 等通用名不译
  （`取消息` = `getMessage` 因语义清晰仅保留 INI 异常语境使用）。

## 5. 方言使用示例（.zc）

```zc
导入 INI工具.*

主函数() {
    让 解析器 = INI解析器("应用配置.ini")
    让 配置 = 解析器.解析()
    让 服务节 = 配置.get("服务器")
    让 端口 = 解析器.取整数值(服务节.get("端口"))
    打印行("端口 = ${端口}")
}
```

## 6. 测试

- 映射级（无 SDK 可跑）：`python3 scripts/verify-libs-api.py`——24 个
  官方原名全词命中 ini4cj 源码；`check-libs.py` 守格式与撞词表；
- 语义级（需 SDK + ini4cj 依赖）：方言断言测试示例——

```zc
导入 标准断言.*
导入 INI工具.*

测试解析内联配置() {
    让 解析器 = INI解析器()
    让 配置 = 解析器.parse("[节]\n名 = 42\n")
    断言相等(解析器.取整数值(配置.get("节").get("名")), 42)
}
```
