# 三方库移植（翻译）说明

本目录记录把仓颉生态（Cangjie-TPC，<https://gitcode.com/Cangjie-TPC>）中的优秀  
第三方库**移植到 zhc 方言体系**的分析与使用说明。移植产物是  
`libs/zh/crates/<库名>.toml` 方言映射（规范源）——合并后经  
`scripts/sync-libs.sh` 同步进语言包运行时镜像，所有 zhc 用户即可用母语  
import 与调用这些库。

## 已移植库

| 库      | 版本    | 功能                           | 映射规模 | 说明文档                   |
| ------ | ----- | ---------------------------- | ---- | ---------------------- |
| csv4cj | 1.0.4 | CSV 解析/读写，支持中文、GBK、注释行、自定义格式 | 73 键 | [csv4cj.md](csv4cj.md) |
| ini4cj | 1.0.4 | INI 配置解析，五类类型安全取值 + 溢出检查     | 25 键 | [ini4cj.md](ini4cj.md) |

## 移植方法论（后续贡献者可复用）

1. **分析**：克隆三方库源码，盘点 `public` 类型/常量/方法与依赖（`grep -n "^public" src/*.cj`），确认依赖是否仅官方 `std.*`/`stdx`；
2. **翻译**：按 `libs/README.md` 质量守则写 `<库名>.toml`——键 = 母语名、值 = 官方原名；只译有语义边界的名字，通用短名（get/size/print…）恒等保留；
3. **验证**（无 SDK 即可全部执行）：
   - `python3 scripts/check-libs.py` —— 格式 / 撞词表 / 双目录一致；
   - `python3 scripts/verify-libs-api.py` —— 每个"值"全词命中三方库源码（防杜撰 API）；
   - `bash scripts/sync-libs.sh` —— 同步运行时镜像并复检；
   - 有 SDK 时追加：`cd zhc && ZHC_LANG_PACKS=$PWD target/release/bin/main mapping check`；
4. **文档**：本目录下补 `<库名>.md`（功能模块/核心接口/依赖/差异说明/方言示例/测试）。

## 与直接抄源码移植的差异说明

zhc 的「移植」是**接口映射移植**而非源码复制：三方库仍以原生 cjpm 依赖参与编译，  
映射只负责把方言源码中的母语标识符转译为官方名。好处是库升级零成本、类型系统与  
错误处理行为与原库完全一致；代价是映射必须与官方 API 严格对齐——这正是  
`check-libs.py` + `verify-libs-api.py` 两道测试守住的点。

