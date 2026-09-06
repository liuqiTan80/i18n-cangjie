# 九语演示（60 秒传播素材）

同一个「Hello」程序，九种母语各写一份——这是 zhc 最直接的演示：
**每个开发者都可以用自己的母语读代码、读报错。**

> `ar` 是阶段 D 首个 RTL 试点（书写方向从右到左，`lang_info.toml` 声明
> `"方向" = "rtl"`，2026-09-06 入档 demo 档）——母语编程不止覆盖 LTR 语种。

## 文件

| 文件 | 语言 | 运行 |
|---|---|---|
| `hello.zh.zc` | 中文 | `zhc run demo/hello.zh.zc` |
| `hello.en.en` | 英语 | `zhc run demo/hello.en.en` |
| `hello.ru.rc` | 俄语 | `zhc run demo/hello.ru.rc` |
| `hello.ja.jc` | 日语 | `zhc run demo/hello.ja.jc` |
| `hello.ko.kc` | 韩语 | `zhc run demo/hello.ko.kc` |
| `hello.fr.fc` | 法语 | `zhc run demo/hello.fr.fc` |
| `hello.de.dc` | 德语 | `zhc run demo/hello.de.dc` |
| `hello.es.sc` | 西语 | `zhc run demo/hello.es.sc` |
| `hello.ar.ac` | 阿拉伯语（RTL 试点） | `zhc run demo/hello.ar.ac` |
| `error.en.en` | 英语诊断演示 | `zhc check demo/error.en.en`（故意写错→看英语教学诊断） |

扩展名（.zc/.en/.rc/.jc/.kc/.fc/.dc/.sc/.ac）在 lang_info.toml 中声明，`zhc run/check`
按文件扩展名**自动决议语言**，无需设置 ZHCLANG。

## 60 秒录制脚本（九分屏）

1. 0-5s：开场白——"用你的母语写仓颉"；
2. 5-30s：九分屏依次 `zhc run` 九个 hello 文件，各自输出母语问候
   （`你好，仓颉！` / `Hello, Cangjie!` / `Привет, Cangjie!` / `こんにちは、世界！` /
   `안녕하세요, Cangjie!` / `Bonjour, Cangjie !` / `Hallo, Cangjie!` / `¡Hola, Cangjie!` /
   `مرحبا، كانغجي!`——阿拉伯语从右到左，观感对比拉满）；
3. 30-50s：切 `error.en.en`，运行 `zhc check`——展示英语报错：`undeclared identifier`
   + 💡 教学提示 + 可粘贴修复示例；
4. 50-60s：收尾——`zhc lang list` 展示 9 语言包与档位（ar 的 rtl demo 亮一行），指向仓库与 `zhc doctor`。

## 注意

- demo 文件用各语言包**当前词表**编写；词表升级（档位变更）后请回归本目录
  （与教程验证同机制）；
- ar 为 demo 档 RTL 试点：词表 v0.1.0 以示例为准，欢迎阿拉伯语母语者提 PR 修订
  （见 docs/语言包开发.md 档位章节与 RTL 试点说明）。
