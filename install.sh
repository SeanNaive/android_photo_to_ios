#!/bin/bash

# ==========================================
# Android to iOS 照片无感同步 - 一键安装脚手架
# ==========================================

# 颜色定义，让终端输出更有商业软件的感觉
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   Android Photo to iOS (Mac) 一键部署程序   ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""

# ------------------------------------------
# 1. 检测并安装依赖 (adb)
# ------------------------------------------
echo -e "${YELLOW}[1/4] 环境依赖检测...${NC}"
if ! command -v adb &> /dev/null; then
    echo -e "未检测到 ADB 环境，准备自动安装..."
    if command -v brew &> /dev/null; then
        brew install android-platform-tools
        echo -e "${GREEN}ADB 安装完成！${NC}"
    else
        echo -e "${RED}致命错误：未找到 Homebrew！请先安装 Homebrew (https://brew.sh/) 后再运行此脚本。${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}已检测到 ADB 环境，跳过安装。${NC}"
fi

# ------------------------------------------
# 2. 硬件级固件引导 (检测 5566 端口或强制 USB 固化)
# ------------------------------------------
echo -e "\n${YELLOW}[2/4] 设备网络调试状态检测...${NC}"
# 简单粗暴：直接抓取有没有 5566 的设备在线
if adb devices | grep -q "5566"; then
    echo -e "${GREEN}检测到局域网内已有设备开启了 5566 端口！${NC}"
else
    echo -e "${YELLOW}未在局域网内探测到无线调试设备。${NC}"
    echo -e "为实现后续的'无感拔插'，我们需要进行【首次有线固化】。"
    echo -e "👉 请现在使用 ${GREEN}USB 数据线${NC} 将您的 Android 手机连接到 Mac。"
    echo -e "👉 并确保手机已开启【USB调试】。"
    
    # 死循环等待用户插入 USB 设备
    while true; do
        if adb devices | grep -v "List" | grep -q "device$"; then
            echo -e "${GREEN}检测到 USB 设备接入！正在下发固化指令...${NC}"
            adb tcpip 5566
            sleep 2
            echo -e "${GREEN}端口 5566 固化成功！您现在可以拔下数据线了。${NC}"
            break
        fi
        sleep 2
    done
fi

# ------------------------------------------
# 3. 部署核心同步脚本
# ------------------------------------------
echo -e "\n${YELLOW}[3/4] 正在拉取核心同步代码...${NC}"
SCRIPT_DIR="$HOME/Scripts"
SCRIPT_PATH="$SCRIPT_DIR/sync_photos.sh"

mkdir -p "$SCRIPT_DIR"

# ⚠️ 注意：发布前请将下面这个 URL 替换为你 GitHub 仓库里 sync_photos.sh 的真实 Raw 地址
RAW_URL="https://raw.githubusercontent.com/kobeguang/android_photo_to_ios/refs/heads/main/sync_photos.sh"

echo "从 GitHub 下载脚本..."
curl -sSL "$RAW_URL" -o "$SCRIPT_PATH"

if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
    echo -e "${GREEN}脚本部署成功: $SCRIPT_PATH${NC}"
else
    echo -e "${RED}脚本下载失败，请检查网络或 GitHub 连通性。${NC}"
    exit 1
fi

# ------------------------------------------
# 4. 配置 macOS 原生定时任务 (launchd)
# ------------------------------------------
echo -e "\n${YELLOW}[4/4] 配置后台无感自动运行...${NC}"
echo "请选择后台尝试寻找手机并拉取照片的频率："
echo "  1) 敏捷模式: 每 5 分钟 (适合经常拍照急需在 Mac 上用的场景)"
echo "  2) 均衡模式: 每 10 分钟"
echo "  3) 养老模式: 每 30 分钟 (推荐，最省系统资源)"
echo "  4) 佛系模式: 每 60 分钟"

read -p "请输入序号 [1-4] (默认选 3): " FREQ_CHOICE

case $FREQ_CHOICE in
    1) INTERVAL=300 ;;
    2) INTERVAL=600 ;;
    4) INTERVAL=3600 ;;
    *) INTERVAL=1800 ;; # 默认 30 分钟
esac

echo "已选择频率：$((INTERVAL / 60)) 分钟。"

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.geek.androidphoto2ios.plist"

mkdir -p "$PLIST_DIR"

# 动态生成 plist 配置文件
cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.geek.androidphoto2ios</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$INTERVAL</integer>
    <key>StandardOutPath</key>
    <string>/tmp/android_sync_launchd.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/android_sync_launchd_err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

# 重新加载定时任务
launchctl unload "$PLIST_PATH" 2>/dev/null
launchctl load "$PLIST_PATH"

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}🎉 部署大功告成！${NC}"
echo -e "后台守护进程已启动，系统将每隔 $((INTERVAL / 60)) 分钟静默探寻您的手机。"
echo -e "如需查看执行日志，可输入命令: ${YELLOW}tail -f ~/Scripts/synced_photos.log${NC}"
echo -e "${GREEN}==============================================${NC}"
