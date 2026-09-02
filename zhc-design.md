# 仓颉方言编程框架 zhc 设计文档

> 本文依据 `dialect-framework-blueprint.md`（zrRust 已验证的生产架构蓝图）为**仓颉编程语言（Cangjie）**
> 设计一套母语方言编程框架，引擎与 CLI 全部使用仓颉语言自举实现（dogfooding）。
>
> - 范式：转译代理（Transpile-and-Delegate）——方言源码 → 官方源码 → 官方工具链编译 → 诊断反向翻译
> - 命名：CLI 名 `zhc`（中文仓颉）；方言源码扩展名 `.zc`（中文仓颉）；项目仓库根 `zhc/`
> - 阅读顺序：§1 范式 → §2 架构 → §3 差异适配 → §4-9 模块细节 → §10 路线 → §11-15 风险/测试/实测 → §16 仓颉特性优化

---

## 1. 范式与前提核对

### 1.1 核心决策：沿用"转译代理"

与蓝图一致，不重写编译器。三条支撑理由在仓颉语境下全部成立：

1. **生态零成本继承**：编译、依赖管理、测试全部由官方工具链（cjc/cjpm）完成，方言代码与仓颉生态完全互通。
2. **语义永远正确**：方言不引入新语义——母语代码与标准代码同构，差别只在标识符文本，不存在"方言编译器自己的 bug"。
3. **渐进过渡**：`eject` 一键导出标准 `.cj` 源码，学习者随时"毕业"，消除被工具锁死的顾虑。

### 1.2 成立前提核对（蓝图 §1.2 三条逐一验证）

| 前提 | 仓颉现状 | 结论 |
|---|---|---|
| 标识符允许非 ASCII（Unicode XID） | 仓颉普通标识符 = `XID_Start + XID_Continue*` 或 `_ + XID_Continue+`（Unicode 15.0.0），中文/日文均可 | ✅ 完全满足 |
| 官方工具链可脚本驱动、有结构化诊断 | `cjc` 支持 `--diagnostic-format=[default\|noColor\|json]`、`--output-dir`、`-p`（包编译）、`--import-path`；`cjpm` 负责依赖解析 | ✅ 满足（JSON 字段结构需实测，见 §13） |
| 词法边界可靠可得 | 标准库 `std.ast` 提供官方语法解析器（仓颉宏系统 Tokens 来源），但**词法 API 是否公开需实测**；仓颉无公开第三方词法器 crate | ⚠️ 半满足：优先 `std.ast`，不可用则自研保守词法器（§5.1） |

### 1.3 教学三支柱（仓颉版）

- **母语可执行**：`函数 主函数() { 打印行("你好") }` 直接编译运行。
- **母语诊断**：级别、消息、类型名、help 短语、cjpm 进度行全部翻译，并附教学提示。
- **母语生态**：标准库与第三方库 API 也有母语别名（`向量.添加()` → `ArrayList.add()`）。

### 1.4 仓颉语言特性速查（设计依据）

- 关键字（官方清单，共 60+）：`as abstract break Bool case catch class const continue Rune do else enum extend for func false finally Float16 Float32 Float64 if in is init import interface Int8 Int16 Int32 Int64 IntNative let mut main macro match Nothing open operator override prop public package private protected quote redef return spawn super static struct synchronized try this true type throw This unsafe Unit UInt8 UInt16 UInt32 UInt64 UIntNative var VArray where while`
- 声明用 `func`（非 `fn`）；可变声明用 `var`（非 `mut`）；`main` 是关键字且可直接书写（`main()` 无需声明关键字）
- 原始标识符用**反引号**：`` `if` ``（非 Rust 的 `r#`）
- 模块路径与成员访问统一用 `.`：`import std.collection.{ArrayList, HashMap}`、`MyStruct.NAME`、`map.size`；**无 Rust 式 `::` 关联调用**
- 过程宏：`macro package` 定义、`public macro 名字(input: Tokens): Tokens { quote {...} }`、调用 `@名字(...)`；`println`/`print`/`readln` 是内置函数（非宏）
- 字符串插值：`"值是 ${i}"`；格式化字符串 `f"..."`；字符字面量 `'a'`（Rune）
- 空安全：`?Int64` 可空类型、`Option`（`Some`/`None`）、`match/case`、`is`/`as`
- 诊断消息特征：类型名带种类前缀，如 `expected 'Struct-String', found 'Class-Deque<Tuple<Int64, Int64>>'`
- 仓颉将标识符统一识别为 NFC 形式（Unicode Normalization Form C）

---

## 2. 总体架构

### 2.1 四层模型（照抄蓝图 §2，宿主替换为仓颉）

```text
┌────────────────────────────────────────────────────────────┐
│  ④ IDE 层        VS Code 扩展：语言注册 / 全角转换 / 右键运行    │
│                  LSP 代理：方言 ↔ 官方语言服务双向翻译（三档降级） │
├────────────────────────────────────────────────────────────┤
│  ③ 工具链层      zhc CLI：init / run / check / eject / add /   │
│                  lang / mapping / install lsp                 │
├────────────────────────────────────────────────────────────┤
│  ② 引擎层（仓颉实现）                                         │
│     词法转译（AST 辅助，三档降级）→ import 路径 → 别名替换 → 缓存 │
│     诊断翻译（消息表 + 类型本地化 + 教学提示）                   │
│     源映射 / Unicode 检查 / 自国际化 / 前置语法检查              │
├────────────────────────────────────────────────────────────┤
│  ① 数据层        语言包（每自然语言一个目录，TOML）：            │
│                  关键字 / 模块路径 / 标准库别名 / 第三方库别名    │
│                  / 错误翻译 / 界面文案 / 元信息                 │
└────────────────────────────────────────────────────────────┘
```

**关键不变式**：引擎层不硬编码任何具体自然语言与宿主语言知识；一切语言相关内容在数据层（语言包）与宿主适配层（词法器、cjc/cjpm 驱动）。

**模块依赖方向**（严格单向）：`语言包(数据) → 引擎 → CLI / LSP → IDE 扩展`

### 2.2 技术选型（仓颉自举）

| 需求 | 选型 | 备注 |
|---|---|---|
| CLI 参数解析 | `std.argopt` | 标准库自带 |
| JSON（诊断/语言包/LSP 消息） | `std.json` | 标准库自带 |
| 进程调用（cjc/cjpm） | `std.os.process`（或 `std.process`，版本差异实测） | 需捕获 stdout/stderr |
| 文件系统 | `std.fs` | 标准库自带 |
| 缓存指纹哈希 | `std.crypto.digest`（SHA256） | 标准库自带 |
| Unicode 分类 / NFC | `std.unicode` | XID 分类与 normalize API 需实测（§13） |
| TOML 解析 | **自研 TOML 子集解析器**（阶段 0） | 标准库无 std.toml；若 stdx 提供则优先复用 |
| 正则 | `std.regex` | ⚠️ **仅支持 ASCII**：中文键匹配禁用 regex，一律用 `String.startsWith/endsWith/contains` |
| 词法器 | `std.ast` 官方解析器（实测）→ 自研保守词法器（兜底） | 见 §5.1 |
| 单元测试 | `std.unittest` | 标准库自带 |
| 语言包分发 | 运行时文件加载：内置目录 + `~/.zhc/lang-packs` 用户覆盖 | 仓颉无 include_str! 编译期嵌入；`lang install` 天然支持 |

**TOML 子集解析器范围**（自研时必须支持的语言包语法子集）：注释、`[表]` / `["中文表名"]`、裸键 / `"引号键"`、字符串（含转义）、布尔、整数、数组、内联表；不支持多行字符串、日期、跨表引用（语言包用不到）。解析结果为 `HashMap<String, TomlValue>`，保持插入序。

### 2.3 仓库结构（zhc/）

```text
zhc/
├── cjpm.toml                    # 模块配置（见 §15）
├── src/
│   ├── main.cj                  # CLI 入口（argopt 命令树）
│   ├── engine/                  # 语言无关引擎（仓颉实现）
│   │   ├── lexer.cj             # 词法转译 + @宏名替换 + 源映射记录
│   │   ├── module_path.cj       # import 语句态路径替换
│   │   ├── alias.cj             # 别名替换（声明位保护 + 豁免集）
│   │   ├── reverse.cj           # 反向映射构建（eject/诊断类型本地化共用）
│   │   ├── unicode_check.cj     # 零宽/双向控制符/同形字符扫描
│   │   ├── sourcmap.cj          # 源映射数据结构与双向折算
│   │   ├── cache.cj             # 增量缓存（内容哈希 + 语境指纹）
│   │   └── i18n.cj              # 工具自身界面国际化（ui.toml 路由）
│   ├── diag/
│   │   ├── json_parse.cj        # cjc --diagnostic-format=json 解析
│   │   ├── text_parse.cj        # noColor 文本兜底解析
│   │   ├── translate.cj         # 翻译决策链（精确→前缀→~后缀）
│   │   ├── placeholder.cj       # {期望}/{实际}/{q0} 占位符捕获
│   │   └── type_localize.cj     # Struct-/Class- 前缀 + 泛型 + 路径段本地化
│   ├── toolchain/
│   │   ├── cjc_driver.cj        # cjc 编译/检查驱动（JSON 模式）
│   │   ├── cjpm_driver.cj       # cjpm update/依赖解析驱动
│   │   └── version_probe.cj     # cjc --version 探测（init 用）
│   ├── langpack/
│   │   ├── loader.cj            # 语言包加载/合并/优先级
│   │   ├── toml_mini.cj         # TOML 子集解析器（或 stdx 复用适配）
│   │   └── manifest.cj          # lang list/install/remove
│   ├── cli/                     # init/run/check/eject/add/lang/mapping 各一文件
│   ├── lsp/                     # LSP 代理（三档降级，见 §8）
│   │   ├── proxy.cj             # JSON-RPC 转发 + 响应 ID 映射
│   │   ├── position_map.cj      # 源映射 → 行列折算
│   │   └── poll_diag.cj         # 轮询降级诊断
│   └── util/
│       ├── nfc.cj               # NFC 归一化（查表键与标识符）
│       └── path.cj              # 项目根定位（向上找 cjpm.toml）
├── lang-packs/
│   └── zh/                      # 中文语言包（完整样例见 §6）
│       ├── lang_info.toml
│       ├── keywords.toml
│       ├── module_paths.toml
│       ├── stdlib.toml
│       ├── errors.toml
│       ├── ui.toml
│       └── crates/
└── tests/
    ├── unit/                    # 引擎单测（std.unittest）
    ├── golden/                  # 诊断黄金样例（源码 → 母语诊断文本）
    ├── adversarial/             # 对抗用例库（字符串含关键字/豁免/零宽等）
    └── e2e/                     # 端到端（临时项目跑 run/check/eject）
```

---

## 3. 仓颉 vs Rust 关键差异适配（本设计核心）

以下 13 条是蓝图移植到仓颉时必须替换或删除的适配点，每条给出：蓝图做法 → 仓颉做法 → 实现要点。

### 3.1 原始标识符：`r#让` → `` `让` ``

- 蓝图：`r#` 前缀剥离查表后复原。
- 仓颉：反引号包裹的原始标识符（`` `if` `` 等）。词法器将反引号 + 内部标识符作为一个 token；转译时剥离反引号查关键字表，命中则替换反引号内的词（`` `让` `` → `` `let` ``），未命中则原文透传。注意反引号 token 与宏 `@` 前缀、字符串字面量互斥，词法状态机需明确优先级。

### 3.2 宏机制：`println!` 补感叹号 → `@宏名` 过程宏

- 蓝图：宏名后跟 `(`/`[`/`{` 且前无 `::` 时自动补 `!`；宏名用独立宏映射表。
- 仓颉：`println`/`print` 是**普通内置函数**（无需任何特殊处理，走关键字/别名表即可）；真正的宏是过程宏，调用形式 `@名字(...)` 或 `@名字`（作用于声明）。**"补感叹号"逻辑整段删除**。
- 实现要点：
  - 词法器识别 `@` 后跟标识符的 token 序列（`@` 与标识符之间允许空白？按官方语法 `@MacroName(...)` 紧邻，保守实现允许 `@` 与名字间零空白，实测确认）。
  - `@` 后的宏名查**独立宏节**（keywords.toml 的 `["宏"]` 节，如 `"派生" = "Derive"`，则 `@派生` → `@Derive`），不查全局关键字表（避免与类型/别名撞词，对应蓝图坑 ⑤）。
  - `macro package`、`quote {...}`、`Tokens` 等宏定义侧的关键词走普通关键字表；`quote` 表达式体内的 token 序列照常参与转译（它是合法仓颉 token 序列）。

### 3.3 import 路径：`::` 分隔 → `.` 分隔 + 导入列表

- 蓝图：`use std::collections::HashMap;` 语句态，`::` 段替换。
- 仓颉：
  ```cangjie
  import std.collection.{ArrayList, HashMap}   // 导入列表形式
  import std.math.*                             // 通配形式
  import myModule.log.printLog                  // 单符号形式
  ```
- 实现要点：
  - 状态机：遇 `import` 关键字（或其方言映射结果）进入语句态，遇 `;` 退出。
  - 语句态内：`.` 分隔的路径段查 `module_paths.toml`（如 `标准集合` → `std.collection`）；`{...}` 内的符号列表是**导入标识符**，查别名表（如 `{哈希映射, 向量}` → `{HashMap, ArrayList}`）；`*` 透传。
  - 语句外的 `标识符.段` 一律不碰（那是别名表的职责，对应蓝图 §5.2 的越界红线）。
  - `import` 语句本身在词法阶段已被关键字表转译（方言 `导入` → `import`），因此路径替换阶段以**转译后的 `import` token** 为状态机触发点（与蓝图"先关键字后路径"的管线顺序一致）。

### 3.4 声明关键字与豁免集

- 蓝图：`DECL_KEYWORDS = fn/struct/enum/trait/type/mod/let/const/static`；第一遍收集声明名，第二遍全文件裸使用处豁免。
- 仓颉：`DECL_KEYWORDS = func/class/struct/enum/interface/extend/let/var/const/prop/type/macro`（`static`、`mut`、`public` 等是修饰符，不作为声明触发器，但需**跳过修饰符链**定位声明名——`public static prop GETNAME` 中 `GETNAME` 由 `prop` 触发收集）。
- **仓颉扩展豁免（蓝图没有）**：仓颉参数名与模式绑定名也需豁免，否则误伤：
  - 参数：`func 求和(数量: Int64)`、`(let 成员: String)`、`(var 成员: Int64)` —— 在声明后的 `(...)` 区间内收集 `:` 前标识符与 `let/var` 后标识符。
  - 模式绑定：`for (键 in 映射)`、`case Some(值) =>`、`let (a, 键) = 元组`、lambda `{x: Int64 => ...}` —— 阶段 2 实现，列为对抗测试项。
- 豁免优先级：用户声明名/参数名/模式绑定名 > 别名表；`import {…}` 列表、`@` 宏名不受豁免集影响（宏名走宏节）。

### 3.5 成员访问限定符：`::` → `.`（别名替换安全性重设计）

- 蓝图：`字符串::新建` → `Vec::new()`，`::` 前必为类型名，因此"`::` 限定段照常替换"是安全的。
- 仓颉：**静态成员与实例成员统一用 `.`**（`MathUtils.count`、`map.size`、`x.toString()`）。`x.新建` 中的 `x` 可能是用户变量，`新建` 可能是用户 struct 的成员名。
- 安全性闭环（不引入作用域分析）：
  1. 第一遍收集：声明关键字后的声明名 **+ 类/结构体成员声明**（`public let 长度: Int64`、`prop 全名: String` 中的 `长度`/`全名` 都被 `let`/`var`/`prop` 触发收集）**+ 参数名 + 模式绑定名**；
  2. 第二遍：豁免集内名字的全部裸出现处（包括 `.` 之后的段）不替换；
  3. 未被豁免的 `.段`（如 `向量.添加` 中的 `添加`）查别名表替换——用户不可能声明却又未收集到（成员声明必含 `let/var/prop`）。
- 结论：蓝图"`::` 限定段照常替换"在仓颉中改为"**`.` 限定段照常替换，但豁免集覆盖成员名**"；其余逻辑不变。
- 已知边界：`extend` 扩展声明中的函数名、接口默认实现里的名字若与别名撞词，需 mapping check 与教学文档提示（与蓝图相同性质的保守近似）。

### 3.6 构建工具驱动：cargo JSON → cjc JSON

- 蓝图：`cargo check/run --message-format=json`，解析器兼容"编译器直出 / cargo 包装行"两种格式。
- 仓颉：**直接驱动 `cjc`**（绕过 cjpm，避免双格式包装）：
  - 单文件：`cjc <转译文件> --diagnostic-format=json --output-dir <隔离目录> -o <产物名>`
  - 项目（无第三方依赖）：`cjc -p <转译目录> --output-type=exe --diagnostic-format=json --output-dir <隔离目录>`
  - 项目（有依赖）：先 `cjpm update` 解析依赖（生成 `target/` 下依赖的 `.cjo`/`.a`），再 `cjc --import-path target -p <转译目录> ...`（命令形态照抄 `cjpm build -V` 展示的真实 cjc 调用）。
  - `run`：编译成功后直接执行产物，stdout 透传、stderr 逐行处理（JSON 行收集翻译、其余透传，对应蓝图 §6.5）。
- 转译产物目录：默认 `.zhc/`（项目根下，gitignore），方言源码可与官方 `.cj` 混放 `src/` 的可行性取决于 `cjc -p` 是否过滤扩展名（实测项 #6，§13）；**默认隔离目录策略不依赖该实测结果**。

### 3.7 错误码：E0308 优先 → 消息表为主

- 蓝图：错误码表优先（`[E0308]` 节），消息表兜底。
- 仓颉（1.0.5 实测）：**JSON 诊断自带稳定错误码 `DiagKind` 字段**（如 `sema_mismatched_types`/`chir_dce_unused_variable`/`parse_expected_character`/`sema_cannot_assign_to_immutable`/`package_search_error`，§13.1 第 19 条）。**errors.toml 的 `["诊断码"]` 表（键 = DiagKind）为第一优先级**（模板 + 教学提示 + 修复示例），`["消息翻译"]` 表（精确 → 最长前缀 → `~` 后缀）兜底版本漂移/未收录诊断。

### 3.8 类型名本地化：`::` 三段式 → 种类前缀 + 泛型 + `.` 段

- 蓝图：`std::fmt::Display` 按 `::` 分段（后缀段查词表 → 多段前缀完整匹配 → 中间段单段映射）。
- 仓颉：诊断消息中的类型形如 `Struct-String`、`Class-Deque<Tuple<Int64, Int64>>`、`?Int64`、`Array<ArrayList<Int64>>`：
  1. **剥种类前缀**：`Struct-`/`Class-`/`Interface-`/`Enum-`/`EnumCase-` 等（前缀清单实测确认，§13），本地化时前缀译作 `结构体`/`类`/`接口`/`枚举` 或不译（教学倾向：`类-字符串`）；
  2. **泛型递归**：`<...>` 内参数逐个递归本地化（`Tuple<Int64, Int64>` → `元组<整数, 整数>`，`Tuple` 本身查类型词表）；
  3. **路径段**：`a.b.C` 按 `.` 分段（后缀段 → 中间段 → 多段前缀完整匹配），复用 reverse.cj 的反向映射（过滤纯 ASCII 键）。
- 反向映射构建：类型节反转 + 别名表反转 + module_paths 反转，**过滤纯 ASCII 键**（对应蓝图坑 ②），模块路径源用覆盖式合并（后载覆盖先载）。

### 3.9 教学叙事：所有权 → 仓颉三主题

删除 Rust 所有权/借用叙事（仓颉无此概念），替换为仓颉学习者最高频的三类困惑：

1. **空安全叙事**：`?T`/`Option`/`None` 相关诊断 → 提示 `匹配`/`case Some(值)` 解包模式，示例用母语关键字书写；
2. **可变性叙事**：`let` 绑定后被修改 → "将 `让` 改为 `可变`（var）"；
3. **类型不匹配叙事**：`expected ... found ...` → 提示 `作为`（as）转换、检查声明与赋值两侧。
另保留通用提示：未使用告警（对应 `-Woff unused` 的项）、未解析导入（提示 `zhc add <库>`）。

### 3.10 工具链版本锁定：rust-toolchain.toml → cjpm.toml 的 cjc-version

- 蓝图：`init` 动态探测 `rustc --version` 写入 rust-toolchain.toml（坑 ⑬：硬编码版本会过时）。
- 仓颉：`cjpm.toml` 的 `[package] cjc-version` 字段是**必需项**（"所需 cjc 的最低版本要求"）。`zhc init` 时解析 `cjc --version` 输出动态填入，不硬编码。

### 3.11 包管理器封装：cargo add → 编辑 cjpm.toml

- 蓝图：`rzc add` 封装 `cargo add`。
- 仓颉：cjpm **无 `add` 命令**（仅 `install` 安装二进制包；依赖在 `cjpm.toml` 的 `[dependencies]` 手写 git/path 形式）。`zhc add <库>` = 向 `[dependencies]` 追加条目（TOML 追加写，不重排）+ 查找 `crates/<库>.toml` 映射存在与否并提示 `mapping auto`；git 库需用户提供 URL，path 库需用户提供相对路径。

### 3.12 LSP 目标：rust-analyzer → 官方语言服务（三档降级）

- 蓝图：代理 rust-analyzer（成熟）。
- 仓颉：官方 VSCode 插件（Cangjie 官方插件）存在，但**独立可启动的语言服务器成熟度未知**（社区 2025 年报道"语言服务器尚未就绪"）。设计为三档降级，档位由实测决定，见 §8。

### 3.13 字符串插值：`${}`（仓颉独有，蓝图无此概念）

- 仓颉字符串内嵌 `${表达式}` 是**代码**而非文本：`"值是 ${i}"`、`"${x.toString()}"`。
- 蓝图原则"字符串内容绝不误改"在仓颉需修正为：**字符串文本不误改，`${}` 插值段内的 token 参与转译**（否则 `"${x.转换字符串()}"` 中的 `转换字符串` 无法替换，编译报错）。
- 实现要点（阶段 2）：
  - 词法器在字符串 token 内扫描 `${`，进入插值代码态；用**括号栈**（`(`/`[`/`{` 配对）确定插值结束的 `}`（处理嵌套 `"${ {a:1}.x }"`）；
  - 插值态内按普通代码 token 规则转译（含嵌套字符串？保守：插值态内遇 `"` 视为普通字符串跳过其内容，避免过度复杂；此边界列为对抗测试）；
  - 插值态恢复后继续字符串扫描，直至匹配的 `"` 或行尾（多行字符串实测确认）。
- 阶段 0 可先按"字符串整体保护"实现（`${}` 不转译），阶段 2 升级为插值态转译；文档与教学教程说明该能力边界。

---

## 4. 核心执行管线

### 4.1 正向：方言 → 可执行程序

```text
main.zc 源码
   │  ① Unicode 混淆检查（零宽 U+200B 等/双向控制符 RLO/高置信同形字符，仅告警不阻断，报告精确位置）
   │  ② 词法转译：token 级关键字替换 + @宏名替换（字符串文本/注释/反引号标识符绝不误改；
   │     多词关键字最长匹配（否则如果→else if）；${} 插值段转译（阶段 2））
   │     可选 AST 语义辅助（std.ast 解析 → 精确豁免集 / 插值识别 / 前置语法检查，
   │     失败自动回退 token 级保守模式，见 §16.1）
   │  ③ import 语句态路径替换（. 分隔；{...} 导入列表替换；; 退出）
   │  ④ 别名替换（两遍扫描：声明位保护 + 用户声明名/成员名/参数名/模式绑定名全文件豁免；
   │     . 限定段照常替换）
   ▼
标准 .cj 源码（写入隔离目录 .zhc/ 或临时目录）
   │  ⑤ 调用官方工具链（cjc --diagnostic-format=json；项目模式先 cjpm update 解析依赖）
   ▼
编译产物运行 / JSON 诊断行
```

**管线顺序不可调换**（对应蓝图 §3.1）：先关键字（`导入`→`import` 让路径阶段能识别语句起点），再 import 路径（限定在 import 内），最后别名（兜底处理 import 内未命中的末段与表达式中的 `.` 限定调用）。

### 4.2 反向：诊断 → 母语教学信息

```text
cjc --diagnostic-format=json 诊断行
   │  ① 解析（cjc 直出格式；noColor 文本兜底）
   │  ② 查翻译表：错误码（预留）→ 消息表精确 → 最长前缀 → ~后缀
   │  ③ 提取期望/实际类型（label/字段优先，消息内引号对兜底）
   │  ④ 类型名本地化（剥 Struct-/Class- 前缀 → 泛型递归 → . 路径段三段式）
   │  ⑤ help 子消息翻译 + 教学提示拼接（空安全/可变性/类型转换/依赖提示）
   ▼
母语教学诊断（级别/消息/位置/📌叙事/💡提示）
```

### 4.3 增量缓存

- 缓存键 = **内容哈希（SHA256）+ 语境指纹**（全部映射表的哈希）；源码不变但语言包更新 → 指纹变化 → 自动失效重译（对应蓝图坑 ⑨）。**指纹在语言包加载合并完成后计算（最终生效合并表的哈希）**——用户目录覆盖、`lang install` 都会改变指纹，保证旧译文不复活。
- 缓存同时保存**源映射**（被替换标识符的源偏移与前后文本），供 LSP 位置还原与增量诊断复用。
- 缓存位置：`~/.zhc/cache/`（跨项目复用）+ 项目 `.zhc/cache/`（随项目可清理）。

**实现状态（s5t9a ✅）**：缓存键 = hash64(源文本) + 语言包指纹（转译相关四表 keywords/macros/modulePaths/aliases 排序拼串哈希——用户目录覆盖、lang install 都会改变指纹）；缓存内容 = TranspileResult 序列化（JSON：转译文 + MapEntry 列表 + total），命中后由 dstText/map 重建 SourceMap（诊断坐标与未命中路径完全一致）；接入 runSingle（单文件）、buildMember（项目/workspace）、cmdNative（构建钩子）三路径；缓存位置项目 .zhc/cache/（写入失败静默不影响转译）。1.0 适配：UInt64 运行时溢出抛异常 → 纯位运算哈希（§13.1 第 35 条）。

---

## 5. 引擎模块详细设计

### 5.1 词法转译（lexer.cj）

**输入**：方言源码 + 关键字映射 + 宏映射。**输出**：官方源码 + 源映射。

**三档转译策略（仓颉特性优化，见 §16.1）**：

- **L0（兜底，阶段 0）**：纯 token 级替换 + 保守豁免集——std.ast 不可用或解析失败时启用；
- **L1（AST 校验，阶段 2）**：token 级替换 + std.ast 解析方言源码，用 AST 语义校验并补全豁免集，附带前置语法检查（母语诊断语法错误）；
- **L2（AST 原地替换，阶段 3+）**：遍历 AST，利用语义上下文精确决定每个标识符的替换，只改写标识符区间、保留注释与空白（保格式）。

实现要求（按重要性排序，对应蓝图 §5.1 逐条适配）：

1. **token 级替换**：优先 `std.ast` 官方词法 API（实测项 #2）；不可用则自研保守词法器。自研时必须正确跳过：`//` 行注释、`/* */` 块注释（嵌套规则实测）、`"..."` 字符串（含 `\` 转义）、`f"..."` 格式化字符串前缀、`'c'` Rune 字面量、反引号原始标识符；自研词法器不做语法校验，只做 token 切分与类别判定。
2. **整词匹配**：仅替换完整标识符 token（`读取全部字符串` 中的 `字符串` 不得被误替换）。
3. **原始标识符透传**：`` `让` `` 剥离反引号查表后复原为 `` `let` ``。
4. **@宏名替换**：`@` 后标识符**只查独立宏节**，不查全局关键字表与别名表（对应蓝图坑 ⑤）；无补感叹号逻辑。注意宏节词与关键字表允许同名（如 `"宏" = "macro"` 与宏节词 `宏`），`@` 上下文以宏节为准，非 `@` 位置按普通标识符规则处理。
5. **多词关键字**：`否则如果` → `else if` 需连续 token 前瞻合并，按最长匹配处理（对应蓝图坑 ⑥）。
6. **源映射记录**：每次实际替换记录 `(源偏移, 长度, 原文, 替换文)`；`@` 前缀本身不产生映射条目（宏名替换记录的是名字部分）。
7. **反向转译**：反转映射表即得 官方 → 母语（供 eject 反向展示与文档生成）；多对一碰撞时报告并采用"声明处最近用词"策略（见 §7 eject）。
8. **${} 插值态**（阶段 2）：字符串内 `${` 开启代码态，括号栈配对 `}`，态内 token 级转译（§3.13）。

### 5.2 import 路径替换（module_path.cj）

状态机：遇 `import` token（已转译）进入语句态，遇 `;` 退出；语句态内：
- `.` 分隔的段查 `module_paths.toml`（`标准集合` → `std.collection`），整段匹配优先（`标准集合` 而非 `标准`+`集合`）；
- `{` `}` 之间的标识符查**别名表**（导入符号列表）；
- `*`、`.`、`,`、`{` `}` 原样透传。

语句外的一切 `.` 路径不碰（红线）。

### 5.3 别名替换（alias.cj）——最易出错模块

两遍扫描（对应蓝图 §5.3，豁免集扩展为仓颉版）：

1. **第一遍收集豁免集**：
   - 声明名：`DECL_KEYWORDS`（func/class/struct/enum/interface/extend/let/var/const/prop/type/macro）后紧跟的标识符；修饰符链（public/private/protected/internal/static/mut/open/override/redef/operator）透明跳过，空白与注释不打断收集态；
   - 成员名：类/结构体体内 `let`/`var`/`prop` 声明的名字（已被上条覆盖）；
   - 参数名：声明后 `(...)` 区间内 `:` 前标识符与 `let`/`var` 后标识符；
   - 模式绑定名（阶段 2）：`for (名 in ...)`、`case 构造器(名)`、lambda `{名: 类型 =>` 中的绑定。
2. **第二遍逐 token 替换**：豁免集内的名字在全文件所有裸使用处（含 `.` 之后）不替换；未豁免的标识符查别名表（stdlib + crates 合并表）；`.段` 照常替换（§3.5 闭环）。

### 5.4 Unicode 混淆安全检查（unicode_check.cj）

转译前扫描：零宽字符（U+200B 等）、双向控制符（RLO 等）、高置信同形字符（如 CJK 与拉丁同形）。仅告警不阻断（教学场景宽容），必须报告精确位置（行/列）。这是母语编程框架的安全底线（对应蓝图坑 ⑫）。

### 5.5 工具自身国际化（i18n.cj，自举）

界面文案设计走 `ui.toml`（`["界面消息"]` 节 → `lang.uiText(键, 默认值)`，缺键回退默认）。**实现现状（2026-08 审计修正）**：仅关键编译结果文案走 uiText（4 处），其余用户可见文案为中文母语硬编码；完整 i18n 列为后续路线。**升级（2026-09：语言无关化）**：`ZHCLANG` 环境变量切换方言语言（`resolveLang()`，默认 zh；未设置/为空回退 zh）——全部入口（run/check/eject/lint/test/expand/native/lsp/mapping auto）已从硬编码 `resolveLangPack("zh")` 改为 `resolveLangPack(resolveLang())`；转译/反向转译/诊断翻译/类型本地化随所选语言包驱动，支持任意国家母语编写仓颉（ru 演示语言包 + 俄语示例 `examples/ru-hello.rc` 实测通过，.rc 扩展名来自 lang_info.toml）。界面文案仍以中文为默认（ui.toml 缺键回退），系统区域检测未实现。语言包运行时从环境变量 `ZHC_LANG_PACKS` → 当前目录 → 可执行文件旁（含离线包父目录）→ `~/.zhc/lang-packs` 加载（用户目录覆盖内置）。框架“自己说的每一句话”都是母语（当前以中文为默认界面语言）。

### 5.6 源映射（sourcmap.cj）

- 条目：`(源偏移, 长度, 原文, 替换文)`，按源偏移升序存储；**偏移单位统一为 UTF-16 code unit**（与 LSP 位置体系一致）；仓颉 String 按 Rune 索引，实现时逐字符遍历累计 UTF-16 偏移，避免与诊断坐标、编辑器坐标三方不一致；
- 正向：转译时增量记录；反向：给定官方坐标，二分定位受影响条目，按替换前后长度差做列偏移折算（等宽替换零成本）；
- 用途：LSP 位置还原、诊断位置映射、eject 对照。

---

## 6. 语言包数据规范

### 6.1 目录结构与格式

一个语言包 = 一个目录（目录名即语言代码）。全部使用 TOML；**非 ASCII 键必须双引号包裹**（TOML 裸键仅允许 ASCII）。

```text
lang-packs/<语言代码>/
├── lang_info.toml      # 必需：元信息
├── keywords.toml       # 必需：关键字映射（含 ["宏"] 节）
├── module_paths.toml   # 可选：import 路径段映射
├── stdlib.toml         # 可选：标准库模块路径 + 标识符别名
├── errors.toml         # 可选（强烈建议）：诊断翻译
├── ui.toml             # 必需：工具自身界面文案
└── crates/             # 可选：第三方库映射（每库一文件）
    └── <库名>.toml
```

### 6.2 中文语言包完整样例（zh）

**lang_info.toml**

```toml
["语言包"]
"名称" = "中文"
"扩展名" = "zc"      # 方言源码扩展名，决定 zhc run 的文件识别
"版本" = "1.0"
```

**keywords.toml**（键 = 母语词，值 = 官方原词；节名可自定义，`宏` 节有特殊语义）

```toml
["声明"]
"函数" = "func"
"主函数" = "main"
"让" = "let"
"可变" = "var"
"类" = "class"
"结构体" = "struct"
"枚举" = "enum"
"接口" = "interface"
"扩展" = "extend"
"常量" = "const"
"属性" = "prop"
"类型" = "type"
"宏" = "macro"
"导入" = "import"
"包" = "package"
"新" = "init"        # 构造函数（init 是关键字）

["控制流"]
"如果" = "if"
"否则如果" = "else if"   # 多词关键字，词法器需连续 token 合并
"否则" = "else"
"对于" = "for"
"在" = "in"
"当" = "while"
"匹配" = "match"
"情况" = "case"
"返回" = "return"
"跳出" = "break"
"继续" = "continue"
"尝试" = "try"
"捕获" = "catch"
"最终" = "finally"
"抛出" = "throw"
"同步" = "synchronized"
"生成" = "spawn"      # 并发

["类型"]
"整数" = "Int64"
"整数32" = "Int32"
"无符号整数" = "UInt64"
"浮点" = "Float64"
"浮点32" = "Float32"
"字符串" = "String"
"字符" = "Rune"
"布尔" = "Bool"
"单元" = "Unit"
"空" = "Nothing"
"向量" = "ArrayList"
"数组" = "Array"
"哈希映射" = "HashMap"
"哈希集合" = "HashSet"
"选项" = "Option"
"有值" = "Some"
"无值" = "None"

["逻辑值"]
"真" = "true"
"假" = "false"

["运算符"]
"是" = "is"
"作为" = "as"
"属于" = "is"          # 与上同值：同一官方词允许多个母语词

["宏"]                  # @ 前缀宏专用（独立宏映射表）
"派生" = "Derive"       # @派生(...) → @Derive(...)
```

设计要点（沿用蓝图 §4.2 并适配仓颉）：
- 枚举变体/构造器（`有值`/`无值`）进关键字表——出现频率极高且语义稳定；
- 同一词允许映射多词短语（`否则如果`），词法器按最长匹配处理；
- 常用类型（`字符串`/`向量`/`哈希映射`）放关键字表保证处处可写；更细 API 放 stdlib.toml；
- 仓颉无 `fn`（用 `func`）；变量可变性由 `let`/`var` 表达，`mut` 仅修饰 prop/func（扩展词表 `修改`）；`main` 是关键字但可直写，方言推荐 `主函数`；
- `?Int64` 这类可空类型由 `?` 运算符 + `整数` 类型名组合而成，无需整词映射。

**扩展词表**（按需启用，教学阶段建议渐进引入；与主表同格式，追加到 keywords.toml 对应节）：

```toml
["修饰"]            # 修饰符（声明位保护时需透明跳过的修饰符链）
"修改" = "mut"      # mut prop / mut func
"开放" = "open"
"重写" = "override"
"重定义" = "redef"
"外部" = "foreign"  # FFI
"不安全" = "unsafe"
"约束" = "where"    # 泛型约束
"本对象" = "this"
"本类型" = "This"

["属性访问器"]      # prop 块内 get/set 是上下文词（非关键字），经关键字表全局替换；
"获取" = "get"      # 用户声明同名变量时靠豁免集保护，与普通别名同一保守近似
"设置" = "set"

["宏定义"]          # 宏定义侧关键词
"引用" = "quote"    # quote { ... }
```

注意：`get`/`set` 不是仓颉关键字，方言词 `获取`/`设置` 走关键字表做全局 token 替换（仅在 `prop` 块内语义正确，但全局替换 + 豁免集保护与别名替换同一保守近似，可接受）。

**module_paths.toml**

```toml
["模块路径"]
"标准库" = "std"
"标准集合" = "std.collection"
"标准核心" = "std.core"
"数学" = "std.math"
"文件系统" = "std.fs"
"进程" = "std.os.process"     # 版本差异：std.process / std.os.process，按实测
"正则" = "std.regex"
"时间" = "std.time"
"JSON" = "std.json"
"AST" = "std.ast"
"格式化" = "std.format"
"IO" = "std.io"
```

仅在 `import` 语句内生效（`导入 标准集合.{哈希映射, 向量};` → `import std.collection.{HashMap, ArrayList};`）。表达式中的 `类型.关联函数` 不走此表，交给别名表。

**stdlib.toml**（与第三方库映射同格式，两节；加载顺序即优先级，最后加载覆盖同名键）

```toml
["模块路径"]
"标准集合" = "std.collection"
"标准核心" = "std.core"
"数学" = "std.math"

["标识符"]
"打印" = "print"
"打印行" = "println"       # 内置函数（非宏）
"读取行" = "readln"
"长度" = "size"             # 属性
"添加" = "add"
"放入" = "put"
"包含" = "contains"
"删除" = "remove"
"获取" = "get"
"转换字符串" = "toString"
"新建" = "new"              # 若仓颉标准库存在 new 形式构造
"拼接" = "append"
"排序" = "sort"
"迭代" = "iterator"
```

**errors.toml**（两类条目共存；仓颉无错误码体系，消息表为主，错误码节保留）

```toml
# ① 错误码表（预留扩展位：未来 cjc 若引入错误码，顶层节直接启用）
# [CJ0001]
# "消息模板" = "..."
# "教学提示" = "..."

# ② 消息表：节名固定 ["消息翻译"]，键为官方英文消息原文
["消息翻译"]
# 最长前缀匹配：动态后缀自动拼回
["消息翻译"."expected '"]
"消息模板" = "期望类型 `{q0}`，实际得到 `{q1}`"
"教学提示" = "类型不匹配：检查声明与赋值两侧类型是否一致。需要转换时使用 `作为`（as）。"

["消息翻译"."not found in"]
"消息模板" = "在 `{q0}` 中找不到 `{q1}`"

# ~ 后缀键：动态名在消息中间时用后缀锚定
["消息翻译"."~ is never used"]
"消息模板" = "`{q0}` 从未被使用"
"教学提示" = "删除未使用的声明，或检查拼写。"

# 空安全叙事（仓颉特色教学）
["消息翻译"."~ is not nullable"]
"消息模板" = "`{q0}` 不是可空类型"
"教学提示" = "可空类型写法：`整数?`（?类型）。解包使用 匹配 或 `有值/无值` 模式。"

# 可变性叙事（仓颉特色教学）
["消息翻译"."cannot assign to"]
"消息模板" = "不能给 `{q0}` 赋值"
"教学提示" = "`让`（let）绑定不可变。需要修改时把 `让` 改为 `可变`（var）。"
```

**匹配顺序**：错误码表 → 消息表精确 → 消息表最长前缀 → 消息表最长后缀（`~` 键）。占位符体系沿用蓝图：`{期望}/{实际}` 从 expected/found 提取；`{q0}/{q1}` 从动态残段引号内容填充（反引号取最后一对 rsplit，单引号按序取）。

**关键约束**（对应蓝图坑 ②）：消息表里不得出现英文键反向修正条目；构建反向映射（英文→母语）时必须过滤纯 ASCII 键，否则污染诊断翻译。

**ui.toml**（键为稳定英文标识，`{}` 顺序占位符）

```toml
["界面消息"]
"success_compile" = "✅ 编译成功，没有错误。"
"cjpm_progress_compiling" = "正在编译 {}"
"cjpm_build_success" = "构建成功。"
"unknown_extension" = "未知的方言扩展名 `{}`，可用扩展名：{}"
"no_project" = "未找到 cjpm.toml，请先在项目目录执行 `zhc init`。"
"toolchain_too_old" = "检测到 cjc 版本 {}，低于项目要求 {}。"
```

**crates/<库名>.toml**：格式与 stdlib.toml 完全相同；文件名即库展示名。由 `mapping auto`（提取公开 API + AI 命名）或 `mapping scaffold`（骨架 + 人工）生成，质量由 `mapping check` 把关。

### 6.3 加载与合并规则（确定性要求）

1. `crates/*.toml` 按**文件名排序**后依次合并；
2. `stdlib.toml` 最后加载，覆盖同名键（标准库通用词不被第三方撞名词条污染）；
3. 所有多源合并前排序（对应蓝图坑 ①：HashMap 迭代顺序不确定）；
4. 用户安装目录语言包覆盖内置目录（`~/.zhc/lang-packs/<代码>/*` 覆盖内置同路径文件）。

### 6.4 中文语言包工作量估算（对应蓝图 §11.3）

| 文件 | 工作量 | 说明 |
|---|---|---|
| keywords.toml | 小 | 仓颉关键字 60+（含内置类型 Int64/String/Bool/Rune、构造器 Some/None、`主函数`），加扩展词表后仍为一次性 |
| module_paths.toml | 小 | std 各包路径段（core/collection/math/fs/...），约 20 条 |
| stdlib.toml | 中 | 内置函数（print/println/readln）+ 常用类型方法（size/add/put/contains/toString/...），重点覆盖集合与字符串 API |
| errors.toml | 中 | 无错误码体系，靠消息表；优先覆盖 expected/found、未使用、空安全、可变性、未解析导入五类高频消息（每条含模板 + 教学提示） |
| ui.toml | 小 | 键不变（与蓝图同键），仅译文案 |
| crates/ | 中（按需） | 仓颉三方库生态起步阶段；`mapping auto` 需适配解析 .cjo/源码提取公开 API（实测后定） |
| 全包校验 | 小 | `zhc mapping check` 纳入 CI |

---

## 7. 诊断翻译系统

### 7.1 双通道解析

- **JSON 通道（首选）**：`cjc --diagnostic-format=json`。解析器需实测确认 cjc 直出格式（字段名/输出流/每行一对象或整体数组），并设计容错：无法解析的行降级到文本通道，不崩溃。
- **文本通道（兜底）**：`--diagnostic-format=noColor`。按 `[error]`/`[warning]` 锚定行、提取后续消息文本、`expected 'X', found 'Y'` 模式提取期望/实际；失去 span/children/help 信息，教学叙事降级（仅模板 + 提示）。

### 7.2 翻译决策链

```text
诊断(code, message, spans, children)
 ├─ code 命中错误码表（预留）────────→ 模板 + 教学提示
 ├─ message 命中消息表(精确/前缀/后缀) → 模板（含 {q0} 捕获填充）+ 动态残段拼接
 └─ 均未命中 ─────────────────────→ 回退原文（仅做类型名本地化）
```

前缀/后缀匹配**禁用 std.regex**（仅 ASCII）：用 `String.startsWith` 扫描键集合取最长命中；`~` 后缀键用 `String.endsWith` 取最长命中；动态残段取反引号/单引号对填充 `{q0}/{q1}`。

### 7.3 类型名本地化（type_localize.cj）

仓颉诊断类型形如 `Class-Deque<Tuple<Int64, Int64>>`、`?Int64`、`Array<ArrayList<Int64>>`：

1. **剥种类前缀**：`Struct-`/`Class-`/`Interface-`/`Enum-`/`EnumCase-`（清单实测）→ 前缀本地化（`类`）或剥离；
2. **可空标记**：`?` 前缀原样保留（`?整数`）；
3. **泛型递归**：`<...>` 内参数递归本地化；
4. **路径段三段式**：后缀段查类型词表 → 从长到短尝试多段前缀完整匹配 → 中间段单段映射（`.c` 分隔）；
5. **未知类型回退**：原样透传，不崩溃。

反向映射表由引擎从语言包自动构建（reverse.cj）：类型节反转 + 别名表反转 + module_paths 反转，**过滤纯 ASCII 键**，模块路径源覆盖式合并。

### 7.4 教学增强（仓颉三主题，见 §3.9）

- **教学提示（💡）**：每条错误条目附面向初学者的下一步建议，用母语关键字书写示例；
- **空安全叙事**：None 解包/可空性诊断从 span label 定位解包点，生成一句话故事线；
- **依赖提示**：未解析导入错误自动提取候选库名，提示 `zhc add <库>`（LSP 侧注入快捷修复代码动作）；
- **构建进度翻译**：`cjpm build success`、`compile package ...` 等前缀行进 ui.toml（匹配前 `trim_start`，对应蓝图坑 ⑧）；cjc 直出模式无进度行，无需处理。
- **宏展开错误**：仓颉宏可经 `std.ast` 的 `diagReport` 自定义报错（与编译器同格式输出）——宏展开产生的错误同样出现在 cjc 诊断流中，可被消息表覆盖；errors.toml 需预置宏类消息模板（如 `macro expansion failed` 类前缀键）。

### 7.5 run/check 的 JSON 模式集成

1. **JSON 诊断**：`--diagnostic-format=json` 输出多行格式化 JSON 到 **stderr**；顶层 `Diags[]` 数组，字段 `DiagKind`（**稳定错误码**，如 `sema_mismatched_types`）、`Severity`（error/warning）、`Message`（大写，短消息）、`MainHint.Content`（具体信息，如 `expected 'Int64', found 'Struct-String'`）、`Location.{File,Line,Column}`（行号列号与转译产物对应，做源映射折算）、`Notes[]`/`Helps[]`（补充说明）；末尾 `Num.{Errors,Warnings}`。zhc 提取 DiagKind → Message → Content 三通道（§16.5 错误字典前身，阶段 3 落地）。

---

## 8. CLI 设计（zhc）

命令树（宿主无关部分照抄蓝图 §7，构建命令替换为 cjc/cjpm）：

| 命令 | 职责 | 仓颉版实现要点 |
|---|---|---|
| `init <项目> --lang zh` | 生成项目骨架 | cjpm.toml（`cjc-version` **动态探测**自 `cjc --version`）+ `src/main.zc` 模板（`主函数() { 打印行("你好，仓颉！") }`）+ `.gitignore`（`.zhc/`、`target/`） |
| `run <文件>` | 转译 → cjc 编译 → 运行 | 单文件：转译到临时目录 → `cjc --diagnostic-format=json --output-dir ...` → 执行产物；项目模式：转译到 `.zhc/src/` → `cjpm update`（有依赖时）→ `cjc -p .zhc/src --import-path target --output-type=exe` |
| `check <文件>` | 转译 → cjc 编译检查 | 同上但 `--output-type` 保持 exe 且不运行；诊断母语化 |
| `eject <文件>` | 导出标准 .cj 源码 | 反向映射转译；**多对一碰撞报告**（同一官方词有多个母语词时，按声明处最近用词/首个命中策略输出并警告） |
| `add <库>[@版本]` | 添加依赖 | 编辑 `cjpm.toml` `[dependencies]`（git/path 形式）+ 检查 `crates/<库>.toml` 映射存在性并提示 |
| `lang list / install / remove` | 语言包管理 | 内置（随安装分发）+ 用户目录（`~/.zhc/lang-packs`）；install 支持本地目录与远程压缩包 |
| `mapping auto / check / scaffold` | 第三方映射工具链 | 见 §9 |
| `install lsp` | 安装/检测语言服务 | 检测官方 LSP 可执行文件；不可用则提示降级模式 |

实现要点（沿用蓝图 §7 并适配）：

- **文件扩展名 → 语言包路由**：扫描所有已安装语言包的 `lang_info.toml` 扩展名；未知扩展名报错并列出可用扩展名；`--lang-pack` 可显式指定目录；`lang install` 时校验**扩展名冲突**（两语言包声明同一扩展名则拒绝安装并报错）；
- **项目根定位**：从源文件向上查找 `cjpm.toml`；找不到给出 `init` 引导；
- **语言包加载优先级**：用户安装目录覆盖内置（内置目录随二进制分发，新增语言包零代码改动）；
- **界面语言**：`ZHCLANG` 环境变量切换方言语言（默认 zh，2026-09 已实现）；系统区域检测未实现（§5.5）
- **工具链版本锁定**：`init` 动态探测本机 `cjc --version` 写入 `cjpm.toml` 的 `cjc-version` 字段（必需字段），不可硬编码（对应蓝图坑 ⑬）；
- **CLI 框架**：`std.argopt` 解析；帮助文本经 ui.toml 本地化。

---

## 9. LSP 与 IDE 设计

### 9.1 三档降级策略（官方 LSP 成熟度未知）

**第一档：完整代理**（若官方语言服务器可独立启动）：

```text
编辑器 ──.zc 文件──▶ zhc LSP 代理 ──转译后 .cj──▶ 官方语言服务（子进程）
编辑器 ◀──母语诊断── zhc LSP 代理 ◀──位置/文本还原── 官方语言服务
```

- 正向：`didOpen/didChange` 收到方言文本 → 转译 → 以虚拟官方文件喂给子进程；
- 反向位置还原：官方响应的行列位置经源映射逆向折算回方言坐标（等宽零成本；不等宽按条目做列偏移模拟）；
- 响应映射器：转发请求使用自增 ID，维护 `代理ID → 原始请求` 映射，响应到达时还原 ID 并翻译内容；设 60s 超时清理防累积；
- 诊断翻译：复用引擎诊断翻译系统（与 CLI 同一套）；
- 代码动作增强：`codeAction` 请求上下文中提取未声明库名，响应时注入"添加依赖"快捷修复；
- 扩展名可配置：默认清单与内置语言包一致，`--extensions` 参数覆盖。

**第二档：轮询降级**（无独立 LSP）：`didChange` 防抖（如 500ms）→ 引擎转译 + `cjc --diagnostic-format=json` 检查 → 翻译 → `publishDiagnostics`（位置经源映射还原）。适合教学场景，丢失增量补全/悬停/跳转。

**第三档：仅高亮**：tmLanguage 由脚本从语言包自动生成（关键字/类型/宏节注入正则），保证映射表与高亮永不漂移。

档位判定：`install lsp` 与扩展启动时探测官方 LSP 可执行文件与能力声明；运行时自动降级并提示用户。

### 9.2 IDE 扩展设计（VS Code）

1. **语言注册**：`.zc` → 方言语言 id（每语言包一个），语言包扩展名清单动态注册；
2. **全角符号自动转换**：中文输入法的全角标点（`（），；：`）在代码上下文自动转半角，词法状态机区分字符串内外（字符串内保留原文，配对引号场景特判）；
3. **右键运行/检查**：终端发送 `zhc run <文件>`；Windows 必须处理 PowerShell 语法：带引号的可执行路径需 `& ` 调用操作符前缀（对应蓝图坑 ④），参数按平台引用转义防注入；
4. **依赖添加命令**：封装 `zhc add`；
5. **LSP 客户端**：启动 zhc LSP 代理（可执行文件解析跨平台：PATH 扫描 + PATHEXT 后缀探测 + 用户主目录回退）；
6. **AI 辅助翻译**（可选增值）：选中文本调用 LLM 提供方把标准代码译为方言。

**实现状态（2026-08 后续交付物 ✅）**：扩展落地位 tools/vscode-extension/（职责 1-5）：语法高亮由 tools/gen_highlight.py 从语言包生成 tmLanguage（关键字/类型/函数/宏 分节 + 中文词边界 `\p{L}` 断言，与映射永不漂移）；全角转换词法状态机保护字符串与注释（输入时自动 + 命令整篇转换，单元验证 7/7）；右键运行/检查走终端（PowerShell `& ` 前缀）；LSP 客户端行帧协议驱动 zhc lsp（诊断 publishDiagnostics 收集，zhc 不可用自动降级提示）；可执行解析 PATH + PATHEXT + 主目录回退。职责 6（AI 翻译）作为可选增值留待社区接入。

---

## 10. 映射质量工具链

母语映射是社区共建的，质量门禁必须自动化（照抄蓝图 §10）：

| 工具 | 检查项 |
|---|---|
| `mapping check` | ① 同文件重复键 ② 母语词与关键字碰撞（`让` 不能再当库别名）③ 跨文件同键不同值 ④ 跨语言条目数一致性 ⑤ TOML 解析合法性 |
| `mapping auto <库>` | 提取已安装库的公开 API（解析源码声明或 .cjo AST，实测 后定）→ 规则/LLM 生成母语名与解释 → 写 `crates/<库>.toml`，可 `--install` 顺带加依赖 |

**实现状态（s5t9b ✅）**：`zhc mapping auto <库目录> [--install <库名>=<路径>]`——提取 .cj 公开 API（func/let/var/const/class/struct/interface/enum/type/macro；逐行启发式扫描 + 块注释跨行状态机 + 行注释剥离，不解析 AST，std.ast 1.0 无公开 API）→ 生成 crates/<库>.toml（键 = 官方原名恒等，人工润色改键为母语）；语言包加载时 crates/ 目录最后加载覆盖同名键（社区映射优先内置，实测"求和"覆盖 stdlib 内置）；--install 复用 add 策略追加 [dependencies]（重复拒绝、节内插入）。提取质量由 mapping check 五项门禁把关。
| `mapping scaffold <源语言> <目标语言>` | 以成熟语言包为源，生成目标语言翻译骨架（英文值不动，键待译）；支持 LLM 批量翻译 + 冲突改名重试，重跑自动补齐残留 |

**确定性要求**（对应蓝图坑 ①）：多文件合并必须排序（文件名字典序），撞名时按固定优先级覆盖（后载覆盖先载，文档声明）。

---

## 11. 分阶段实现路线

按依赖顺序切分，每阶段独立可交付、可验证：

### 阶段 0：最小可运行（约 1-2 周）

> ✅ 已完成（2026-08，本机 cjc 1.0.5）：验收通过 `zhc run examples/hello.zc`。
> 入口写法依 1.0 语法调整为 `主函数()`（不带"函数"前缀，见 §13.1 第 9 条）。

- 实测清单 §13 全部 8 项（决定后续所有设计落地形态）
- TOML 子集解析器（toml_mini.cj）
- 词法器：std.ast 实测 → 可用则封装，不可用则自研保守词法器
- **zh 语言包 v0.1**：lang_info.toml + keywords.toml（主表 + 扩展词表）+ ui.toml 最小集
- keywords.toml + token 级词法转译（含字符串/注释/反引号保护、多词关键字最长匹配）
- `run` 单文件：转译 → cjc 编译（JSON 诊断解析验证）→ 运行 → 透传输出
- **验收**：`主函数() { 打印行("你好") }` 运行成功；字符串内的母语关键字不被误改；`--diagnostic-format=json` 输出可解析并回退原文

> 阶段 0 实际交付：见 [zhc/](zhc/)（src/ 四文件 + lang-packs/ + examples/）。
> 对抗样例 examples/adv.zc：@宏替换/反引号/注释与字符串保护/多词关键字均验证通过。

### 阶段 1：项目模型与检查（约 1-2 周）

> ✅ 已完成（2026-08，本机 cjc 1.0.5）：验收通过
> `zhc init 我的项目 → run src/main.zc → eject src/main.zc → cjc -p eject/src 直接编译` 全链（EXIT=0）。
> 落地要点：`init` 动态探测 cjc-version（§13.1 第 14-16 条）；项目模式判定为"项目根下 src/ 含方言源码"，
> 转译整个 src/ 到 `.zhc/src/` 后 `cjc -p` 编译（§13 实测项 #6 验证 `.zc` 混放被忽略）；
> `cjc -p` **不递归子目录**——子目录方言源码项目编译暂不支持（警告提示），eject 导出不受限。

- `init` 骨架（cjpm.toml + cjc-version 动态探测）、项目根定位、`check` 命令（JSON/文本双通道诊断）
- `eject` 导出（反向映射 + 多对一碰撞报告）
- **验收**：完整项目可 init → run → eject → cjc 直接编译 eject 产物

### 阶段 2：标准库母语化（约 2 周）

> ✅ 已完成（2026-08，本机 cjc 1.0.5）：验收通过
> `导入 标准集合.{哈希映射, 向量}` → `import std.collection.{HashMap, ArrayList}` 编译运行；
> `让 长度 = 5` 声明处与后续使用处均豁免（参数/lambda/case/for 绑定同样豁免）；
> `"值是 ${i}"` 插值段内别名与关键字均可替换（嵌套字符串/括号栈配对正确）。
> 落地要点：语言包 v0.2（module_paths.toml + stdlib.toml；类型词/常用内置从 keywords.toml
> 迁入别名表走豁免集保护）；完整管线 transpileFull = 词法（含插值态）→ import 路径
> → 别名替换（两遍扫描 + 豁免集）；eject 碰撞报告并入别名表（去重）。

- module_paths.toml + stdlib.toml + 别名替换（声明位保护 + 豁免集：声明名/成员名/参数名/模式绑定）
- 字符串插值 `${}` 插值态转译
- **AST 辅助转译 L1**：std.ast 解析方言源码 → 校验/补全豁免集 + 前置语法检查（语法错误直接母语诊断）
- **验收**：`导入 标准集合.{哈希映射, 向量};` / `向量.添加(x)` 编译通过；`让 长度 = 5` 不误替换且后续使用处豁免（回归用例必写）；`"值是 ${i}"` 插值内别名可替换

### 阶段 3：教学诊断 ✅（已完成）

- **JSON 字段实测落地**（§13.1 第 19 条）：`DiagKind` 即稳定错误码 → **errors.toml `["诊断码"]` 表启用为第一优先级**（设计 §3.7 预留位落地）；`Message` 为短消息、具体信息在 `MainHint.Content`；`Location.{File,Line,Column}` 定位
- **消息表**（`["消息翻译"]` 精确 → 最长前缀 → `~` 后缀）+ **{q0}/{q1} 捕获**（从完整消息提取引号对，避免前缀截断把闭引号当开引号）+ 动态残段拼接（模板无占位符时）
- **类型名本地化**（type_localize.cj，§7.3）：种类前缀（`Struct-`/`Class-`/`Enum-` 等译为 `结构体-`/`类-`/`枚举-`，§16.3 不剥离）+ `?` 可空保留 + 泛型递归（`Enum-Option<Int64>` → `枚举-选项<整数>`）+ 路径段三段式（modulePaths 反向表）；未知类型原样透传
- **仓颉三主题教学提示**（💡）：类型不匹配/空安全/可变性（`让`→`可变`）+ 未解析导入（依赖提示）+ 未使用变量；**诊断可粘贴修复示例**（§16.9）：教学提示附方言代码块，直接粘贴可用
- **文本兜底**（§7.1）：非 JSON 行中 `[error]`/`[warning]` 锚定行做消息表翻译，其余透传；解析失败不崩溃
- **JSON 解析加固**：括号深度**引号感知计数**（诊断消息可含 `}`/`{`，如 `found '}'`，误计导致提前退出）
- **验收**：类型不匹配/未使用/空安全/可变性/未解析导入/未收录/语法错 7 类样例全中文输出；未收录消息优雅回退原文不崩溃（`undeclared identifier 'x'` 原文透传）；全链回归（run/check/eject/示例）通过
- **AST 原地替换 L2**：维持 §13.1 第 17 条结论（Token 无位置字段 → L2 受限），阶段 3 不实施

### 阶段 4：IDE 集成 ✅（已完成）

> ✅ 已完成（2026-08，本机 cjc 1.0.5）：验收通过
> 代理档（真实 pid 握手 + initialize 响应强制全量同步 + 诊断位置映射 .zc 严格对齐：3:20 ↔ LSP line=2/col=19）
> 与降级档（无官方 LSPServer → 仅诊断，stderr 提示不报错）双档全 PASS；高亮语义验证 12/12、全角转换 7/7；
> 全链回归（run/check/eject/init/项目模式/help）通过。
> 落地要点：
> - **官方 LSPServer 可独立启动但 capabilities 无 diagnosticProvider**（didOpen 后不推送任何诊断，§13.1 第 20 条）
>   → **混合档**：语言能力转发官方（补全/悬停/定义/语义 Token），诊断 zhc 自跑 cjc（位置经源映射还原 .zc
>   后 publishDiagnostics；无诊断推送空数组清标记）；
> - **仓颉 runtime 行化限制**（stdin/子进程管道的一切 read 等 \n 或 EOF，libc read(fd 0) 亦被接管，§13.1 第 21 条）
>   → 编辑器 ↔ zhc 用**行帧协议**（JSON 单行 + \n）；zhc ↔ LSPServer 写走 stdInPipe（写无行化限制）、
>   读走 **bash 重定向临时文件 + ServerStream 轮询**（File.readFrom 字节级正常，§13.1 第 22 条）；
> - **LSPServer processId=None 静默挂起**（§13.1 第 23 条）→ 编辑器必须发真实 pid/rootUri，zhc 注入 CANGJIE_HOME 族环境；
> - initialize 无响应（server 失联）自动降级：本地最小能力集接管（`{"textDocumentSync":1}`），不报错；
> - 高亮 tmLanguage 由 tools/gen_highlight.py 从语言包生成（关键字/类型/宏分节 + 中文词边界 `\p{L}` 断言，
>   与映射永不漂移）；扩展骨架 tools/vscode-extension/（行帧 LSP 客户端 + 诊断收集 + 右键运行/检查 +
>   全角转换状态机，§9.2 职责 1/2/3/5）。

- LSP 三档降级（代理/轮询/高亮）、扩展（高亮生成脚本/全角转换/右键运行/LSP 客户端/跨平台可执行解析）
- **验收**：编辑器内诊断可用且位置与方言源码严格对齐；官方 LSP 不可用时自动降级不报错

### 阶段 5：生态与规模化（持续）

- ✅ **mapping check/scaffold 工具链**（§10 落地，第一批交付）：check 五项门禁全实现（⑤ TOML 合法性 / ① 重复键 / ③ 跨节同键不同值 / ② 关键字碰撞 / ④ 跨语言一致性）；scaffold 生成语言包骨架（键 = 官方值恒等，值去重防多对一重复键）
- ✅ **第二自然语言包 en**（验证语言无关性：恒等转译，`.en` 源码原样编译运行）；✅ **语言包热安装 `lang list/install/remove`**（用户目录 ~/.zhc/lang-packs 覆盖内置，install 校验扩展名冲突）
- ✅ **`zhc add` 包管理器封装**（§3.11：向 cjpm.toml [dependencies] 节内追加条目，重复拒绝，crates/ 映射存在性提示）
- ✅ **workspace 多模块支持**（s5t7）：根 cjpm.toml 含 [workspace] 节时，run/check 转译全部方言成员（成员目录内向上查找驱动），按模块输出诊断（各自映射回方言坐标），run 依次运行可执行成员；test 对每个方言成员执行 .zhc-test/ 流程；纯官方成员跳过；成员间依赖链接留待构建钩子批次
- ✅ **`zhc lint`（cjlint 集成，§16.6，第二批）**：转译 → cjlint JSON 报告 → 源映射回方言坐标 → 母语报告（级别本地化 + 规则码透传）；`zhc test`（§16.8，第二批）：转译全部方言源码（注入 package）→ cjpm test → ANSI 剥离 + 输出母语化（用例名保留方言原名）；Unicode 安全检查（坑 ⑫，第二批）：零宽/双向控制符精确 位置告警不阻断
- ✅ **cjpm 原生构建集成**（§16.2，s5t8）：`zhc init --native` 生成 build.cj 钩子（pre-build 阶段自动转译 src 下 .zc → 同名 .cj 并补 package），`cjpm build/run/test` 直接驱动方言项目；**错误字典自生成**（§16.5，s5t8）：未命中消息记录 ~/.zhc/diag-log/，`zhc mapping check --missing` 聚合待翻译清单（消息原文 + 次数 + 示例）；**语言包编码可插拔**（§16.7，s5t8）：lang_info.toml `格式 = "json"` 时全表 JSON 加载（JsonNode 递归下降解析器），mapping check 对 JSON 包全量门禁；NFC 归一因 1.0 std.unicode 无 API 留 normalizeKey 可插拔点（§13.1 第 34 条）
- ✅ **增量缓存**（§4.3，s5t9）：缓存键 = hash64(源文本) + 语言包指纹（转译相关四表排序拼串哈希，映射更新自动失效重译）；缓存内容 = TranspileResult 序列化（JSON：转译文 + MapEntry 列表 + total），命中后重建 SourceMap（诊断坐标与未命中一致）；runSingle/buildMember/cmdNative 三路径接入，缓存位置项目 .zhc/cache/（§13.1 第 35 条溢出陷阱记录）
- ✅ **mapping auto 与第三方库映射积累**（§10，s5t9）：`zhc mapping auto <库目录> [--install <库名>=<路径>]` 提取 .cj 公开 API（func/let/var/const/class/struct/interface/enum/type/macro，逐行启发式 + 注释状态机）生成 crates/<库>.toml（恒等映射待润色）；语言包加载时 crates/ 最后加载覆盖同名键（社区映射优先内置，实测“求和”覆盖 stdlib 的 fold）；`--install` 顺带追加 [dependencies]（与 add 同策略）
- ✅ **离线发布包**（§14.3，s5t9）：scripts/release.sh 构建 → 自检（help + mapping check）→ 组装 zhc-<版本>-<系统>-<架构>.tar.gz（bin/zhc 启动脚本 + zhc-core + lib/ 仓颉运行时两 so + lang-packs + README），无网络环境解压即用（resolveLangPack 增 exeDir 父目录探测，§13.1 第 38 条）
- ✅ **双平台 CI**（§14.3，s5t9，2026-08 审计修正）：.github/workflows/ci.yml——Linux：一键全量验收 scripts/acceptance.sh（构建 + 50 项断言 + release.sh 打包 → artifact 上传）；Windows：构建 + help/mapping 自检（best-effort，产物 main.exe 适配；发布包仅 Linux，release.sh 只适配 linux_x86_64）；v 标签触发 release 工作流（SDK 安装步骤为占位，发布前替换实际渠道）
- ✅ **宏展开教学视图 `zhc expand`**（§16.4，s5t9 收尾）：1.0.5 宏链路实测打通（宏包 `macro package` 声明 + `cjc --compile-macro` 两步编译 + `--debug-macro` 生成 .macrocall），`zhc expand <文件.zc> [--macro-pkg <目录>]`：转译 → 临时工程（宏包复制 + 自动补 import）→ cjc 两步编译 → 解析 Emitted 展开区 → **反向转译母语**（词法扫描跳过字符串/注释，标识符查反向表）→ “展开前 / 展开后（官方）/ 展开后（方言）”三栏对照；宏展开后编译报错仍展示视图；crates/ 映射新增「宏」节（第三方宏母语化）

---

## 12. 风险与坑清单

### 12.1 蓝图坑清单对照（§13 逐条核对）

| # | 蓝图坑 | zhc 处置 |
|---|---|---|
| ① | HashMap 迭代顺序不确定 | 多源合并强制排序；固定优先级覆盖（后载覆盖先载） |
| ② | 英文键反向条目污染 | 构建反向映射过滤纯 ASCII 键；内部修正条目与教学条目物理分离 |
| ③ | 别名误伤用户标识符 | 两遍扫描：声明名/成员名/参数名/模式绑定豁免；`. 限定段` 除外 |
| ④ | PowerShell 带引号路径 | Windows 终端命令名统一加 `& ` 前缀，写单测 |
| ⑤ | 宏名与类型名碰撞 | `@` 宏名走独立宏映射表（宏节），不查全局关键字表 |
| ⑥ | 多词关键字拆错 | 词法阶段最长匹配/连续 token 合并（`否则如果`） |
| ⑦ | 编译器消息格式随版本漂移 | 提取逻辑双通道（字段优先、引号对兜底）；每个 cjc 大版本跑回归 |
| ⑧ | 进度行翻译失效 | 前缀匹配前先 `trim_start` |
| ⑨ | 缓存只按内容哈希 | 缓存键 = 内容哈希 + 映射表语境指纹 |
| ⑩ | 字符串/注释被误改 | 词法器必须 token 级；`${}` 插值态单独处理；对抗样例测试 |
| ⑪ | 并行测试锁竞争 | 构建类测试串行化或独立临时项目目录；环境变量测试共用进程级互斥锁 |
| ⑫ | 零宽字符注入 | 转译前扫描告警（不阻断），报告精确位置 |
| ⑬ | 硬编码工具链版本 | init 动态探测 `cjc --version` 写入 cjc-version |

### 12.2 仓颉特有风险（本设计新增）

1. **std.ast 词法 API 公开性/稳定性未知**：实测项 #2；不可用则自研保守词法器（字符串/`${}`/反引号/`@` 宏边界是底线）；自研词法器不得做语法校验。
2. **cjc JSON 诊断字段结构未知**：实测项 #1；双通道解析兜底，任何解析失败降级不崩溃。
3. **无 std.toml**：自研 TOML 子集解析器；std.regex 仅 ASCII → 母语匹配禁用 regex。
4. **静态/实例成员统一 `.`**（蓝图 `::` 保护失效）：豁免集扩展到成员名/参数名/模式绑定 + 对抗测试（`让 长度 = 5` 回归用例）。
5. **cjpm 无 add、cjc-version 必需**：add 改配置编辑；init 动态探测。
6. **官方 LSP 成熟度**：三档降级；语义着色依赖官方语言服务（官方 LSP 启动失败时只剩 TextMate 关键字着色，同蓝图注意点）。
7. **NFC 规范化**：仓颉将标识符识别为 NFC 形式——转译器查表键与源码标识符均需 NFC 归一（std.unicode 实测项 #4）。
8. **字符串插值 `${}`**：插值段是代码不是文本；括号栈配对；嵌套字符串边界列为对抗测试。
9. **仓颉 `main` 直写**：1.0 中 `func main` 是语法错误（编译器报 `'main' declaration doesn't need 'func' keyword`），入口写 `main()`/`main(args)` 且 `args` 不含程序名；方言入口约定为 `主函数()`（不带"函数"前缀），`函数` 仅用于普通函数。
10. **`cjc -p` 扩展名过滤**：✅ 已验证（§13.1 第 15 条）：忽略非 `.cj` 扩展名（方言 `.zc` 可与官方 `.cj` 混放 `src/`，§3.6 的默认隔离目录策略保留）；`cjc -p` **不递归子目录**且只接受单个包路径——子目录方言源码项目编译暂不支持（zhc 给出警告提示，eject 导出不受限），workspace 多模块支持留待阶段 5。
11. **package 声明**：仓颉源码可含 `package 名` 声明（`macro package` 等）——方言 `包` 关键字映射后原样保留，包名不参与替换（包名是用户命名空间）。
12. **仓颉版本分裂（0.53.x vs 1.0.x）**：✅ 已验证（§13.1）：标准库包名与 API 差异巨大（std.process vs std.os.process、Environment.get → getVariable、ProcessBuilder → executeWithOutput、File.open 消失、String 下标变字节语义、Rune 字面量 r'x'、HashMap.put → add、`x!` 解包消失等）；应对：zhc 自身 cjpm.toml 声明最低 cjc-version，运行时驱动探测 `cjc --version` 并按大版本切换工具链适配，每个 cjc 大版本跑回归（对应蓝图坑 ⑦）。
13. **get/set 上下文词**：`获取`/`设置` 全局替换为 get/set（非关键字、仅在 prop 块内有语义）；用户同名声明靠豁免集保护，但 `匹配` 模式中的 `case 获取(值)` 若用户未声明会误替换——低概率，列入对抗用例与教学文档。
14. **AST 辅助转译依赖 std.ast**：节点源区间/遍历 API 是否公开决定 L2 可行性（实测项 #2，关键路径）；方言源码必须可被 std.ast 解析（成立：方言词均为合法标识符）；std.ast 随 cjc 版本演进的 API 变动（每个大版本跑回归）——三档降级 L0/L1/L2 保证任何失败回退不阻断。

---

## 13. 阶段 0 前置实测清单（实现启动即执行）

> 实测状态（cjc 1.0.5，2026-08）：✅ 已验证并落地 / ⚠️ 部分验证 / ⬜ 未测（延后）

1. ✅ `cjc --diagnostic-format=json` 实际输出结构（结论见 §13.1 第 1 条）
2. ✅ `std.ast` 词法/节点区间 API（结论见 §13.1 第 17 条）：`cangjieLex`/`parseProgram` 公开可用，`Token.kind`/`Token.value` 可读；**Token 无位置/行号字段** → L2 精确源映射受限，L1（前置语法检查 + 词法辅助）可行
3. ⚠️ 字符串字面量语法全集：`"..."`/`'c'`/`r"..."`/`"""`/`${}` 插值已实测；`f"..."` 格式化串未用（阶段 0 不涉及）
4. ⬜ `std.unicode` XID/NFC API（阶段 0 用 `r >= Rune(128)` 保守兜底，阶段 2 前实测）
5. ⬜ stdx 的 toml 解析（阶段 0 已自研 toml_mini.cj 子集解析器，可用性未确认）
6. ✅ `cjc -p` 扩展名过滤（结论见 §13.1 第 15 条）：只编译一层目录内的 `.cj` 文件，忽略 `.zc` 等其它扩展名
7. ✅ 官方 VSCode 插件含可独立启动的语言服务器二进制（`tools/bin/LSPServer` 可独立启动，initialize 返回完整能力）
8. ⬜ cjpm 依赖布局（未涉及，阶段 1 引入依赖时实测）
9. ✅ cjpm 自定义构建钩子（§16.2，阶段 5）：结论见 §13.1 第 32 条
10. ✅ cjc 宏展开产物 `.macrocall`（结论见 §13.1 第 39 条，阶段 5）

### 13.1 实测记录（cjc 1.0.5，阶段 0 交付时固化）

1. **JSON 诊断**：`--diagnostic-format=json` 输出多行格式化 JSON 到 **stderr**；顶层 `Diags[]` 数组，字段 `Message`（大写，通用信息）、`MainHint.Content`（具体信息，如 `expected 'Int64', found 'Struct-String'`）、`Location.{File,Line,Column}`（行号列号与转译产物对应，做源映射折算）；末尾 `Num.{Errors,Warnings}`。zhc 提取 Message + 非空 Content 两通道（§16.5 错误字典前身）。
2. **String 1.0（0.53 差异最大处）**：`s.size` 是**字节数**；`s[i]` 返回 **UInt8 字节**；`s[a..b]` 是**字节切片**（切到多字节字符中间抛 `Invalid utf8 byte sequence`）；`trim()`/`substring()`/`slice()` 不存在 → `trimAscii()` + 字节切片；`indexOf`/`lastIndexOf` 返回 `?Int64`（**字节偏移**，未找到为 None）；`split(sep, removeEmpty!)` 返回 `ArrayList<String>`；`toRuneArray()`/`String(Array<Rune>)` 构造为中文安全操作的基础；**单引号 `'x'` 是 String**（不是 Rune）。
3. **Rune 1.0**：字面量 **`r'x'`**（r 前缀）；构造 `Rune(97)`；方法仅有 `isAsciiLetter()`/`isAsciiNumber()`（isLetter/isDigit/isWhitespace/isAsciiDigit 均不存在）；中文/非 ASCII 判断用 `r >= Rune(128)`；支持 `==`/`>=` 比较与插值。
4. **HashMap 1.0**：写入用 **`add(key, value)`**（put/insert/set/update 均不存在）；下标 `m[k]`/`m[k] = v` 可用；`get`/`keys`/`contains`/`size` 不变。**`Option<自定义类>` 不支持 `==` 比较**（`lang == None` 编译报错，String/Int64 的 Option 可以）→ 一律用模式匹配或 `getOrThrow()`。
5. **Option 1.0**：**`x!` 强制解包已删除**（`!` 是逻辑非）→ `getOrThrow()` 或 `match` 解包；`getOr()` 不存在。
6. **std.fs 1.0**：顶层 `exists(Path)`（File.exists/Directory.exists 消失）；`File.readFrom(path)`（接受 String 或 Path）返回 `Array<Byte>`；`File.writeTo(path, bytes)` **覆盖写**（`File.create` 对已存在文件抛 `The file already exists!`）；`File.open` 不存在；`Directory.create(path, recursive: true)`（1.0 命名参数写法，`recursive!` 是语法错误；目录已存在抛异常，先 `exists` 判断再建）；`Path.of` 不存在 → `Path("...")`。
7. **std.process / std.env 1.0**：`ProcessBuilder`/`Process.runOutput` 均废弃 → 顶层 **`executeWithOutput(cmd, args): (Int64, Array<Byte>, Array<Byte>)`**；`Environment.get` → 顶层 **`getVariable(key): ?String`**；`main(args)` 中 **args 不含程序名**（args[0] 即第一个参数）。
8. **main 入口 1.0**：`main()`/`main(args: Array<String>)` 均合法，**不带 func 关键字**（`func main` 报 `'main' declaration doesn't need 'func' keyword`）；返回类型可省略；无 return 默认 0。
9. **cjc 单文件编译**：`--output-dir` 目录**必须已存在**；产物固定名 **`main`**（+ default.cjo）；`--output <名>` 可改名。
10. **cjpm 1.0**：std 子包依赖用 `[target.<triple>] path-option = [".../modules/linux_x86_64_cjnative"]`（`[dependencies]` 键名带点会被 TOML 解析为嵌套表）；**增量缓存陷阱**：改源码后必须 `cjpm clean`，否则复用旧产物假成功；可执行产物在 `target/release/bin/main`。
11. **语法杂项**：`quote` 是关键字（不可作参数名，可用反引号转义或改名）；**块注释可嵌套**（注释内出现 `/*` 会开启内层，需匹配关闭）；`Exception` 子类写法不变（`class X <: Exception { init(m) { super(m) } }`），`e.message` 可用；`main()` 内直接写中文标识符（`let 问候`）合法。
12. **1.0 版本分裂应对落地**（§12.2 风险 12）：zhc 全部源码已按 1.0 API 编写并在本机编译运行验证；后续大版本升级需按 §13.1 重新回归。
13. **隔离目录命名**：阶段 0 单文件模式实现为 `.zhc-run/`；**阶段 1 已统一为 `.zhc/`**（单文件与项目模式一致，gitignore 双写兼容）。
14. **目录列举与文件信息（std.fs 1.0，阶段 1 实测）**：`Directory.list`/`listFiles`/`readDir`/`walk` 均不存在，用 **`Directory.readFrom(path): Array<FileInfo>`**；`FileInfo.name`（文件名，无 fileName）、`FileInfo.isDirectory()`（方法非属性）；`ArrayList.remove` **仅接受 Range**（`remove(size - 1..size)`，无按索引删除）。
15. **`cjc -p` 包模式**（§13 实测项 #6 结论）：只编译**一层目录**内的 `.cj` 文件（忽略 `.zc` 等其它扩展名），**不递归子目录**；命令行只接受一个 `-p` 路径（多个报 `expect exact one package path to build`）；产物为 `default.cjo`（中间）+ `main`（可执行）；`--output-dir` 目录同样必须已存在。
16. **阶段 1 工具 API**：`SymbolicLink.readFrom("/proc/self/exe")` 返回可执行文件绝对路径（Linux，语言包可执行旁定位）；项目根定位用 `PWD` 环境变量把相对目录转绝对（`"."` 的父目录是自身，纯相对路径无法向上查找）；`cjc --version` 输出 `Cangjie Compiler: 1.0.5 (cjnative)`，版本号取 `Compiler:` 后到空白/括号前的 token。
17. **std.ast 公开性（§13 实测项 #2，阶段 2 实测）**：`cangjieLex(String): Tokens` 词法入口、`parseProgram(Tokens): Program` 解析入口、`Token.kind: TokenKind`（FUNC/IDENTIFIER/INT64/RETURN 等）+ `Token.value: String`（token 原文）全部公开可用；**Token 无 offset/line/col 等位置字段**（text 不存在）→ L2 原地替换的精确源区间不可得，L1（前置语法检查 + kind 辅助）可行；方言源码（含中文标识符）可直接 `parseProgram` 解析（方言词均为合法标识符）。
18. **类成员声明 1.0（阶段 2 实测）**：类体内 `prop x: Int64` 裸声明报 `property can not be abstract`——prop 必须带 get/set 实现块；普通可变成员用 `var`（`var x: Int64`，可与 `this.x` 赋值）；`init(...)` 是构造函数（`初始化` 已入关键字表）；`HashMap` 无 `new()`/`put`，构造用 `哈希映射<K, V>()`、写入用 `add`（stdlib.toml 别名 `放入`/`添加` → `add`）。
19. **诊断翻译实测（阶段 3）**：`DiagKind` 字段即稳定错误码（`sema_mismatched_types`/`chir_dce_unused_variable`/`parse_expected_character`/`sema_cannot_assign_to_immutable`/`package_search_error` 等），errors.toml `["诊断码"]` 表按此键命中；**诊断消息文本可含花括号**（如 `found '}'`）→ JSON 深度计数必须引号感知（字符串内 `{`/`}` 不计，`\"` 转义不切换字符串态），否则诊断对象提前闭合、尾部 `Num` 字段透传；可空类型是**前缀式 `?T`**（`Int64?` 报 `expected ';' or '<NL>', found '?'`）；**String 下标返回 UInt8 字节**（不是 Rune，`"${s[i]}"` 输出十进制码点如反引号 = `96`）→ 取字符必须走 `toRuneArray()` 或 `indexOf` 字节偏移切片；类型诊断带种类前缀（`Struct-String` 黄金样例）且泛型可嵌套（`Class-Deque<Tuple<Int64, Int64>>`）。
20. **LSPServer 无 diagnosticProvider（阶段 4 实测）**：官方 `tools/bin/LSPServer` 可独立启动（仅 stdio，**不支持任何命令行参数**——`--help` 也会挂住等待 stdin，需 pkill 清理），initialize 返回完整能力（补全/悬停/定义/语义 Token/代码操作等），**capabilities 无 diagnosticProvider 键**——didOpen 后不推送任何诊断（发送方静默丢弃）→ zhc 混合档：诊断自跑 cjc 推送；初始化参数缺 `processId`（None）或 `rootUri` 时 **LSPServer 静默挂起不响应**（无超时、无报错，进程活着）→ 编辑器必须发真实 pid/rootUri，且需注入 `CANGJIE_HOME`/`CANGJIE_HOME_BIN`/`PATH`/`LD_LIBRARY_PATH`（缺 CANGJIE_HOME 族同样静默挂起）。
21. **仓颉 runtime 行化读取（阶段 4 实测，重大）**：stdin（ConsoleReader）与子进程 `stdOutPipe` 的一切 `read(Array<UInt8>)` 都是**行语义**——等 `\n` 或 EOF 才返回；无换行的长连接数据永久阻塞（buf 大小无关）；**libc `read(fd 0)` 返回 EOF**（runtime 无条件接管/预读 fd 0，字节级旁路不可行）；std.socket 模块不存在（`std.socket` 无 bc）；std.time 无 sleep → **C FFI `foreign func usleep(microseconds: UInt32): Int32`** + `unsafe` 块调用；唯一字节级读取路径是 **`File.readFrom(path)`**。
22. **行帧协议 + 文件轮询架构（阶段 4 落地，§13.1 第 21 条对策）**：编辑器 ↔ zhc 约定**行帧协议**（每帧一行 JSON + `\n`，readLineBytes 在行化语义下恰好逐行读；帧内 JSON 由 jsonQuote 保证无换行）；zhc ↔ LSPServer：写入走 `stdInPipe`（**写无行化限制**，标准 Content-Length 帧原样），读取用 `launch("bash", ["-c", "exec '<bin>' > '<resp>' 2> '<err>'"])` 输出重定向临时文件 + ServerStream 轮询（`File.readFrom` 全读 + consumed 偏移 + `parseFrameAt` 帧解析，usleep 50ms 步进；响应文件持续增长不做截断）；`ProcessRedirect` 枚举成员仅 `Pipe/Inherit/Discard`（无 Ignore/Close，Discard 丢弃输出）；`getProcessId()`/`getTempDirectory()` 在 **std.env**（不在 std.process）。
23. **Option 元组比较（阶段 4 实测）**：`Option<(Int64, String)>` 不支持 `!= None` 比较（报 `generic type should be used with type argument`）——`?String` 可以但带元组的 Option 不行 → 一律用 `match` 模式匹配解包。
24. **TextMate 中文词边界（阶段 4 实测）**：`\b` 的 `\w` 仅 ASCII，对中文词**永不匹配**（`\b让\b` 不成立）→ 高亮正则用 `(?<![\p{L}\p{N}_])词(?![\p{L}\p{N}_])` 前后断言（Oniguruma 支持 \p{L}）；多词键按长度降序合并（`否则如果` 优先于 `否则`）；字符串/注释模式前置避免内部关键字误高亮（TextMate begin/end 区域语义）。
25. **std.fs 删除/复制（阶段 5 实测）**：顶层 **`removeIfExists(path, recursive: true): Bool`**（删除目录树，供 lang remove 用）与 **`copy(src, to: dst, overwrite: true): Bool`**（命名参数是 `to:` 前缀写法，漏写报 `missing argument prefix 'to:'`）；`Directory.copyDirectory` 存在但签名未验证，自实现逐文件递归复制（readFrom + writeTo）。
26. **mapping check 实战首轮即抓到真实缺陷（阶段 5）**：zh 语言包 `获取` 同时出现在 keywords.toml 属性访问器节（`对象.获取` → get）与 stdlib.toml 别名节（`映射.获取(键)` → get）——属性访问器是**全局 token 替换**，别名条目纯冗余 → 删除 stdlib 侧条目后示例仍经关键字通道正确转译；门禁保持严格（键碰撞即 FAIL，不因值相同放宽）。
27. **scaffold 值去重与一致性口径（阶段 5 实测）**：zh 语言包内部允许多对一同义词（`是`/`属于` → is 等），scaffold 生成键 = 官方值骨架时必须按官方值去重（否则 `is` 键重复，parseToml 抛异常）；mapping check ④ 跨语言一致性的统计口径 = **官方值覆盖集大小**（去重后），而非条目数——zh 54 条与 en 53 条因同义词差异，覆盖集均为 53 视为一致。
28. **cjlint JSON 报告（阶段 5 实测，zhc lint）**：`cjlint -f <目录> -r json -o <报告>` 输出 JSON 数组（空报告为 `[]`），元素字段 `file/line/column/endLine/endColumn/analyzerName/description/defectLevel/defectType/language`，行列 **1-based**；defectLevel 为 SUGGESTIONS/WARNING/ERROR；需 CANGJIE_HOME 环境变量且 **LD_LIBRARY_PATH 需含 $CANGJIE_HOME/tools/lib**（libcjlint.so 所在，缺失时退出码 127）；`--help` 非法须用 `-h`。
29. **std.unittest 1.0 与 cjpm test 输出（阶段 5 实测，zhc test）**：`@Test` 宏在 **std.unittest.testmacro** 包（仅 import std.unittest.* 报 undeclared）；assertEqual 签名 `(expectedStr, actualStr, expectedVal, actualVal, isDelta: Bool)` 共 6 参（前两参为描述字符串，第 5 参必须命名 `isDelta`）；**无 assertTrue**；cjpm test 文本输出**带 ANSI 颜色码**（PASSED/FAILED/SKIPPED 被 `\x1b[3xm` 包裹，尾部含 `\x1b[0J`/`\x1b7`/`\x1b[;r`/`\x1b[?25h` 等序列）——zhc 输出母语化前必须剥离 ANSI，且剥离器须按 **CSI 最终字节（0x40-0x7E）** 处理，不可只找 `m` 结尾（`\x1b[0J` 会吞掉后续文本直到 `cjpm` 里的 m）。
30. **cjpm 测试文件识别陷阱（阶段 5 实测，重大）**：src/ 下**文件名任意位置 含 "test"** 的 .cj 被 cjpm 识别为测试文件（.cjpm-history 的 `hasTestFiles=true` ），`cjpm build` 只编译产品文件——若产品代码引用其中的函数报 `undeclared identifier`，表现为"新增文件未参与编译"的假象（zhc 源码 lint_test.cj 因此报 cmdLint/cmdTest 未声明，改名 lint_tool.cj 后构建稳定）；手动 `cjc -p src` 无此区分一直成功；zhc test 转译方言测试文件命名含 test 恰好被 cjpm test 按测试文件编译，行为自洽。
31. **cjpm 1.0 workspace（阶段 5 实测，s5t7）**：`cjpm init --workspace` 生 成根 cjpm.toml（`[workspace]` 节含 `members/build-members/test-members` 数组 + compile-option/link-option/target-dir）；根下 `cjpm build` 构建**全部成员**（`-m <成员>` 指定单个），`cjpm test` 同（`--module` 亦可）；**`cjpm run` 不支持 -m** （unknown command），workspace 下 run 需进入成员目录；被依赖成员 output-type 不 能是 executable（须 static），依赖键名须等于成员包名（`pkg_b = { path = "../b" }` 相对成员目录），但静态库链接有 undefined reference 问题待解；zhc workspace 首 批不做跨成员依赖解析——成员各自独立转译 + `cjc -p` 编译（诊断按模块输出），成员目录内运行 zhc 会向上查找 workspace 根驱动全部成员（findWorkspaceRoot）。
32. **cjpm 构建钩子 build.cj（阶段 5 实测，§16.2，s5t8）**：项目根放 build.cj 即启用——cjpm build/run/test 每次在 **pre-build** 阶段自动执行（异常时报 `failed to run build script ... by operation 'pre-build'` 即钩子名）；钩子执行**先于源码编译**（钩子生成的 src 文件会被本次编译包含：实测 build.cj 写 src/generated.cj 后 main 调用其函数运行成功）；钩子编译失败或运行抛异常 → cjpm build failed（错误安全）；**main 必须显式标注 `: Unit`**（否则返回类型推断为异常类型报错）；钩子 stdout 重定向进 build-script-cache/<pkg>/bin/script-log（终端不可见，排查看日志）；`--skip-script` 禁用钩子。zhc 集成：build.cj 定位 zhc（ZHC_BIN 环境变量优先，其次 PATH）→ 执行 `zhc native`（转译 src 下 .zc → 同名 .cj，自动补 package 声明，官方 .cj 不动，.zc/.cj 并存由 cjc 扩展名过滤保证）→ 转译失败抛异常中断构建。
33. **自定义类 Option 的 `== None` 推断限制（阶段 5 实测）**：内置类型 Option（`?String`/`?Int64`）可直接 `x == None`，但**自定义类**的 Option（如 `?JsonNode`）用 `== None`/`!= None` 报 `generic type should be used with type argument`——一律用 `匹配`（match）解包；递归函数内部对自身调用的返回同样受限。另：std.sort 带比较器重载的 lambda 参数须显式类型标注、返回值无法推断（`unable to infer generic argument`），zhc 改用默认升序排序规避。
34. **std.unicode 1.0 无 NFC API（阶段 5 实测，§16.7）**：std.unicode 模块存在（libstd.unicode.bc）但无 normalize/isNormalized（试探均 undeclared）→ §16.7  的 NFC 加载时归一留可插拔点 normalizeKey（暂原样返回，标准库提供时替换实现）；JSON 编码语言包落地：lang_info.toml `["语言包"] 格式 = "json"`，各表同名 .json（结构同 TOML：keywords 两级、errors 三级），json_mini.cj 新增 JsonNode 递归下降通用值解析器（对象/字符串/数字/布尔/null/数组）加载；mapping check 对 JSON 包同样全 量门禁（覆盖集 54 与 TOML 包一致）。
35. **UInt64 运行时溢出抛 OverflowException（阶段 5 实测，§4.3/s5t9a）**：加减乘**变量运算**溢出均抛异常（编译期常量折叠也拦截；曾误判"加法回绕"——0xFFFFFFFFFFFFFF00+100 恰不溢出）；左移/异或等纯位运算无溢出检查 → hash64 用循环左移 + 黄金比例异或混合哈希替代 FNV-1a（含乘法）；String 下标返回 UInt8（第 2 条），Rune 数组操作统一 toRuneArray。
36. **cjc -p 同目录同包要求（阶段 5 实测，s5t9b）**：方言产物无 package（default 包）与官方 .cj 的命名包混编时报 `found more than one package declaration` → withPackage 从 cjpm.toml [package].name 补包名；cjpm.toml 含 toml_mini 不支持的值（`package-configuration = {}` 空内联表）会解析崩溃 → toml_mini 支持内联表存原始文本（大括号配对计数）；1.0 枚举语法为成员名直列 + `|` 分隔（`enum Color { Red | Blue }`，无 case 关键字）。
37. **String.indexOf 无起始位置参数（阶段 5 实测）**：`s.indexOf("x", from)` 不存在 → 逐 Rune 手写子串匹配（mapping_auto 的 public 关键字扫描）；`Rune` 字面量比较用 `r' '` 形式（`' '` 是 String）。
38. **离线发布包运行期依赖（阶段 5 实测，§14.3/s5t9c）**：zhc 二进制 ldd 仅 动态依赖 libcangjie-runtime.so + libboundscheck.so（std 静态链接）→ 离线包 lib/ 带这两个即可；resolveLangPack 增可执行文件父目录探测（包结构 bin/ + 顶层 lang-packs/）；release.sh 自检（help + mapping check）后打包，解压无 ZHC_LANG_PACKS 直接可 用。
39. **cjc 1.0.5 宏链路实测（阶段 5 收尾，§16.4/s5t9）**：宏**声明式宏**（非属性宏）可用，此前 `@Derive<Equatable>` 等失败是形式不对（Derive 是属性宏/未公开）；正确姿势：宏包源码首行 `macro package <名>`（独立包仅暴露宏）→ `cjc 宏包文件 --compile-macro` 生成 <名>.cjo + lib-macro_<名>.so（与宏包文件同目录，`-o` 不可与此选项同用）→ 主程序 `import <名>.*` 后 `cjc main.cj -o main` 自动发现展开；宏定义 `public macro 名(input: Tokens): Tokens`，参数/返回均 Tokens；调用 `@名(...)`；quote(...) 内 `$(expr)` **仅在代码位置插值**（字符串字面量内不插值），基本类型插值为字面量 token、Tokens 直接嵌入；`--debug-macro` 生成 <文件>.cj.macrocall（宏体真实执行），展开区带 `Emitted by MacroCall @名 in 文件:行:列` 斜杠星标记与 `/* n.m */` 序号注释；**println 1.0.5 仅单参数**（`println("a", 7)` 报 extra argument given for parameter list '(UInt64)'），多段输出用 `print($(s) + " = ")`（String 的 + 为连接）。zhc expand 即基于此链路（转译 → 临时工程两步编译 → Emitted 区解析 → 反向母语对照视图）；crates/ 映射新增「宏」节支持第三方宏母语化。
40. **1.0.5 OOP/模式语法实测（2026-08 教学教程验收）**：① 继承用 `<:`（`class Dog <: Animal`，`:` 报 expected '{' or '<'）；② 子类构造用 `super(args)` 调用父类构造（`super.init(x)` 报 'init' is not a member——init 是关键字需反引号转义，正确姿势就是 super(args)）；③ 可重写方法与可继承类必须 `open`（`open func` 可见性须 public/protected；override 时基方法非 open 报 cannot override）；④ 结构体不能 open（open struct 报 unexpected modifier）；⑤ 接口成员隐含 public（显式 public 报 redundant modifier）；⑥ **带 setter 的属性须 `mut prop`**（prop 默认不可变，setter 报 immutable property cannot have setter）；getter 语法 `get()`（无括号报 expected '(' or '<'）；⑦ **match 模式无括号**（`case Some(v) =>`，`case (Some(v))` 报 1-element tuple pattern is not allowed）；⑧ **max/min 是顶层函数**（`max(列表)` 返回 Option，ArrayList/Array 成员 `.max()` 均报 not a member）；⑨ Result 类型在 1.0 标准库不可用（Option 默认作用域，`import std.convert.*` 也无 Result），语言包「结果」映射保留但教程不采用；⑩ **case 构造器模式豁免缺陷**（zhc 侧修复）：`case 有值(名字)` 中构造器名被当模式绑定豁免且按词形全局生效（`返回 有值(...)` 也被回滚）→ collectExempts 改为 caseCand 延迟决定：`(` 前不豁免、`=>` 时按「候选在别名表 → 构造器不豁免 / 否则绑定豁免」启发式处理，`case 有值(名字)`/`case 无值 =>`/`case 其他 =>` 三态全部正确。
41. **语言包补漏（2026-08）**：关键字差集检查发现缺 `super`（补「超类」）、缺 `true/false`（stdlib 已有 真/假）；常用类型缺 `Exception`（补「异常」）；zh/en 同步保持 mapping check 跨语言一致性门禁。
42. **unittest 测试写法与 zhc test 验收（2026-08）**：官方 1.0.5 测试框架需**双通配符导入**（`import std.unittest.*` + `import std.unittest.testmacro.*`，缺一不可；`{Test}` 花括号导入报 not accessible、`@test` 小写报 undeclared）；断言用 `@Expect(实际, 期望)` 宏（`assertEqual` 2 参不可用，仅 6 参重载）；`@Test` 宏展开需 std.unittest 的运行时类型（TestClass/Configuration 等），故不可只导 testmacro。方言侧：语言包 [宏] 节补「期望 → Expect」（zh/en 同步）；zhc test 全链路验收通过（转译 → cjpm test → 母语化输出 `[ 通过 ] 用例：…`/`汇总：共 2`）。配套：gen_highlight.py 修正宏节归属——keywords.toml [宏] 节键不再并入关键字表，改为 `@前缀` 宏高亮（宏 0→3，关键字 58→55），与 langpack.cj 加载语义严格一致。
43. **@Expect 内 `== None` 泛型推断失败（2026-08，zhc 自身单元测试）**：`@Expect(匹配(...), None)` 宏展开为泛型 `expectEqual(实际, 期望)` 后，`None` 一侧**无法推断类型参数**（`generic type should be used with type argument`，与第 33 条自定义类 Option 同源）→ 断言 Option 一律用模式匹配辅助函数（testutil.cj：`isNoneOpt<T>/isSomeOpt<T>` 对 Option<T> 做 `匹配` 解包），实测 50 用例全部可行。另：测试文件与 main.cj **同包共存**于 src/（`package zhc`），`cjpm test` 自动发现 `@Test` 函数、`cjpm build` 不受影响；测试源码含 `${}` 时**仓颉编译期即做字符串插值展开**（未声明标识符报错）→ 构造含 `$` 的测试输入用 Rune 拼接（`String([r'$'])`），勿写字面量。
44. **scanAliasString 字符串保护缺陷（2026-08，alias 单元测试驱动发现并修复）**：别名替换的字符串扫描函数 start 指向开引号本身，但循环首字符 `"` 即命中闭引号分支**立即返回**——字符串内容整体落入代码态被别名替换（`打印行("打印行 向量")` 内两个词被误替换），教学样例字符串内容恰好不在别名表所以验收未暴露。修复：进入循环前先输出并跳过开引号，循环只认闭引号；修复后 `主函数() { 打印行("打印行 向量") }` 替换计数 4→2。**教训：字符串/注释保护类函数的边界测试（内容含待替换词）必须覆盖，勿只测内容不在映射表的情况。**
45. **诊断翻译三路径本地化一致性（2026-08，生产级审查发现并修复）**：translateDiag 的三条路径对消息的处理不一致——消息表路径与回退路径都会对输出做 `localizeText`（类型本地化/反向映射），唯独**错误码表路径** `fillQuotes` 后直接输出（`{q0}` 引号内容保持官方名：`缺少程序入口 \`main\``、`超出类型 \`Int64\``）→ 补 `localizeText(fillQuotes(...))` 后统一为「主函数」「整数」。另：`localizeType` 原不支持括号包裹的参数列表（`(Int64)`）→ 新增 ②.5 分支：剥括号后按顶层逗号拆分逐个本地化再还原（`(Int64, String)` → `(整数, 字符串)`）。**教训：同一决策链的多条路径行为必须一致，且引号内动态内容也要过本地化。**
46. **官方错误码全集与覆盖策略（2026-08，生产级审查实测）**：cjc 1.0.5 二进制 strings 提取 DiagKind 约 **693 个**（sema_/parse_/chir_/lex_/link_ 等前缀）；错误码表与消息表覆盖只能覆盖高频子集（实证 18 个常见场景），**回退机制（原文透传 + 类型本地化 + diag-log 记录 + mapping check --missing 清单）保证不崩溃不瞎译**；生产级做法：高频场景固化为验收回归门禁（12 个场景断言母语片段，防英文回退回归），低频错误靠 diag-log 社区闭环持续积累。官方消息形态逐字匹配验证方法：`strings cjc | grep` 对照（如 `missing argument for parameter list '%s' in call`、`'%s' is immutable`）。
47. **错误码全集落地：644 条 DiagKind 全翻译 + `{q0?}` 可选动态值（2026-08）**：cjc 1.0.5 二进制 strings 精确提取 DiagKind 全集 **644 条**（sema 394 / parse 175 / lex 41 / chir 34；此前估 693 含非错误码噪音）。errors.toml 诊断码 14→645 全收录（644 官方 DiagKind + 1 方言自定义 `package_search_error`）：13 条官方精翻（模板含 `{q0}` 引号提取 + 教学提示 + 修复示例） + `package_search_error` 方言精翻 + 631 条自动条目——**纯中文模板** = 「翻译{q0?}」：`{q0?}` 为 fillQuotes 可选动态值占位符（有值 → 反引号包裹输出「 `值`」，无值 → 空串），动态值仍过类型本地化（实测 `cannot convert an integer literal to type 'Bool'` → 「不能转换字面量 `布尔`」）；`{raw}`（原文全文透传）保留兼容但自动条目不再使用，输出零英文残留。生成器 `tools/gen_full_errors.py` 内置 FULL_KINDS 全集清单 + 校验（翻译表与清单 missing/extra 任一非空即报错退出），翻译表独立模块 `tools/diag_translations*.py` 便于后续按官方新版本 diff 增量维护；错误字典 docs/errors-dictionary.md 随之全量收录（4654 行）。**教训：手工抄写大清单必漏（本次实测漏 3 条：`sema_forin_pattern_must_be_irrefutable`/`sema_wrong_forin_guard`/`sema_wrong_number_of_arguments`），全靠生成器双集合 diff 校验兜住；且精翻条目 CURATED 与翻译表必须同源（`sema_wrong_number_of_arguments` 精翻存在但翻译表漏了，校验时只报清单缺失才会暴露）。**
48. **全中文提示审查：detail/note 行与教学提示零英文（2026-09，「任何提示都要是中文」）**：实测警告场景发现三处英文残留——① **detail 行**（`↳ unused variable`）：content 精确命中消息表时 renderEntry 仍把剔除引号后的英文残段拼在模板后（精确命中模板已完整表达）→ Match 增加 `exact` 标志，仅模糊命中（前缀/后缀键）时拼残段（信息不丢失），精确命中不拼；② **note 行**（`· this warning can be suppressed…`）：notes 原只做类型本地化不走翻译 → 改为走消息表三路径（精确/最长前缀/~后缀 + 本地化，未命中回退原文），消息表 12→20 键补警告类高频键（unused variable/import/function + this warning/error can be suppressed…/following constraints…/constraint '/may come from，模板含 `{q0}` 提取选项名：实测「此警告可通过编译器选项 `-Woff unused` 关闭」）；③ **教学提示英文对照**（`（let）`/`（var）`/`（as）`/import）→ 全部去除（`让` 绑定…`可变`；检查拼写与导入），转义序列 `\n`/`\uXXXX` 等代码形态保留。另修：`zhc --help`/`-h` 未识别报「未知命令」→ 增加 case；expand.cj「macro package 声明」→「宏包声明」。验收步骤 4 增加警告回归门禁 2 断言（detail `↳ 未使用的变量` + note `此警告可通过编译器选项`），12 场景 → 14 断言（50→52 项）。**教训：诊断输出的每一行（主消息/detail/note/教学提示）都是用户可见提示，逐一检查；消息表键设计尽量带 `{q0}` 占位符或精确键，避免模糊命中拼英文残段。**

---

## 14. 测试策略与发布流程

### 14.1 测试分层（参照蓝图实测规模：引擎 142 / CLI 68 / LSP 65 用例）

| 层 | 内容 | 仓颉示例 |
|---|---|---|
| 单元 | 每个引擎模块独立可测（std.unittest） | 词法转译/import 路径/别名豁免/缓存指纹/后缀键匹配/{q0} 捕获/类型本地化 |
| 数据 | 语言包静态校验进 CI | `zhc mapping check`（重复键/碰撞/冲突）+ TOML 解析合法性 |
| 诊断 | 黄金样例法 | 固定源码 → 固定母语诊断文本断言；覆盖消息表/前缀键/~后缀键/回退原文 |
| 端到端 | 真实编译 | 构造含目标警告/错误的临时项目跑 `zhc check`，断言母语输出 |
| 对抗 | 边界用例库 | 见 14.2 |

**实现状态（2026-08 ✅）**：单元层已落地 `zhc/src/*_test.cj`（12 个测试文件 + testutil.cj 辅助，与 main.cj 同包共存），**58 用例全过**，覆盖：词法（标识符/空白/scanQuoted 转义/行注释/块注释）、源映射（rune/utf16 长度换算、backShift 三态、mergeMaps 偏移折算）、缓存（hash64 确定性/区分度/hexOf）、TOML（基础表/嵌套节 `["外层"."子层"]`/行尾注释/空白行）、JSON（转义/None/数字/数组切分/引号输出）、诊断匹配（精确/最长前缀/~后缀锚定/None 四分支 + extractQuoted 捕获 + {q0} 填充）、类型本地化（Struct- 前缀/嵌套泛型黄金样例/可空/未知回退/括号参数列表）、**反向映射（三表合并/关键字表优先/碰撞报告/确定性，4 用例）**、**语言包加载（真实 zh 包全量回归——645 条诊断码大 TOML 解析/en 包对称/缺目录回退/jstr，4 用例）**、**别名替换（转译引擎核心：基础替换/类型签名/声明名豁免/字符串反引号保护/for-case 绑定豁免/插值递归/点段替换，9 用例）**。诊断层：**错误翻译黄金样例回归门禁**（验收步骤 4：12 个高频场景断言母语片段，防英文回退回归）；错误码表 14 条 + 消息表 12 键（2026-08 生产级补齐：sema_undeclared_type_name/sema_redefinition/sema_generic_type_without_type_argument/sema_exceed_num_value_range/parse_expected_right_delimiter/lex_unrecognized_escape/sema_missing_entry/sema_wrong_number_of_arguments + missing argument/unclosed delimiter/redefinition of/undeclared type name/generic type should be used/unrecognized escape/~ is missing 兜底键；官方消息形态逐字匹配，strings 验证）；错误码表路径补 localizeText（§13.1 第 45 条三路径一致性）。纳入验收脚本步骤 9 与 CI（acceptance.sh 断言 `PASSED: 58`）；测试驱动修复真实缺陷 3 处：parseToml 行尾注释（闭合引号截断法）+ scanAliasString 字符串保护失效（§13.1 第 44 条）+ 错误码表路径本地化缺失（§13.1 第 45 条）。实测坑位记录 §13.1 第 43-46 条。

### 14.2 对抗用例库（仓颉特有必写）

- 字符串含全部关键字（`"打印行"` 不误改）；`${}` 插值内别名可替换、嵌套括号/字符串边界
- 反引号原始标识符（`` `让` ``、`` `如果` ``）
- 用户声明名撞库别名：`让 长度 = 5`、`函数 打印行() {}` 及其后续使用处豁免
- 参数名/成员名/模式绑定名豁免：`函数 求和(数量: Int64)`、`public let 长度: Int64`、`for (键 in 映射)`、`case 有值(值)`
- 多词关键字：`否则如果`；`@宏` 映射（`@派生`）
- 零宽字符/双向控制符注入（告警不阻断、位置准确）
- NFC 差异标识符（同一标识符的不同编码形式归一后映射命中）
- `expected 'Struct-String', found 'Class-Deque<Tuple<Int64, Int64>>'` 类型本地化黄金样例
- 未收录消息优雅回退（不崩溃、原文透传仅类型本地化）

### 14.3 发布流程与交付物清单

发布流程照抄蓝图 §14.2（版本同步、release 构建 + 全量测试、annotated tag、双平台 CI、离线发布包含 CLI+LSP+语言包）。**发布渠道（2026-09 审计修正）**：实际托管为 **GitCode 单一仓库**（gitcode.com/tan80/zwCangjie，origin 即 GitCode）——蓝图“GitHub 主仓库 + Gitee/GitCode 镜像双 remote”设想不适用，无 GitHub/Gitee 镜像；Release 附件（离线发布包 tar.gz + sha256）上传 GitCode Releases 页，install.sh 默认直链即 GitCode；离线发布包面向无网络教学环境。

**实现状态（s5t9c/s5t9d ✅）**：离线发布包由 scripts/release.sh 产出（构建 → 自 检 help + mapping check → 组装 bin/zhc 启动脚本 + zhc-core + lib/ 仓颉运行时两 so + lang-packs + docs/ 教程与错误字典 + tools/ VS Code 扩展与生成脚本 + README → tar.gz + sha256sum，解压即用无需 ZHC_LANG_PACKS）；双平台 CI 配置 .github/workflows/ci.yml（Linux：一键全量验收 scripts/acceptance.sh——构建/自检/示例/教程/expand/init/lint/test/离线包 50 项断言 + release.sh 打包，产物上传；Windows：构建 + help/mapping 自检 best-effort；v 标签触发 GitHub Release；仓颉 SDK 安装步骤为占位，发布前替换实际渠道；2026-08 审计修正端到端与 release 步骤路径错误、CI 复用本地验收脚本）。**后续交付物全部落地（2026-08）**：LSP 代理三档降级（阶段 4 已双档 + 高亮档）+ VS Code 扩展（tools/vscode-extension/：高亮/全角转换/右键运行/LSP 行帧客户端/跨平台可执行解析）、教学教程（docs/tutorial/ 九章递进，全部母语示例）、错误字典附录（docs/errors-dictionary.md，由 tools/gen_error_dict.py 从语言包自动生成）。

交付物清单（蓝图 §14.3 对照打勾）：

- [x] 引擎库（词法转译/import 路径/别名/缓存/诊断翻译/源映射/Unicode 检查/自国际化）——仓颉实现
- [x] zhc CLI（init/run/check/eject/add/lang/mapping/expand/lsp）
- [x] 语言包 ×N（至少中文完整覆盖；第二语言验证语言无关性）
- [x] LSP 代理（三档降级）+ VS Code 扩展（高亮生成/全角转换/右键运行）
- [x] 教学教程（按章节递进，全部用母语代码示例）
- [x] 错误信息字典附录（供学习者反查）
- [x] CI：cjpm build + std.unittest + mapping check + 发布工作流（多平台）

---

## 15. 项目骨架规划（zhc/）

### 15.1 cjpm.toml 模板

```toml
[package]
cjc-version = "0.53.13"   # 必需：zhc init 时由 cjc --version 动态探测填入，禁止硬编码
name = "zhc"
version = "0.1.0"
description = "仓颉方言编程框架：转译代理 + 语言包 + 教学诊断"
output-type = "executable"
compile-option = ""       # 诊断格式由 zhc 在命令行注入 --diagnostic-format=json，不写入此处

[dependencies]
# 暂无；后续如需 LLM 客户端等可在此添加 git/path 依赖
```

### 15.2 目录结构

见 §2.3。要点：

- `src/` 按 `engine / diag / toolchain / langpack / cli / lsp / util` 分包，对应蓝图 crate 划分（引擎库、CLI、LSP 三层在同一模块内以包隔离，便于早期自举阶段快速迭代；规模化后按需拆分为多模块 + 工作空间）
- `lang-packs/zh/` 随仓库分发（内置语言包），安装脚本复制到安装目录；`lang install` 管理用户目录
- `tests/` 四类测试目录 + 对抗用例库；构建类测试串行化（坑 ⑪）
- 转译产物目录 `.zhc/` 与 `target/` 均进 .gitignore

### 15.3 模块间接口示意（仓颉签名级别）

```cangjie
// engine/lexer.cj
public struct LexResult {
    public let output: String        // 转译后官方源码
    public let map: ArrayList<SrcMapEntry>  // 源映射
    public let warnings: ArrayList<UniWarning>
}
public func tokenizeAndTranslate(src: String, kw: HashMap<String, String>,
    mac: HashMap<String, String>): LexResult

// engine/alias.cj
public func collectExempted(src: String, declKw: HashSet<String>): HashSet<String>
public func replaceAliases(src: String, aliases: HashMap<String, String>,
    exempted: HashSet<String>): String

// diag/translate.cj
public func translateDiagnostic(d: Diag, pack: LangPack): Diag
public func localizeType(typeStr: String, reverse: HashMap<String, String>): String

// langpack/loader.cj
public func loadLangPack(code: String): LangPack   // 用户目录覆盖内置

// toolchain/cjc_driver.cj
public func compileWithJson(srcFile: String, args: ArrayList<String>): BuildResult

// engine/cache.cj
public func cacheKey(content: String, fingerprint: String): String  // SHA256
```

接口命名规范：引擎公共函数用英文标识符（引擎自身代码是官方仓颉，供开发者维护）；语言包数据与用户界面全中文。

---

## 16. 仓颉特性驱动的优化设计（蓝图之外）

蓝图移植只解决"能跑"；本节基于仓颉**独有**的语言与工具链特性，给出蓝图没有的框架级优化。每项标注：特性来源 / 设计 / 阶段 / 风险。

### 16.1 AST 辅助转译（核心优化，std.ast）

**特性来源**：仓颉标准库 `std.ast` 公开官方语法解析器与 Tokens（宏系统基础设施）——蓝图宿主 Rust 只能拿到 rustc_lexer 的 token 流，仓颉可以**直接调用官方解析器**，这是蓝图无法获得的语义级能力。

**设计**：三档转译策略，渐进启用：

- **L0（兜底）**：纯 token 级替换 + 保守豁免集（§5.1）——std.ast 不可用或解析失败时启用；
- **L1（AST 校验，阶段 2）**：token 级替换 + std.ast 解析方言源码，用 AST 语义校验并补全豁免集；解析失败自动回退 L0；
- **L2（AST 原地替换，阶段 3+）**：遍历 AST，利用语义上下文精确决定每个标识符是否替换——只改写标识符区间文本，注释/空白/格式原样保留（保格式）；输出与 L0 同构的源映射。

**L2 的语义上下文收益**（根治蓝图三个保守近似）：

1. **蓝图坑③（别名误伤用户标识符）**：AST 区分"绑定到用户声明的引用"与"未绑定标识符"——前者精确豁免（废除"全文件裸使用处豁免"的近似），后者才是库别名候选；
2. **字符串插值 `${}`（§3.13）**：插值表达式是 AST 节点，天然正确，废除自研括号栈；
3. **模式绑定 / 导入符号列表 / 成员访问 / 类型位置**：全部由节点类型精确识别（`case 有值(值)` 中 `值` 是绑定、`向量.添加` 中 `添加` 是成员名、`@宏名` 是宏调用）。

**前置语法检查（L1 附带收益）**：std.ast 解析方言源码失败 = 方言语法错误，解析器错误信息（官方格式）经消息表翻译后**直接以方言坐标输出母语诊断**——语法错误不再需要"转译→cjc 编译→源映射还原"的间接链路，这是 token 级方案做不到的。

**风险**：std.ast 面向宏的 API 是否暴露通用遍历与节点源区间（实测项 #2，关键路径）；方言源码必须可被 std.ast 解析（成立：方言词均为合法标识符，`@宏` 调用是合法语法）；std.ast 随 cjc 版本演进的 API 变动（每个大版本跑回归，对应蓝图坑 ⑦）。与"转译代理"范式不冲突：仍不重写编译器，仅用官方解析器做保格式的标识符重写。

### 16.2 cjpm 原生构建集成（构建钩子）

**特性来源**：cjpm 支持自定义构建机制（pre/post 处理流程，"允许开发者在构建的不同阶段增加预处理和后处理流程"）——cargo 无等价机制，蓝图 rzc 只能绕开 cargo 独立驱动。

**设计**：`zhc init --native` 生成的项目在 cjpm.toml 配置预处理钩子：pre 阶段自动转译方言源码（转译产物进隔离目录，`src-dir` 指向转译目录或约定目录），`cjpm build/run/test` 直接驱动方言项目——用户无需记忆 zhc 命令，工具链体验与官方一致。zhc 托管模式（`zhc run/check` 直驱 cjc）保持为默认与兜底。

**前提**：实测 cjpm 自定义构建机制的配置形式（实测项 #9，✅ 已落地：build.cj 钩子，§13.1 第 32 条）。

**阶段**：5。

**状态**：✅ 已落地（s5t8，2026-08）：`zhc init --native` 生成 build.cj 钩子（pre-build 自动转译 src 下 .zc → 同名 .cj 并补 package 声明），`cjpm build/run/test` 直接驱动方言项目；设计差异：转译产物写 src/ 内同名 .cj 而非隔离目录（cjc 扩展名过滤保证 .zc/.cj 并存安全，增量由每次全量转译保证）。

### 16.3 类型系统教学增强（值/引用语义）

**特性来源**：仓颉 struct 是值类型、class 是引用类型——诊断种类前缀 `Struct-`/`Class-` 正是这一区分的体现（Rust 无此诊断特征）；`?T` 空安全与 Option 是仓颉高频教学点。

**设计**：类型本地化**不剥离种类前缀**，译为母语概念（`结构体-字符串`/`类-向量`），并附语义提示：

- 值类型 vs 引用类型：赋值拷贝 vs 共享（`类` 类型赋值后修改会互相影响）；
- 空安全：`?T` 与 `T` 不兼容的诊断 → 提示解包模式（`匹配` + `有值`/`无值`）。

errors.toml 模板新增 `{种类}` 占位符，由类型本地化阶段填充。

**阶段**：3（与类型本地化同步）。

### 16.4 宏展开教学视图（zhc expand）

**特性来源**：仓颉编译器可生成宏展开产物（`.macrocall` 文件，编译期可视化宏展开结果）——蓝图宿主无此能力（Rust 宏展开需要 nightly + 额外工具）。

**设计**：`zhc expand <文件.zc>`：转译 → cjc 宏展开链路（`--compile-macro`）→ 读取展开产物 → **反向转译为母语** → 输出"展开前 / 展开后"对照教学视图。学习者直观看到宏做了什么（如 `@调试日志(...)` 展开出的完整代码）。

**实现状态（s5t9 ✅，挂起解除）**：`zhc expand <文件.zc> [--macro-pkg <目录>]`——方言文件转译（宏名经 [宏] 表替换，如 `@调试日志` → `@dprint`）→ 临时工程 ~/.zhc/expand/<hash>/src/（宏包目录复制 + 自动补 `import <宏包>.*`）→ `cjc --compile-macro` 编译宏包 → `cjc --debug-macro` 生成 .macrocall → 解析每个 Emitted 展开区（宏名/转译文行列经源映射折算回方言坐标）→ 反向转译母语（词法扫描：字符串/注释原样，标识符查反向表首命中）→ 三栏对照输出（展开前方言原行 / 展开后官方 / 展开后方言）。宏展开后编译报错仍展示视图并提示。宏包未提供时（同目录/父目录 define/ 或 --macro-pkg）报错引导。链路实测见 §13.1 第 39 条，crates/ 映射新增「宏」节（loadCratesToml/Json）。

**前提**：实测 .macrocall 生成机制与格式（实测项 #10 ✅）。

**阶段**：5（可选——已完成）。

### 16.5 错误字典自生成（社区共建闭环）

**特性来源**：仓颉无错误码体系，消息表是唯一翻译来源——需要数据反馈机制让消息表随真实使用增长（Rust 有官方错误码索引可参考，仓颉没有）。

**设计**：`zhc check` 未命中消息时提示"可提交翻译"；`zhc mapping check --missing` 扫描诊断日志（`~/.zhc/diag-log/`）生成待翻译清单：消息原文 + 出现次数 + 示例上下文（方言源码片段）。清单可直接作为 errors.toml 的 PR 素材，形成"使用 → 反馈 → 补全"闭环。

**阶段**：5。

**状态**：✅ 已落地（s5t8，2026-08）：check/run 未命中消息表时写 ~/.zhc/diag-log/diag.log（logMiss，try 包裹不影响主流程），`zhc mapping check --missing` 聚合输出消息原文 + 出现次数 + 示例 content（升序确定性排序）。

### 16.6 zhc lint（cjlint 集成）

**特性来源**：仓颉工具链自带静态检查器 cjlint（蓝图无对应物——Rust 侧 lint 是 rustc 内建警告，蓝图只翻译不扩展）。

**设计**：转译 → cjlint 检查（输出格式实测：若 JSON 则复用诊断管线，否则文本模式）→ 母语 lint 报告；`zhc init` 可生成 cjlint 配置模板。教学场景下"未使用变量 / 命名规范"类建议由 lint 通道补充。

**实现状态（✅，2026-08 后续交付物）**：`zhc lint <文件.zc> [--fix]` 两级检查——① 方言风格检查（`styleCheckFix`，教程 08.3 承诺落地）：全角标点（与 VS Code 扩展 FULLWIDTH_MAP 一致的 6 个映射：（）→() ，→, ；→; ：→:，字符串/行注释/块注释内豁免，词法状态机）、尾随空白（先跳过行尾 \r 再检测，避免被 CRLF 挡住漏报）、CRLF、连续空行（最多保留 1 个，哨兵行剔除实现）、行长度 >120（只报告不自动修）；`--fix` 自动修复前三类（参数顺序任意：`lint --fix 文件` 或 `lint 文件 --fix`）；② cjlint 集成（JSON 报告 → 源映射回方言坐标 → 母语报告，级别本地化 + 规则码透传）。仓颉实现要点：字符字面量是 String 非 Rune，Rune 比较须用 `Rune(码点)` 构造（§13.1 第 31 条）。

**阶段**：3+（cjlint 输出格式实测后）。

### 16.7 语言包编码可插拔 + NFC 加载时归一

**特性来源**：std.json 官方支持；仓颉标识符 NFC 规范化规范。

**设计**：语言包加载器接口化（默认 TOML，可选 JSON 编码，`lang_info.toml` 声明编码）；加载时对全部映射键做**一次 NFC 归一**，运行期查表零归一开销（NFC 差异标识符列入对抗用例验证）。

**阶段**：5（轻量）。

**状态**：✅ 已落地（s5t8，2026-08）：lang_info.toml `["语言包"] 格式 = "json"` 时全表 JSON 加载（json_mini.cj 新增 JsonNode 递归下降通用值解析器，errors.json 三级结构支持）；NFC 归一因 1.0 std.unicode 无 API 留 normalizeKey 可插拔点（§13.1 第 34 条）。

### 16.8 方言测试自举（dogfooding）

**特性来源**：框架本身用仓颉实现，std.unittest 齐备（蓝图引擎是 Rust，测试与方言天然隔离）。

**设计**：对抗用例库中部分用例**直接以方言源码书写**（测试即验收样例），CI 中经 `zhc run` 执行方言测试文件；`zhc test` = 转译全部方言源 → `cjpm test` → 翻译测试输出。方言写的测试用例本身就是最好的演示与回归资产。

**阶段**：1 起步（用例逐步方言化），5 完成命令面。

### 16.9 诊断可粘贴修复示例

**特性来源**：教学定位（仓颉官方强调易学性，目标用户含初学者）。

**设计**：教学提示附**可复制的方言修复代码块**（多行，直接粘贴进编辑器），而非仅文本建议；修复示例用母语关键字书写，保证学习者粘贴即可用。

**阶段**：3。

### 16.10 优化与蓝图关系的说明

保留蓝图通用骨架：语言包数据规范（§6）、诊断翻译决策链（§7）、源映射、增量缓存、IDE 全角转换、mapping 工具链——这些与宿主语言无关，直接继承。

替换与增强的全部是仓颉特性相关部分：§3 差异表 13 项（语法/工具链适配）+ §16 优化 9 项（特性增值）。**"不照搬"的判定标准**：每项优化都对应一个蓝图没有的仓颉能力——std.ast 官方解析器（§16.1）、cjpm 构建钩子（§16.2）、值/引用类型诊断前缀（§16.3）、.macrocall 宏展开产物（§16.4）、无错误码体系的数据反馈需求（§16.5）、cjlint 工具（§16.6）、std.json 与 NFC 规范（§16.7）、自举实现本身（§16.8）。

## 17. 发布平台矩阵与适配路线（路线图）

**现状**：release.sh 仅适配 linux-x86_64 并显式拒绝其他平台（scripts/release.sh 启动即检）。发布包的关键平台耦合点：

| 耦合点 | linux 现状 | Windows 待适配 | macOS 待适配 |
|---|---|---|---|
| 运行时库 | `libcangjie-runtime.so`/`libboundscheck.so` 静态名单 | 同名 `.dll`（名称与依赖待 SDK 渠道确认） | `.dylib`（install_name 路径） |
| 可执行产物 | `target/release/bin/main` | `main.exe`（命名待确认） | 同 linux |
| bin 启动器 | bash 脚本（LD_LIBRARY_PATH 注入后 exec） | 需 `.bat`/`.ps1`（PATH 注入 + 调用操作符） | 同 linux（bash 可用） |
| 验收运行 | acceptance 段 0 需要 `$CANGJIE_HOME` | SDK 安装路径/环境变量不同 | 同 linux |

**优先级判断**：教学离线包的主要场景是学校机房——Windows 占比高，故 Windows 适配价值高于 macOS；但非本框架教学核心（方言语法/诊断/工具链与平台无关），故作为路线图而非当前阶段任务。

**Windows 适配 checklist**（SDK Windows 渠道就绪后逐项实测并回填）：

1. 获取 Windows 版 SDK，确认 `bin/cjc.exe`、`tools/lib`（LSPServer.exe）、`runtime/lib/*.dll` 布局与命名；
2. 实测 `cjpm build` 产物名与 `.dll` 依赖集（`ldd` 对应物，如 dumpbin /dependents）；
3. zhc 路径探测代码（resolveLangPack/exeDir）确认支持 `\` 分隔与 `.exe` 定位；
4. 编写 `bin/zhc.bat`（+ PowerShell 版）：注入运行库目录到 PATH → 调用 `zhc-core.exe`；
5. release.sh 增加 `win-x86_64` 分支（打包 .bat 启动器 + .dll 名单 + 产物改名），去掉拒绝逻辑；
6. CI 增加 windows runner 的 release + acceptance 冒烟 job（acceptance 平台相关断言按 §14.3 跳过策略）；
7. 发布矩阵回填：`zhc-<版本>-win-x86_64.zip`（Windows 惯例 zip 而非 tar.gz）；install.sh 需 Windows 版（或指引 .bat 安装）——C9 的 install.sh 同步扩展。

**验收扩展策略**：acceptance 各段中与平台强耦合的断言（段 0 SDK 定位、段 9 发布包解压、段 10 启动器）在非 linux 平台走"已知跳过"计数而非失败，确保同一脚本可在三平台复用。

**状态**：linux-x86_64 ✅ 发布闭环（v0.1.0）；windows/macOS ⬜ 待 SDK 渠道确认后按本清单推进。

---

## 附录 A：最小引擎伪代码（仓颉版）

```text
转译管线(源码, 语言包):
    告警集 = unicode_检查(源码)
    ast = 尝试解析(源码)                        # std.ast 官方解析器；失败→ L0 纯 token 模式
    若 ast 可用:                                 # L1/L2 语义辅助（§16.1）
        豁免集 = 精确收集(ast)                   # 声明/绑定/导入符号/模式绑定/插值表达式
        语法诊断 = 解析失败信息翻译(ast)         # 前置语法检查：方言坐标母语诊断
    (输出, 源映射) = 词法转译(源码, 关键字表, 宏表, ast)   # ${} 插值态（阶段 2）；L2 原地替换（阶段 3+）
    输出 = import路径替换(输出, 路径表)         # 仅 import 语句内，. 分隔
    输出 = 别名替换(输出, 别名表, 豁免集)        # 精确豁免（L1/L2）或保守豁免（L0）；.限定段
    返回 (输出, 源映射, 告警集, 语法诊断)
```
诊断翻译(诊断行们, 语言包):
    诊断们 = 解析json或文本(诊断行们)
    反向类型表 = 构建反向映射(语言包)   # 过滤纯 ASCII 键，固定优先级合并
    对每条诊断:
        条目 = 错误码表[诊断.码] ?? 消息表.查询(诊断.消息)   # 精确→最长前缀→~后缀
        模板 = 条目 ? 填充占位符(条目.模板, 诊断) : 诊断.消息  # {期望}{实际}{q0}
        模板 = 类型名本地化(模板, 反向类型表)                 # 前缀/泛型/路径段
        追加(条目.教学提示, 翻译后的help子消息)
    返回 格式化输出(全部诊断)
```

## 附录 B：相关文档索引

| 文档 | 内容 |
|---|---|
| `dialect-framework-blueprint.md` | 架构蓝图（zrRust 生产验证），本文的唯一母本 |
| `zhc-design.md` | 本文：仓颉适配设计 |
| `zhc/` | 项目仓库（骨架 + 后续实现） |
