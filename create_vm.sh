#!/bin/bash
set -euo pipefail

# ==============================================
# 仅支持Proxmox VE 8.x，不兼容旧版本
# ==============================================
check_pve_version() {
    if ! command -v pveversion &>/dev/null; then
        error_exit "未检测到Proxmox环境，请在pve8上运行"
    fi
    # 提取主版本号（pve-manager/8.1.3/... → 8）
    local pve_major=$(pveversion | awk -F'[/.]' '{print $2}')
    if [[ "$pve_major" -ne 8 ]]; then
        error_exit "仅支持Proxmox VE 8.x，当前版本：$(pveversion | cut -d'/' -f2)"
    fi
    log "Proxmox VE 8.x 版本验证通过"
}

# ==============================================
# 配置参数（pve8优化版）
# ==============================================
TEMPLATE_ID=9001
VM_ID=101
VM_NAME="ubuntu-101"
USERNAME="ubuntu"
PASSWORD="securepassword"
# pve8推荐使用较新的Ubuntu镜像（Jammy或Noble）
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_NAME="noble-server-cloudimg-amd64.img"
STORAGE="local"  # pve8默认本地存储名称
BRIDGE="vmbr0"   # pve8默认桥接名称
MEMORY=8196      # 内存(MB)，pve8支持更大内存配置
CORES=8          # CPU核心数，pve8对多核支持更优
RETRY_DOWNLOAD=3
WAIT_TIMEOUT=300
WAIT_INTERVAL=2

# ==============================================
# 工具函数（pve8适配）
# ==============================================
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
    log "ERROR: $*"
    exit 1
}

check_cmd() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        error_exit "缺少必要工具：$cmd（pve8需手动安装时可使用apt install $cmd）"
    fi
}

wait_for() {
    local condition=$1
    local timeout=$2
    local interval=$3
    local message=$4

    local start_time=$(date +%s)
    log "等待：$message（超时：${timeout}s）"
    
    while ! eval "$condition"; do
        local current_time=$(date +%s)
        if (( current_time - start_time >= timeout )); then
            error_exit "等待超时：$message"
        fi
        sleep "$interval"
    done
    log "等待完成：$message"
}

# ==============================================
# 存储检查（pve8存储配置优化）
# ==============================================
check_storage() {
    local storage=$1

    # pve8中存储状态查询优化
    if ! pvesm status --output-format=json | jq -e ".[] | select(.storage == \"$storage\")" &>/dev/null; then
        log "可用存储列表（pve8）："
        pvesm status | awk '{print "  " $1 " (" $2 ")"}'
        error_exit "存储 '$storage' 不存在，请从上方列表选择正确名称（pve8默认存储为'local'）"
    fi

    # 获取存储类型（pve8使用json解析更可靠）
    local storage_type=$(pvesm status --output-format=json | jq -r ".[] | select(.storage == \"$storage\") | .type")
    log "检测到存储 '$storage'，类型：$storage_type（pve8兼容类型）"

    # pve8对目录存储（dir）的路径处理优化
    if [[ "$storage_type" == "dir" ]]; then
        # pve8中pvesm path命令行为稳定，优先使用
        local storage_path=$(pvesm path "$storage:")
        if [[ -z "$storage_path" || ! -d "$storage_path" ]]; then
            error_exit "目录存储 '$storage' 路径无效：$storage_path（pve8需确保路径存在且权限正确）"
        fi
        log "pve8目录存储路径验证通过：$storage_path"
    fi

    # 检查cloudinit支持（pve8要求显式启用）
    local content=$(pvesm config "$storage" | grep -oP 'content\s+\K.+' || true)
    if ! echo "$content" | grep -q "cloudinit"; then
        error_exit "存储 '$storage' 未启用cloudinit支持！请在pve8 Web界面执行：
数据中心 → 存储 → $storage → 编辑 → 内容 → 勾选'cloudinit' → 确定"
    fi
}

# ==============================================
# 镜像处理（pve8支持的镜像格式优化）
# ==============================================
check_image() {
    if [[ -f "$IMAGE_NAME" ]]; then
        log "本地镜像已存在：$IMAGE_NAME"
        
        # pve8推荐使用curl的--head替代-I，避免协议问题
        REMOTE_SIZE=$(curl -sSL --head "$IMAGE_URL" | grep -i '^content-length' | tail -n1 | awk '{print $2}' | tr -d '\r')
        LOCAL_SIZE=$(stat -c%s "$IMAGE_NAME")
        
        if [[ -n "$REMOTE_SIZE" && "$LOCAL_SIZE" -eq "$REMOTE_SIZE" ]]; then
            log "镜像大小一致（$LOCAL_SIZE 字节），使用现有镜像"
            return 0
        else
            log "镜像大小不一致（本地：$LOCAL_SIZE，远程：$REMOTE_SIZE）"
            read -p "是否重新下载？(y/n，默认n): " REDOWNLOAD
            if [[ "$REDOWNLOAD" == "y" || "$REDOWNLOAD" == "Y" ]]; then
                log "删除旧镜像，准备重新下载"
                rm -f "$IMAGE_NAME"
                return 1
            else
                log "继续使用现有镜像"
                return 0
            fi
        fi
    else
        log "本地镜像不存在，需要下载"
        return 1
    fi
}

download_image() {
    log "开始下载镜像：$IMAGE_URL（最多重试$RETRY_DOWNLOAD次，pve8推荐使用https）"
    local retry=0
    while (( retry < RETRY_DOWNLOAD )); do
        # pve8中wget默认支持TLS1.3，兼容性更好
        if wget -c --no-check-certificate "$IMAGE_URL" -O "$IMAGE_NAME"; then
            log "镜像下载完成"
            return 0
        fi
        (( retry++ ))
        log "下载失败，重试（$retry/$RETRY_DOWNLOAD）"
        sleep 3
    done
    error_exit "镜像下载失败，已达最大重试次数"
}

# ==============================================
# 模板处理（pve8模板创建优化）
# ==============================================
check_template_existence() {
    # pve8中qm list输出格式不变，但过滤逻辑更严格
    if qm list | awk '{print $1}' | grep -q "^$TEMPLATE_ID$"; then
        log "模板ID $TEMPLATE_ID 已存在"
        read -p "是否更新模板？(y/n，默认n): " UPDATE_TEMPLATE
        if [[ "$UPDATE_TEMPLATE" == "y" || "$UPDATE_TEMPLATE" == "Y" ]]; then
            log "停止并删除旧模板（pve8支持强制删除）"
            qm stop "$TEMPLATE_ID" &>/dev/null || true
            wait_for "! qm status $TEMPLATE_ID &>/dev/null" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "模板停止"
            qm destroy "$TEMPLATE_ID" --purge &>/dev/null || true  # pve8新增--purge参数清理残留
            return 0
        else
            log "保留现有模板"
            return 1
        fi
    fi
    return 0
}

create_template() {
    log "创建模板虚拟机（ID：$TEMPLATE_ID，pve8优化配置）"
    # pve8中默认使用qemu 8.0+，推荐virtio-scsi-single控制器
    qm create "$TEMPLATE_ID" \
        --name "ubuntu-template" \
        --memory "$MEMORY" \
        --cores "$CORES" \
        --cpu host \  # pve8推荐使用host cpu模式获取最佳性能
        --net0 "virtio,bridge=$BRIDGE,firewall=1" \  # pve8默认启用防火墙
        --ostype l26 \
        --agent 1  # pve8推荐启用qemu-guest-agent

    log "导入镜像到存储$STORAGE（pve8支持快速导入）"
    qm importdisk "$TEMPLATE_ID" "$IMAGE_NAME" "$STORAGE" --format raw  # pve8推荐显式指定raw格式

    wait_for "qm config $TEMPLATE_ID | grep -q 'scsi0: $STORAGE:$TEMPLATE_ID/'" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "磁盘导入"

    log "配置模板磁盘（pve8存储控制器优化）"
    qm set "$TEMPLATE_ID" --scsihw virtio-scsi-single --scsi0 "$STORAGE:$TEMPLATE_ID/vm-$TEMPLATE_ID-disk-0.raw"
    qm set "$TEMPLATE_ID" --disk size=30G  # pve8支持动态调整磁盘大小

    log "配置Cloud-Init（pve8集成优化）"
    qm set "$TEMPLATE_ID" --ide2 "$STORAGE:cloudinit"
    qm set "$TEMPLATE_ID" --boot order=scsi0  # pve8调整启动顺序参数
    qm set "$TEMPLATE_ID" --serial0 socket --vga serial0  # 兼容pve8的控制台输出
    qm set "$TEMPLATE_ID" --ciuser "$USERNAME" --cipassword "$PASSWORD"
    qm set "$TEMPLATE_ID" --ipconfig0 "ip=dhcp"
    qm set "$TEMPLATE_ID" --onboot 0  # 模板默认不随主机启动（pve8建议）

    if ! qm config "$TEMPLATE_ID" | grep -q "template: 1"; then
        log "转换为模板（pve8模板标记）"
        qm template "$TEMPLATE_ID"
    fi
}

# ==============================================
# 虚拟机处理（pve8克隆优化）
# ==============================================
check_vm_existence() {
    if qm list | awk '{print $1}' | grep -q "^$VM_ID$"; then
        log "虚拟机ID $VM_ID 已存在"
        read -p "是否更新虚拟机？(y/n，默认n): " UPDATE_VM
        if [[ "$UPDATE_VM" == "y" || "$UPDATE_VM" == "Y" ]]; then
            log "停止并删除旧虚拟机（pve8强制清理）"
            qm stop "$VM_ID" &>/dev/null || true
            wait_for "! qm status $VM_ID &>/dev/null" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "虚拟机停止"
            qm destroy "$VM_ID" --purge &>/dev/null || true
            return 0
        else
            log "保留现有虚拟机"
            return 1
        fi
    fi
    return 0
}

create_vm() {
    log "从模板克隆虚拟机（ID：$VM_ID，名称：$VM_NAME，pve8全量克隆）"
    # pve8中克隆命令支持--full快速全量克隆
    qm clone "$TEMPLATE_ID" "$VM_ID" --name "$VM_NAME" --full --storage "$STORAGE"

    wait_for "qm status $VM_ID &>/dev/null" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "虚拟机克隆"

    log "启动虚拟机（pve8启动优化）"
    qm start "$VM_ID" --debug  # pve8支持--debug查看启动日志（可选）
    
    wait_for "qm status $VM_ID | grep -q 'running'" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "虚拟机启动"
}

# ==============================================
# 主流程（pve8优先）
# ==============================================
log "===== 开始执行pve8专用虚拟机部署流程 ====="

# 优先检查pve版本
check_pve_version

# 初始化检查（pve8依赖）
if [[ $(id -u) -ne 0 ]]; then
    error_exit "请以root权限运行（pve8需root执行qm命令）"
fi

# pve8默认已安装大部分工具，仅检查核心依赖
check_cmd qm
check_cmd curl
check_cmd wget
check_cmd jq  # pve8中使用jq解析json（需提前安装：apt install jq）
check_cmd stat
check_cmd pvesm

# 解析命令行参数（兼容原有参数）
for arg in "$@"; do
    case "$arg" in
        --template-id=*) TEMPLATE_ID="${arg#*=}" ;;
        --vm-id=*) VM_ID="${arg#*=}" ;;
        --vm-name=*) VM_NAME="${arg#*=}" ;;
        --username=*) USERNAME="${arg#*=}" ;;
        --password=*) PASSWORD="${arg#*=}" ;;
        --image-url=*) IMAGE_URL="${arg#*=}" ;;
        --image-name=*) IMAGE_NAME="${arg#*=}" ;;
        --storage=*) STORAGE="${arg#*=}" ;;
        --bridge=*) BRIDGE="${arg#*=}" ;;
        --memory=*) MEMORY="${arg#*=}" ;;
        --cores=*) CORES="${arg#*=}" ;;
        --help)
            echo "使用方法：$0 [--key=value...]"
            echo "pve8专用参数（默认值）："
            echo "  --template-id=ID      模板ID（$TEMPLATE_ID）"
            echo "  --vm-id=ID            虚拟机ID（$VM_ID）"
            echo "  --image-url=URL       Ubuntu镜像（$IMAGE_URL）"
            exit 0
            ;;
        *) error_exit "未知参数：$arg，使用--help查看帮助" ;;
    esac
done

# 执行存储检查（pve8专用逻辑）
check_storage "$STORAGE"

# 镜像处理
if ! check_image; then
    download_image
fi

# 模板处理（pve8优化）
if check_template_existence; then
    create_template
fi

# 虚拟机处理（pve8优化）
if check_vm_existence; then
    create_vm
fi

log "===== pve8虚拟机部署完成 ====="
log "当前模板状态："
qm list | awk -v id="$TEMPLATE_ID" '$1 == id' || log "模板$TEMPLATE_ID不存在"
log "当前虚拟机状态："
qm list | awk -v id="$VM_ID" '$1 == id' || log "虚拟机$VM_ID不存在"
log "pve8提示：查看IP可执行 'qm guest cmd $VM_ID network-get-interfaces'（需安装qemu-guest-agent）"
