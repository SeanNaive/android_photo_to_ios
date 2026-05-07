import os
import subprocess
import time

# ==========================================
# --- 无线 ADB 配置区 ---
# ==========================================
# ip列表：把你所有可能出现的局域网 IP 都填进来
PHONE_IPS = [
    "192.168.31.5",
    "192.168.8.101",
    "192.168.10.169"
]

# 统一的固定端口号，每次重启后电脑有线连接Android手机后执行adb tcpip 5566
PHONE_PORT = "5566"

# ==========================================
# --- 同步目录配置区 ---
# ==========================================
REMOTE_DIRS = [
    "/sdcard/DCIM/Camera/",
    "/sdcard/DCIM/Screenshots/"
]

LOCAL_TEMP_DIR = "/tmp/samsung_photos_sync/"
LOG_FILE = os.path.expanduser("~/Scripts/synced_photos.log")

def run_cmd(cmd):
    """执行 Shell 命令并返回输出"""
    result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return result.stdout.strip()

def get_synced_files():
    """读取本地已同步的文件列表"""
    if not os.path.exists(LOG_FILE):
        return set()
    with open(LOG_FILE, "r") as f:
        return set(line.strip() for line in f)

def append_synced_file(filepath):
    """记录已同步的文件（写入完整路径）"""
    with open(LOG_FILE, "a") as f:
        f.write(filepath + "\n")

def import_to_mac_photos(local_file_path):
    """调用 AppleScript 将照片导入 Mac 照片 App"""
    applescript = f'''
    tell application "Photos"
        import POSIX file "{local_file_path}" skip check duplicates yes
    end tell
    '''
    subprocess.run(["osascript", "-e", applescript])

def main():
    print("=== 开始执行多环境探测同步流水线 ===")

    active_ip = None

    # 0. 轮询测试 IP 列表
    for ip in PHONE_IPS:
        print(f"\n[探针] 正在尝试无线连接到设备: {ip}:{PHONE_PORT} ...")

        # 防御性编程：在尝试连接前，先踢掉可能存在的 offline 残留
        run_cmd(f"adb disconnect {ip}:{PHONE_PORT}")

        # 发起连接
        connect_output = run_cmd(f"adb connect {ip}:{PHONE_PORT}")
        print(f"ADB 返回: {connect_output}")

        # 给底层 TCP 握手留 1 秒钟
        time.sleep(1)

        # 检查是否真的连上了（必须在 devices 列表里且状态不是 offline）
        devices_output = run_cmd("adb devices")
        if f"{ip}:{PHONE_PORT}" in devices_output and "offline" not in devices_output:
            print(f"✅ 成功接头！当前所处网络环境对应的设备 IP 为: {ip}")
            active_ip = ip
            break  # 只要命中一个，立刻跳出循环
        else:
            print(f"❌ 无法连通 {ip}，尝试下一个...")
            # 顺手清理失败的连接
            run_cmd(f"adb disconnect {ip}:{PHONE_PORT}")

    # 如果所有 IP 都试完了还是没连上
    if not active_ip:
        print("\n所有配置的 IP 均未连通，设备可能不在当前局域网内或休眠，退出任务。")
        return

    # ==========================================
    # --- 核心同步逻辑 (使用探测到的 active_ip) ---
    # ==========================================
    synced_files = get_synced_files()
    os.makedirs(LOCAL_TEMP_DIR, exist_ok=True)

    for remote_dir in REMOTE_DIRS:
        print(f"\n正在扫描目录: {remote_dir}")

        remote_files_raw = run_cmd(f"adb shell ls -p '{remote_dir}' | grep -v /")

        if not remote_files_raw:
            print("  -> 目录为空或未找到。")
            continue

        remote_files = remote_files_raw.split('\n')

        new_files = []
        for filename in remote_files:
            if not filename:
                continue
            full_remote_path = f"{remote_dir}{filename}"
            if full_remote_path not in synced_files:
                new_files.append((filename, full_remote_path))

        if not new_files:
            print("  -> 没有新文件需要同步。")
            continue

        print(f"  -> 发现 {len(new_files)} 个新文件，开始同步...")

        for filename, full_remote_path in new_files:
            local_path = os.path.join(LOCAL_TEMP_DIR, filename)

            print(f"     拉取: {filename}")
            run_cmd(f'adb pull "{full_remote_path}" "{local_path}"')

            if os.path.exists(local_path):
                import_to_mac_photos(local_path)
                append_synced_file(full_remote_path)
                os.remove(local_path)

    print("\n🎉 当前环境照片同步全部完成！")

    # 运行结束后断开本次命中的连接，保持 Mac 进程干净
    run_cmd(f"adb disconnect {active_ip}:{PHONE_PORT}")

if __name__ == "__main__":
    main()
