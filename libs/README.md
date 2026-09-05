# zhc 翻译众包平台（libs/）

**目标**：让「第三方库的方言翻译」从个人 AI 初稿变成**众人审校、人人受益**的公共资产。

zhc 用 AI 自动翻译第三方库 API（`zhc translate`）后，翻译质量取决于模型——
入库前缺少人工审校，共享靠拷贝目录，没有协作通道。本目录就是答案：

> **任何人**都可以把自己（或 AI）翻译好的第三方库映射放进 `libs/zh/crates/`，
> fork 仓库 → 提 Pull Request → 自动门禁检查 → 维护者合并 → 同步进语言包
> 运行时镜像（`zhc/lang-packs/zh/crates/`）→ 所有 zhc 用户都能用母语 import 这个库。

仓库托管于 **GitCode（主）与 GitHub 镜像（i18n-cangjie，参与入口）**，两边内容
双向同步；GitHub Actions 自动跑本平台门禁，贡献者提交即见结果。

## 目录与两区划分

```
libs/
└── zh/
    └── crates/          # ★ 开放区：第三方库翻译映射（众包 PR 入口）
        └── libdemo.toml # 种子示范（人工润色 + 质量守则样例）
```

**开放区**（直接提 PR，门禁自动把关）：

| 内容 | 说明 |
|---|---|
| `libs/**` | 第三方库 crates 翻译映射（唯一众包入口） |
| `zhc/lang-packs/zh/crates/` | 运行时镜像——由 `scripts/sync-libs.sh` 同步，请勿手改 |
| `zhc/lang-packs/{en,ru,ja}/` | 非 zh 语言包（不牵动 zh 教程，可 PR，需 `zhc mapping check` 过） |

**锁定区**（改动会牵动教程转译快照/错误字典/全链路，须先开 **Issue** 说明动机、
维护者批准后才由维护者修改；PR 触碰会被 `check-libs.py --locked` 拦截）：

| 内容 | 为什么锁 |
|---|---|
| `zhc/lang-packs/zh/{keywords,stdlib,module_paths,errors,ui,lang_info}.toml` | 官方词表——教程 355 个代码 token 全部依赖它，词一改教程全变 |
| `docs/中文仓颉程序设计/` | 《中文仓颉程序设计》19 章教程（词表的直接消费者） |
| `docs/术语表.md`、`docs/errors-dictionary.md` | 一词多译与错误字典基线 |

## 怎么参与（三步）

> **命令行通道（zhc ≥ 0.3.0，`zhc share`）**：本目录就是 share 命令的官方共享
> 仓库（`index.json` 为索引种子）。用户可 `zhc share fetch csv4cj` 按需下载单个
> 映射（校验和 + 门禁 + 撞词表把关后装入语言包，非全量下载）；自译成果可
> `zhc share publish` 发布到自建共享仓库（本地目录 / `tools/share_server.py`
> HTTP 端点），上传失败自动降级导出含 PR 指引的提交包。走 PR 合入本目录
> 仍是最推荐的共享方式（进入正式审查与发布流程）。

1. **翻译**：`zhc translate <库目录> --share 导出名`（AI 初稿）→ 把生成的
   `zhc-共享-导出名/lang-packs/zh/crates/<库>.toml` 复制到 `libs/zh/crates/`；
   也可以直接手写（格式见 libdemo.toml：`["标识符"]` 键 = 母语名、值 = 官方原名，
   `["模块路径"]` 可选）。
2. **润色 + 本地验证**：对照下方「质量守则」人工审校；跑
   `python3 scripts/check-libs.py`（格式/撞词表/双目录一致）与
   `bash scripts/sync-libs.sh`（同步运行时镜像）；有 SDK 时再跑
   `cd zhc && ZHC_LANG_PACKS=$PWD target/release/bin/main mapping check`。
3. **提 PR**：GitHub 镜像仓库 fork → PR → `libs 翻译平台门禁` 自动跑
   （check-libs.py + 锁定区检查）→ 维护者合并 → 全量验收（acceptance 段 2f/12）
   通过后发布。

## 质量守则（决定合并的硬标准）

1. **值 = 官方原名，永不改动**；键 = 母语名（方言代码里写键，转译时替换为值）。
2. **只翻译有语义边界的类型/常量/函数名**——crates 映射是**全局别名**：某个
   `.toml` 里的键会作用于所有方言源码，不限于 import 该库的文件。
3. **通用短名保持恒等**（如 `x`/`y`/`h`/`w`/`sum` 不译）：翻译 `x → 横坐标`
   会把所有方言代码里同名的局部标识符一并改写（示例见 libdemo.toml 头注释）。
4. **键不得撞 zh 词表**（keywords/stdlib/module_paths 键集）——crates 最后加载
   会覆盖内置映射，撞词表 = 全局改义（`check-libs.py` 自动拦截）。
5. 单文件内不得重复键；**跨库同节键也不得重复**（运行时按文件名排序后载覆盖，
   同键 = 哪个库生效取决于文件名的歧义）；模块路径值为点分段的官方路径。
6. 优先小步 PR（一个库一个 PR），方便审校与回滚。

## zhc 内置保护（为什么可以放心翻译）

- **声明豁免**：用户自己声明的标识符（变量/函数名等）在声明处与引用处都**不会**
  被 crates 映射替换——映射只作用于「库符号使用处」（未声明的直接使用：
  调用、右值、参数）。你翻译 `sum → 合计` 不会劫持别人代码里声明的 `合计` 变量。
- **全量验收兜底**：每轮验收跑《中文仓颉程序设计》全部 156+ 代码块实测（段 12），
  任何与教程代码的意外碰撞都会在合并前暴露。
- **mapping check**：语言包质量门禁（键冲突/覆盖语义），SDK 环境自动复核。

## 维护者操作手册（合并 PR 后）

```bash
bash scripts/sync-libs.sh              # 规范源 → 运行时镜像（会自跑 check-libs）
cd zhc && cjpm build                   # 变更涉及 zhc 本体时
cd .. && bash scripts/acceptance.sh    # 全量验收（段 2f 门禁 + 段 12 教程兜底）
git add -A && git commit && git push   # 推 GitCode
git push github main                   # 同步 GitHub 镜像
```

## FAQ

- **只想用别人翻译好的映射？** 合并后映射已随语言包生效——直接母语 import 即可；
  想离线分发可 `zhc translate --share` 重新导出。
- **AI 翻译的初稿也能提吗？** 可以，但请如实润色并对照守则第 2/3 条；恒等保留
  的短名要写注释说明原因（见 libdemo.toml）。
- **我的库不在 zh 词表冲突，为什么门禁还红？** 常见原因：`lang-packs` 镜像没同步
  （跑 `sync-libs.sh`）、文件里有行内尾注释（`#` 必须独占行首）、键重复。
- **错误翻译也想贡献？** 走锁定区流程（Issue 先行）；`zhc mapping check --missing` 可
  生成待翻译清单（诊断日志聚合），是现成的 PR 素材。
