<p align="center">
  <img src="docs/screenshots/icon.png" width="96" alt="Pastry icon">
</p>

<h1 align="center">Pastry</h1>

<p align="center">
  <strong>macOS 剪贴板管理工具</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26.0-blue" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

<p align="center">
  <a href="#功能特点">功能</a> ·
  <a href="#安装">安装</a> ·
  <a href="#文档">文档</a> ·
  <a href="#关联项目">关联项目</a>
</p>

Pastry 用来记录历史剪贴板内容，在需要时快速唤起、搜索、预览、选择并粘贴。它是个人工作流里「临时内容回看」的一层，不建议把长期高频文本都塞进剪贴板收藏；这类内容更适合文本扩展工具，比如作者的另一个项目 [TextFlash](https://github.com/vipic/textflash)。

Vibe 的产物，但细节经过实际使用打磨。布局参考了 [Paste](https://pasteapp.io/)，功能按个人需要持续迭代。

## 界面预览

![Pastry 默认面板与搜索状态](docs/screenshots/showcase.png)

## 功能特点

- **历史剪贴板**：记录文本、链接、图片、文件等常见剪贴内容。
- **快速唤起**：默认 `Command + Shift + V` 打开面板，也可以在设置里修改快捷键。
- **键盘操作**：方向键移动选中，`Enter` 粘贴，`Delete` 删除，`Command + 1...9` 快速粘贴对应卡片。
- **搜索过滤**：`/`、`Command + F`、`Tab` 或工具栏按钮打开搜索栏，快速筛选历史记录。
- **场景备注**：任何条目都可以添加备注，临时记录当时复制这段内容的场景。
- **链接预览**：复制链接后可抓取标题、描述和缩略图，方便回看。
- **文件预览**：文件卡片支持预览和定位原始文件位置。
- **多选操作**：支持区间选择、散选、批量删除和拖拽。
- **隐私排除**：可排除密码管理器等敏感应用，避免记录其剪贴内容。
- **本地存储**：数据保存在本机，数据库使用 SQLCipher 加密。

## 基本使用

| 操作 | 快捷键 |
|---|---|
| 唤起 / 关闭面板 | `Command + Shift + V` |
| 搜索 | `/`、`Command + F` 或 `Tab` |
| 快速粘贴 | `Command + 1...9` |
| 移动选择 | 方向键 |
| 粘贴选中 | `Enter` |
| 删除选中 | `Delete` |
| 预览 / 更多操作 | 右键菜单 |

## 安装

从 [GitHub Releases](https://github.com/vipic/pastry/releases) 下载最新 DMG，打开后将 `Pastry.app` 拖入 `/Applications`。

当前项目没有开发者账号签名和公证，首次打开时可能需要在系统设置里允许运行。Pastry 会在首次执行跨应用粘贴时请求辅助功能权限；剪贴板记录和全局快捷键本身不依赖这项授权。

## 文档

- [更新日志](CHANGELOG.md)：面向用户的版本说明。
- [开发说明](docs/DEVELOPMENT.md)：本地构建、签名证书、调试部署、项目结构。
- [测试说明](docs/TESTING.md)：单测、覆盖率、快照、冒烟和性能检查。
- [发布流程](docs/RELEASE.md)：版本号、DMG、GitHub Releases、自动更新排查。
- [产品说明](docs/PRODUCT.md)：产品定位和功能细节。
- [Agent Onboarding](AGENTS.md)：给代码代理使用的架构、坑点和约定。

## 关联项目

- [TextFlash](https://github.com/vipic/textflash)：适合保存并用缩写展开长期、高频文本，与 Pastry 的临时剪贴板历史互补。
- [mac-as-code](https://github.com/vipic/mac-as-code)：可从 GitHub Releases 自动安装 Pastry 的 macOS 配置与恢复脚本。

## 许可

MIT © [vipic](https://github.com/vipic)
