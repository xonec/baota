#!/bin/bash
set -euo pipefail

# ==============================================
# 配置参数（可通过命令行参数覆盖）
# ==============================================
TEMPLATE_ID=9001
VM_ID=101
VM_NAME="ubuntu-101"
USERNAME="ubuntu"
PASSWORD="securepassword"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_NAME="jammy-server-cloudimg-amd64.img"
STORAGE="local"
BRIDGE="vmbr0"
MEMORY=9182  # MB
CORES=4
RETRY_DOWNLOAD=3
WAIT_TIMEOUT=300
WAIT_INTERVAL=2

# ==============================================
# 工具函数
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
        error_exit "缺少必要工具：$cmd，请先安装"
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
# 存储检查增强版（核心优化）
# ==============================================
check_storage() {
    local storage=$1

    # 检查存储是否存在
    if ! pvesm status | grep -q "^$storage"; then
        log "可用存储列表："
        pvesm status | awk '{print "  " $1 " (" $2 ")"}'  # 显示存储名称和类型
        error_exit "存储 '$storage' 不存在，请从上方列表选择正确的存储名称"
    fi

    # 获取存储类型（dir/lvm/zfs等）
    local storage_type=$(pvesm status | grep "^$storage" | awk '{print $2}')
    log "检测到存储 '$storage'，类型：$storage_type"

    # 仅对目录存储（dir）检查路径，块存储（lvm等）无需路径
    if [[ "$storage_type" == "dir" ]]; then
        local storage_path=$(pvesm path "$storage:" 2>/dev/null || true)
        if [[ -z "$storage_path" || ! -d "$storage_path" ]]; then
            error_exit "目录存储 '$storage' 路径无效（$storage_path），请检查Proxmox存储配置"
        fi
        log "目录存储路径：$storage_path"
    else
        log "块存储（$storage_type）无需路径检查，直接使用存储名称"
    fi

    # 检查存储是否支持cloudinit（所有类型存储都可支持，只需配置正确）
    if ! pvesm config "$storage" | grep -q "content.*cloudinit"; then
        error_exit "存储 '$storage' 未启用cloudinit支持！请执行以下步骤修复：
1. 登录Proxmox Web界面
2. 进入『数据中心 → 存储 → $storage → 编辑』
3. 在『内容』中勾选『cloudinit』
4. 保存后重新运行脚本"
    fi
}

# ==============================================
# 初始化检查
# ==============================================
if [[ $(id -u) -ne 0 ]]; then
    error_exit "请以root权限运行（sudo）"
fi

check_cmd qm
check_cmd curl
check_cmd wget
check_cmd stat
check_cmd pvesm

# 解析命令行参数
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
            echo "可选参数："
            echo "  --template-id=ID      模板ID（默认：$TEMPLATE_ID）"
            echo "  --vm-id=ID            虚拟机ID（默认：$VM_ID）"
            echo "  --vm-name=NAME        虚拟机名称（默认：$VM_NAME）"
            echo "  --username=USER       初始用户名（默认：$USERNAME）"
            echo "  --password=PWD        初始密码（默认：$PASSWORD）"
            echo "  --image-url=URL       镜像下载地址（默认：$IMAGE_URL）"
            echo "  --image-name=NAME     本地镜像文件名（默认：$IMAGE_NAME）"
            echo "  --storage=NAME        Proxmox存储名称（默认：$STORAGE）"
            echo "  --bridge=NAME         网络桥接名称（默认：$BRIDGE）"
            echo "  --memory=MB           内存大小（MB，默认：$MEMORY）"
            echo "  --cores=NUM           CPU核心数（默认：$CORES）"
            exit 0
            ;;
        *) error_exit "未知参数：$arg，使用--help查看帮助" ;;
    esac
done

# 执行增强版存储检查（核心优化点）
check_storage "$STORAGE"

# ==============================================
# 镜像处理（保持不变）
# ==============================================
check_image() {
    if [[ -f "$IMAGE_NAME" ]]; then
        log "本地镜像已存在：$IMAGE_NAME"
        
        REMOTE_SIZE=$(curl -sIL "$IMAGE_URL" | grep -i '^content-length' | tail -n1 | awk '{print $2}' | tr -d '\r')
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
    log "开始下载镜像：$IMAGE_URL（最多重试$RETRY_DOWNLOAD次）"
    local retry=0
    while (( retry < RETRY_DOWNLOAD )); do
        if wget -c "$IMAGE_URL" -O "$IMAGE_NAME"; then
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
# 模板处理（优化存储路径依赖）
# ==============================================
check_template_existence() {
    if qm list | awk '{print $1}' | grep -q "^$TEMPLATE_ID$"; then
        log "模板ID $TEMPLATE_ID 已存在"
        read -p "是否更新模板？(y/n，默认n): " UPDATE_TEMPLATE
        if [[ "$UPDATE_TEMPLATE" == "y" || "$UPDATE_TEMPLATE" == "Y" ]]; then
            log "停止并删除旧模板"
            qm stop "$TEMPLATE_ID" &>/dev/null || true
            wait_for "! qm status $TEMPLATE_ID &>/dev/null" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "模板停止"
            qm destroy "$TEMPLATE_ID" &>/dev/null || true
            return 0
        else
            log "保留现有模板"
            return 1
        fi
    fi
    return 0
}

create_template() {
    log "创建模板虚拟机（ID：$TEMPLATE_ID）"
    qm create "$TEMPLATE_ID" \
        --name "ubuntu-template" \
        --memory "$MEMORY" \
        --cores "$CORES" \
        --net0 "virtio,bridge=$BRIDGE" \
        --ostype l26

    log "导入镜像到存储$STORAGE"
    qm importdisk "$TEMPLATE_ID" "$IMAGE_NAME" "$STORAGE"
    
    # 等待磁盘导入完成（不依赖路径，直接检查配置）
    wait_for "qm config $TEMPLATE_ID | grep -q 'scsi0: $STORAGE:$TEMPLATE_ID/'" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "磁盘导入"

    log "配置模板磁盘"
    qm set "$TEMPLATE_ID" --scsihw virtio-scsi-pci --scsi0 "$STORAGE:$TEMPLATE_ID/vm-$TEMPLATE_ID-disk-0.raw"

    log "配置Cloud-Init"
    qm set "$TEMPLATE_ID" --ide2 "$STORAGE:cloudinit"
    qm set "$TEMPLATE_ID" --boot c --bootdisk scsi0
    qm set "$TEMPLATE_ID" --serial0 socket --vga serial0
    qm set "$TEMPLATE_ID" --ciuser "$USERNAME" --cipassword "$PASSWORD"
    qm set "$TEMPLATE_ID" --ipconfig0 "ip=dhcp"

    if ! qm config "$TEMPLATE_ID" | grep -q "template: 1"; then
        log "转换为模板"
        qm template "$TEMPLATE_ID"
    fi
}

# ==============================================
# 虚拟机处理（保持不变）
# ==============================================
check_vm_existence() {
    if qm list | awk '{print $1}' | grep -q "^$VM_ID$"; then
        log "虚拟机ID $VM_ID 已存在"
        read -p "是否更新虚拟机？(y/n，默认n): " UPDATE_VM
        if [[ "$UPDATE_VM" == "y" || "$UPDATE_VM" == "Y" ]]; then
            log "停止并删除旧虚拟机"
            qm stop "$VM_ID" &>/dev/null || true
            wait_for "! qm status $VM_ID &>/dev/null" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "虚拟机停止"
            qm destroy "$VM_ID" &>/dev/null || true
            return 0
        else
            log "保留现有虚拟机"
            return 1
        fi
    fi
    return 0
}

create_vm() {
    log "从模板克隆虚拟机（ID：$VM_ID，名称：$VM_NAME）"
    qm clone "$TEMPLATE_ID" "$VM_ID" --name "$VM_NAME" --full

    wait_for "qm status $VM_ID &>/dev/null" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "虚拟机克隆"

    log "启动虚拟机"
    qm start "$VM_ID"
    
    wait_for "qm status $VM_ID | grep -q 'running'" "$WAIT_TIMEOUT" "$WAIT_INTERVAL" "虚拟机启动"
}

# ==============================================
# 主流程
# ==============================================
log "===== 开始执行虚拟机部署流程 ====="

if ! check_image; then
    download_image
fi

if check_template_existence; then
    create_template
fi

if check_vm_existence; then
    create_vm
fi

log "===== 操作完成 ====="
log "当前模板状态："
qm list | awk -v id="$TEMPLATE_ID" '$1 == id' || log "模板$TEMPLATE_ID不存在"
log "当前虚拟机状态："
qm list | awk -v id="$VM_ID" '$1 == id' || log "虚拟机$VM_ID不存在"
log "提示：若需查看虚拟机IP，可在启动后执行 'qm guest cmd $VM_ID network-get-interfaces'（需安装qemu-guest-agent）"
