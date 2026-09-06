# 四语演示（60 秒传播素材）

同一个「Hello」程序，四种母语各写一份——这是 zhc 最直接的演示：
**每个开发者都可以用自己的母语读代码、读报错。**

## 文件

| 文件 | 语言 | 运行 |
|---|---|---|
| `hello.zh.zc` | 中文 | `ZHCLANG=zh zhc run demo/hello.zh.zc` |
| `hello.ja.jc` | 日语 | `ZHCLANG=ja zhc run demo/hello.ja.jc` |
| `hello.de.dc` | 德语 | `ZHCLANG=de zhc run demo/hello.de.dc` |
| `hello.es.sc` | 西语 | `ZHCLANG=es zhc run demo/hello.es.sc` |
| `error.en.en` | 英语诊断演示 | `ZHCLANG=en zhc check demo/error.en.en`（故意写错→看英语教学诊断） |

## 60 秒录制脚本（四分屏）

1. 0-5s：开场白——"用你的母语写仓颉"；
2. 5-25s：四分屏依次 `zhc run` 四个 hello 文件，各自输出母语问候
   （`你好，仓颉！` / `こんにちは、世界！` / `Hallo, Cangjie!` / `¡Hola, Cangjie!`）；
3. 25-45s：切 `error.en.en`，运行 `zhc check`——展示英语报错：`undeclared identifier`
   + 💡 教学提示 + 可粘贴修复示例；
4. 45-60s：收尾——`zhc lang list` 展示 8 语言包与档位，指向仓库与 `zhc doctor`。

## 注意

- demo 文件用各语言包**当前词表**编写；词表升级（档位变更）后请回归本目录
  （与教程验证同机制）；
- de/es/fr/ko 为 demo 档：词表以第一版为准，欢迎母语者提 PR 修订（见 docs/语言包开发.md 档位章节）。
