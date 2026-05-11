#!/bin/zsh

# ==========================================
# --- 环境变量与配置区 ---
# ==========================================
# ADB 的绝对路径 (请确保该路径正确，可通过 `which adb` 查看)
ADB_PATH="/opt/homebrew/bin/adb"

# Android 设备的无线调试端口 (我们之前固化的 5566 端口)
PHONE_PORT="5566"

# 需要同步的 Android 远程目录
REMOTE_DIRS=("/sdcard/DCIM/Camera/" "/sdcard/DCIM/Screenshots/" "/sdcard/Pictures/WeiXin/")

# 只同步该时间之后拍摄/生成的照片，格式: YYYY-MM-DD HH:MM:SS；留空表示不限制时间。
# 为避免引入额外依赖，这里使用 Android 端文件修改时间作为拍摄时间判断依据。
SYNC_AFTER_TIME="2026-05-01 00:00:00"

# 本地临时缓存目录、同步记录日志与运行输出日志
LOCAL_TEMP_DIR="/tmp/samsung_photos_sync/"
LOG_FILE="$HOME/Scripts/synced_photos.log"
SKIPPED_LOG_FILE="$HOME/Scripts/skipped_photos.log"
RUN_LOG_FILE="$HOME/Scripts/sync_photos_run.log"

# 初始化本地环境
mkdir -p "$LOCAL_TEMP_DIR" "${LOG_FILE:h}" "${SKIPPED_LOG_FILE:h}" "${RUN_LOG_FILE:h}"
touch "$LOG_FILE" "$SKIPPED_LOG_FILE" "$RUN_LOG_FILE"

# 将脚本运行中的 echo 输出与命令错误统一追加到指定运行日志文件中，并为每行加时间戳。
exec > >(while IFS= read -r line; do
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"
done >> "$RUN_LOG_FILE") 2>&1

SYNC_AFTER_EPOCH=0
if [[ -n "$SYNC_AFTER_TIME" ]]; then
    SYNC_AFTER_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$SYNC_AFTER_TIME" "+%s" 2>/dev/null)
    if [[ -z "$SYNC_AFTER_EPOCH" ]]; then
        echo "❌ SYNC_AFTER_TIME 格式错误，请使用 YYYY-MM-DD HH:MM:SS，例如 2026-05-01 00:00:00"
        exit 1
    fi
    echo "⏱️ 仅同步拍摄/生成时间晚于 $SYNC_AFTER_TIME 的照片。"
fi

echo "=== 开始执行 Android to iOS 照片无感同步流水线 ==="
echo "🔍 正在扫描当前局域网寻找开放了 $PHONE_PORT 端口的设备..."

ACTIVE_IP=""

# ==========================================
# --- 阶段一：动态端口嗅探与设备发现 ---
# ==========================================

# 1. 获取 Mac 当前连接网卡的广播地址 (以 en0 为例)
BROADCAST_IP=$(ifconfig en0 | grep broadcast | awk '{print $6}')

if [[ -n "$BROADCAST_IP" ]]; then
    # 2. 发送两组 Ping 广播包，强制局域网内设备暴露自己，刷新 Mac 的 ARP 缓存表
    ping -c 2 -t 1 "$BROADCAST_IP" >/dev/null 2>&1
fi

# 3. 从 ARP 表中提取出所有存活设备的 IP 地址 (去重)
ARP_IPS=$(arp -a | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort -u)

# 4. 并发/轮询探测这些 IP 的 5566 端口
while IFS= read -r ip; do
    if [[ -z "$ip" ]]; then continue; fi

    # 使用 macOS 自带的 netcat (nc) 探测端口
    if nc -z -G 1 "$ip" "$PHONE_PORT" 2>/dev/null; then
        echo "⚡️ 嗅探到目标: $ip 的 $PHONE_PORT 端口处于开放状态！"

        # 尝试通过 ADB 进行握手
        $ADB_PATH connect "$ip:$PHONE_PORT" >/dev/null 2>&1
        sleep 1

        # 验证是否真正握手成功
        DEVICES=$($ADB_PATH devices)
        if echo "$DEVICES" | grep -q "$ip:$PHONE_PORT" && ! echo "$DEVICES" | grep "$ip:$PHONE_PORT" | grep -q "offline"; then
            echo "✅ 成功接头！设备真实 IP 为: $ip"
            ACTIVE_IP=$ip
            break
        else
            # 握手失败，清理死连接
            $ADB_PATH disconnect "$ip:$PHONE_PORT" >/dev/null 2>&1
        fi
    fi
done <<< "$ARP_IPS"

if [[ -z "$ACTIVE_IP" ]]; then
    echo "❌ 扫描完毕，当前局域网内未发现开放 $PHONE_PORT 端口的 Android 设备。设备可能休眠或不在同一网络。"
    exit 0
fi

# ==========================================
# --- 阶段二：增量同步与相册导入 ---
# ==========================================

for REMOTE_DIR in "${REMOTE_DIRS[@]}"; do
    echo "\n📂 正在扫描目录: $REMOTE_DIR"
    
    # 获取远程文件列表 (排除文件夹，只留文件，并清除换行回车符)
    REMOTE_FILES=$($ADB_PATH shell ls -p "$REMOTE_DIR" | grep -v / | tr -d '\r')
    
    if [[ -z "$REMOTE_FILES" ]]; then
        echo "  -> 目录为空或未找到。"
        continue
    fi
    
    SYNC_COUNT=0
    
    # 逐行读取远程文件名并进行增量比对
    echo "$REMOTE_FILES" | while IFS= read -r FILENAME; do
        if [[ -z "$FILENAME" ]]; then continue; fi
        
        FULL_REMOTE_PATH="${REMOTE_DIR}${FILENAME}"
        
        # 如果日志里没有记录过这个文件的绝对路径，说明是新拍摄的照片
        if ! grep -Fxq "$FULL_REMOTE_PATH" "$LOG_FILE"; then
            if (( SYNC_AFTER_EPOCH > 0 )); then
                CACHED_SKIPPED_EPOCH=$(awk -F '\t' -v path="$FULL_REMOTE_PATH" '$1 == path { value = $2 } END { if (value != "") print value }' "$SKIPPED_LOG_FILE")
                if [[ -n "$CACHED_SKIPPED_EPOCH" && "$CACHED_SKIPPED_EPOCH" -le "$SYNC_AFTER_EPOCH" ]]; then
                    echo "     ⏭️ 跳过已缓存的早期照片: $FILENAME"
                    continue
                fi

                REMOTE_FILE_EPOCH=$($ADB_PATH shell stat -c %Y "$FULL_REMOTE_PATH" </dev/null 2>/dev/null | tr -d '\r')
                if [[ -z "$REMOTE_FILE_EPOCH" || "$REMOTE_FILE_EPOCH" -le "$SYNC_AFTER_EPOCH" ]]; then
                    if [[ -n "$REMOTE_FILE_EPOCH" ]] && ! awk -F '\t' -v path="$FULL_REMOTE_PATH" '$1 == path { found = 1; exit } END { exit !found }' "$SKIPPED_LOG_FILE"; then
                        printf '%s\t%s\n' "$FULL_REMOTE_PATH" "$REMOTE_FILE_EPOCH" >> "$SKIPPED_LOG_FILE"
                    fi
                    echo "     ⏭️ 跳过早于指定时间的照片: $FILENAME"
                    continue
                fi
            fi

            LOCAL_PATH="${LOCAL_TEMP_DIR}${FILENAME}"
            echo "     📥 拉取新照片: $FILENAME"
            
            # 从 Android 拉取到 Mac 临时目录
            $ADB_PATH pull "$FULL_REMOTE_PATH" "$LOCAL_PATH" >/dev/null 2>&1
            
            # 校验文件是否拉取成功，并调用 AppleScript 导入 Mac 照片 App
            if [[ -f "$LOCAL_PATH" ]]; then
                osascript -e "tell application \"Photos\" to import POSIX file \"$LOCAL_PATH\" skip check duplicates yes"
                
                # 导入成功后，记录日志并删除本地临时缓存，释放 Mac 硬盘空间
                echo "$FULL_REMOTE_PATH" >> "$LOG_FILE"
                rm "$LOCAL_PATH"
                ((SYNC_COUNT++))
            fi
        fi
    done
    
    if [[ $SYNC_COUNT -eq 0 ]]; then
        echo "  -> 没有新照片需要同步。"
    else
        echo "  -> 🎉 本目录成功同步了 $SYNC_COUNT 张新照片。"
    fi
done

# ==========================================
# --- 收尾清理 ---
# ==========================================
echo "\n✅ 当前环境所有照片同步流水线执行完毕！"
# 断开无线连接，保持后台纯净
$ADB_PATH disconnect "$ACTIVE_IP:$PHONE_PORT" >/dev/null 2>&1
