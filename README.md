# android_photo_to_ios
A zero-background-drain, fully automated photo sync pipeline from Android to macOS (iCloud) via ADB. Features hardware-trigger and Wi-Fi roaming
Mac 端安装 ADB：
打开终端，运行 brew install android-platform-tools

手机端开启调试：
开启开发者模式，打开 “USB 调试”。插上 Mac 后，在手机弹窗中选择“一律允许该计算机调试”。

在~/Scripts/目录下载当前py文件

添加mac定时任务，cd ~/Library/LaunchAgents
vim com.yourname.samsungsync.plist
添加以下：
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yourname.samsungsync</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <!-- 下面这里换成你脚本的实际路径 -->
        <string>/Users/你的用户名/Scripts/sync_photos.py</string>
    </array>

    <!-- 设置环境变量确保脚本能找到 adb -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <!-- 每 60 秒执行一次检查 -->
    <key>StartInterval</key>
    <integer>60</integer>
    
    <!-- 仅在 Mac 唤醒状态下运行 -->
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
然后执行：launchctl load ~/Library/LaunchAgents/com.yourname.samsungsync.plist
