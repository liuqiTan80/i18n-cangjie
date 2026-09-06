# 八语演示（60 秒传播素材）

同一个「Hello」程序，八种母语各写一份——这是 zhc 最直接的演示：
**每个开发者都可以用自己的母语读代码、读报错。**

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
| `error.en.en` | 英语诊断演示 | `zhc check demo/error.en.en`（故意写错→看英语教学诊断） |

扩展名（.zc/.en/.rc/.jc/.kc/.fc/.dc/.sc）在 lang_info.toml 中声明，`zhc run/check`
按文件扩展名**自动决议语言**，无需设置 ZHCLANG。

## 60 秒录制脚本（八分屏）

1. 0-5s：开场白——"用你的母语写仓颉"；
2. 5-30s：八分屏依次 `zhc run` 八个 hello 文件，各自输出母语问候
   （`你好，仓颉！` / `Hello, Cangjie!` / `Привет, Cangjie!` / `こんにちは、世界！` /
   `안녕하세요, Cangjie!` / `Bonjour, Cangjie !` / `Hallo, Cangjie!` / `¡Hola, Cangjie!`）；
3. 30-50s：切 `error.en.en`，运行 `zhc check`——展示英语报错：`undeclared identifier`
   + 💡 教学提示 + 可粘贴修复示例；
4. 50-60s：收尾——`zhc lang list` 展示 8 语言包与档位，指向仓库与 `zhc doctor`。

## 注意

- demo 文件用各语言包**当前词表**编写；词表升级（档位变更）后请回归本目录
  （与教程验证同机制）；
- de/es/fr/ko 为 demo 档：词表以第一版为准，欢迎母语者提 PR 修订（见 docs/语言包开发.md 档位章节）。
