# AetherKey

原生 macOS 中文拼音输入法，面向 Apple 芯片 Mac，支持 macOS 14 及以上。

[官网与下载](https://aethernative.com/apps/aetherkey/) · [使用帮助](https://aethernative.com/apps/aetherkey/support/) · [问题反馈](https://github.com/bcblr1993/AetherKey/issues)

## 功能

- 本机拼音转换、用户学习与自定义短语，无需账号。
- 候选面板跟随光标、宽度随内容调整，支持选词、翻页和展开。
- Unicode Unihan 17.0.0 字音补充：44,359 个有普通话读音的汉字，覆盖全部 8,105 个通用规范汉字。
- 中文 Emoji 关键词、智能标点、可选中英自动空格、V 模式计算和人民币大写。
- 1.0.1 起支持 Sparkle 应用内更新；支持全拼、小鹤双拼和微软双拼；暂无云同步、语音和手写。

## 安装

从 GitHub Release 或官网下载 DMG，打开「安装 AetherKey.app」并按向导操作。
在系统设置 → 键盘 → 文本输入 → 编辑中添加「AetherKey 拼音」，再从菜单栏切换。
若未立即列出，请注销并重新登录。

输入法安装到 `~/Library/Input Methods/AetherKey.app`。
用户词库位于 `~/Library/Application Support/AetherKey/user_lexicon.json`；更新保留词库。
先切换到其他输入法再移除 AetherKey；用户词库不会随卸载自动删除。

## 应用内更新

从输入法菜单或设置「更新与启动」中的「检查更新」进入；自动检查默认每 6 小时一次，可在设置中关闭。更新归档只包含输入法本体，使用 Ed25519 验证后安装并重新启动，保留个人词库与偏好。1.0.0 用户需要手动安装一次当前版本；1.0.1 及以上可直接应用内更新。支持登录后自动启动，设置页显示 macOS 实际注册状态。

Sparkle 2.10.0 使用 MIT 许可；完整许可随安装包提供。发布密钥保存在 macOS 钥匙串 `AetherKey` 账户中，不进入仓库。

## 构建与验证

使用 Xcode，打开 `AetherKey.xcodeproj`。项目配置同时保存在 `project.yml`。

```sh
xcodebuild -project AetherKey.xcodeproj -scheme AetherKey -configuration Debug test
xcodebuild -project AetherKey.xcodeproj -scheme AetherSetup -configuration Release build
```

正式发布：`scripts/release.sh`。需要有效的 Developer ID Application 身份与 Notarytool Keychain profile；通过 `SIGN_IDENTITY`、`NOTARY_PROFILE` 和 `RELEASE_OUT` 指定。该脚本按嵌套顺序签名、公证并装订票据，再生成签名公证 DMG。

字音数据可用 `scripts/build_character_lexicon.py` 从固定 SHA256 的 Unihan 17.0.0 压缩包重新生成。Unicode 数据许可随资源提供：`Resources/Unihan-LICENSE.txt` 与 `Resources/Unicode-LICENSE.txt`。源码公开供审阅；未另行声明开放源代码许可证。

### 拼音编辑与候选管理

- 通用设置可开启「四方向键选择候选」（默认关闭）：`← / ↑` 选择上一个，`→ / ↓` 选择下一个，空格确认；`Option + ← / →` 仍按音节移动拼音光标。
- 未开启时，`← / →` 在拼音串内移动，`Option + ← / →` 按音节移动，`Home / End` 到开头或末尾。
- `Delete` 删除光标前一个字母，`Option + Delete` 删除前一个音节，向前删除键删除光标后的字母。
- `↑ / ↓ / Tab / Shift + Tab` 选择候选，空格上屏，`- / =` 翻页。
- 右键候选词可置顶、取消置顶或忘记；键盘对应 `Control + Option + P / U / Delete`，作用于当前高亮词。
- 置顶与忘记按拼音分别保存，忘记会移除该拼音下的学习、自定义和置顶记录，并隐藏同名候选。需要恢复时，可在词库中心重新添加该拼音和短语。
- 整句组词保留多条词组组合，结合词典顺序、词组完整度与本机选词记录排序；不使用联网语言模型。

1.0.5 新增默认关闭的“四方向键选择候选”：开启后四个箭头都能选词，Option + 左右键保留拼音编辑。保持自适应面板与光标跟随，54 项回归及 Mac mini 真实打字测试通过。

### 双拼方案

在「AetherKey 设置 → 通用设置 → 拼音方案」选择全拼、小鹤双拼或微软双拼，也可从输入法菜单切换。默认保留全拼；正在编辑的拼音保持原方案直到结束。

- 小鹤：`nihc` → 你好、`vsgo` → 中国、`jbtmtmqi` → 今天天气。
- 微软：`nihk` → 你好、`vsgo` → 中国、`p;` → 平（`;` 是 ing）。零声母用 o，例如 `oa` → 啊、`or` → er（如二、而）。
- 支持中间编辑、按音节移动/删除、分段选词、翻页、右键置顶与忘记。学习和词库按标准拼音保存，三种方案共用。
- 双拼中 `v` 表示 zh；输入 `v` 加数字仍可使用计算器。回车提交原始按键，空格选词。

键位核对参考：[小鹤方案](https://github.com/rime/rime-double-pinyin/blob/master/double_pinyin_flypy.schema.yaml)、[微软方案](https://github.com/rime/rime-double-pinyin/blob/master/double_pinyin_mspy.schema.yaml)。
