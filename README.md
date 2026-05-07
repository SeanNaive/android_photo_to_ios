# Android to iOS (Mac) Photo Sync 📸

可能是最硬核的安卓转 Mac / iCloud 照片无感同步方案：基于 ADB 与 macOS 原生状态机，零后台耗电，支持局域网动态漫游。

## 💡 为什么要做这个项目？ (Why not Third-party Apps?)

传统的跨生态同步软件（如 Syncthing, Resilio Sync, 或者各类网盘）都有一个致命的架构缺陷：**它们需要在 Android 手机端常驻一个后台进程**。
这意味着你的手机必须长期持有一个唤醒锁 (Wakelock)，这不仅会消耗宝贵的电量，还会被现代 Android 严苛的电源管理机制频繁杀后台，导致“必须打开 App 才能同步”的伪自动体验。

本项目采用了**“主客体反转”**的架构思路：
* **手机端（被动客体）**：绝对纯净，不安装任何第三方 App，零后台，零耗电。
* **Mac 端（主动控制）**：作为超级节点，通过原生底层守护进程 (`launchd`) 与局域网端口嗅探 (`netcat`)，在手机接入同一 Wi-Fi 时，主动下发 `adb pull` 探针将照片拉回，并自动导入 iCloud。

## ✨ 核心特性 (Features)

* 🚀 **极致省电**：Android 端 100% 零后台，彻底告别电量焦虑。
* 📡 **无感漫游嗅探**：手机 IP 变了？没关系。Mac 端脚本通过原生 `nc` + `arp` 广播，毫秒级扫透局域网，自动定位你的手机。
* 🍏 **纯血原生架构**：抛弃繁重的 Python/Node.js 运行环境。采用纯正 `Zsh` + `AppleScript` 编写，由 macOS 操作系统级 `launchd` 精准调度，资源占用几乎为零。
* 🔗 **全自动入库**：不仅把照片拉到硬盘，还会自动调用 AppleScript 无感导入 macOS 原生「照片」App，瞬间同步至你的 iPhone/iPad。

## 🚀 一键极速部署 (One-Line Installation)

你不需要去关心怎么写定时任务，只需打开 Mac 的终端 (Terminal 或 iTerm2)，粘贴并运行以下这行代码即可：

```bash
curl -sSL https://raw.githubusercontent.com/kobeguang/android_photo_to_ios/main/install.sh | bash
