# zhc 示例项目（projects）

教程综合案例的**可直接运行成品**（与教程代码保持同源——改动正文代码时同步更新）：

| 项目 | 来源 | 玩法 |
|---|---|---|
| [guessing-game](guessing-game/main.zc) | 《中文仓颉程序设计》19 章综合实战（19.3 核心 + 19.5 重构） | 猜 1..100 随机数；输入数字猜测，输入「退出」结束 |
| [temperature](temperature/main.zc) | 同上 18.8 从需求到交付完整案例 | 输入摄氏度 → 输出华氏度；非数字提示「不是数字」 |

运行（仓库根 zhc/ 下，语言包自动定位）：

```bash
cd examples/projects
zhc run guessing-game/main.zc     # 猜数字（交互）
zhc run temperature/main.zc       # 温度转换，输入 25 回车
```

两项目均经 zhc 实测：完整对局（含边界输入与退出）与摄氏/华氏换算全通过
（验收见 scripts/acceptance.sh 第 5 段）。
