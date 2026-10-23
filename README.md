# AetherKey

原生 macOS 中文拼音输入法，面向 Apple 芯片 Mac，支持 macOS 14 及以上。

[官网与下载](https://aethernative.com/apps/aetherkey/) · [使用帮助](https://aethernative.com/apps/aetherkey/support/) · [问题反馈](https://github.com/bcblr1993/AetherKey/issues)

## 功能

- 本机拼音转换、用户学习与自定义短语，无需账号。
- 候选面板跟随光标、宽度随内容调整，支持选词、翻页和展开。
- Unicode Unihan 17.0.0 字音补充：44,359 个有普通话读音的汉字，覆盖全部 8,105 个通用规范汉字。
- 中文 Emoji 关键词、智能标点、可选中英自动空格、V 模式计算和人民币大写。
- 1.0.0 暂无双拼、云同步、语音、手写和自动更新。

## 安装

从 GitHub Release 或官网下载 DMG，打开「安装 AetherKey.app」并按向导操作。
在系统设置 → 键盘 → 文本输入 → 编辑中添加「AetherKey 拼音」，再从菜单栏切换。
若未立即列出，请注销并重新登录。

输入法安装到 `~/Library/Input Methods/AetherKey.app`。
用户词库位于 `~/Library/Application Support/AetherKey/user_lexicon.json`；更新保留词库。
先切换到其他输入法再移除 AetherKey；用户词库不会随卸载自动删除。

## 构建与验证

使用 Xcode，打开 `AetherKey.xcodeproj`。项目配置同时保存在 `project.yml`。

```sh
xcodebuild -project AetherKey.xcodeproj -scheme AetherKey -configuration Debug test
xcodebuild -project AetherKey.xcodeproj -scheme AetherSetup -configuration Release build
```

正式发布：`scripts/release.sh`。需要有效的 Developer ID Application 身份与 Notarytool Keychain profile；通过 `SIGN_IDENTITY`、`NOTARY_PROFILE` 和 `RELEASE_OUT` 指定。该脚本按嵌套顺序签名、公证并装订票据，再生成签名公证 DMG。

字音数据可用 `scripts/build_character_lexicon.py` 从固定 SHA256 的 Unihan 17.0.0 压缩包重新生成。Unicode 数据许可随资源提供：`Resources/Unihan-LICENSE.txt` 与 `Resources/Unicode-LICENSE.txt`。源码公开供审阅；未另行声明开放源代码许可证。
