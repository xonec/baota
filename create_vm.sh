#!/bin/bash

# 参数配置
TEMPLATE_ID=9001
VM_ID=101
VM_NAME="ubuntu-101"
USERNAME="ubuntu"
PASSWORD="securepassword"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_NAME="jammy-server-cloudimg-amd64.img"
STORAGE="local"
BRIDGE="vmbr0"

# 函数：检查镜像是否存在
check_image() {
    if [[ -f $IMAGE_NAME ]]; then
        echo "本地镜像已存在..."
        # 获取远程文件大小（以字节为单位）
        REMOTE_SIZE=$(curl -sI $IMAGE_URL | grep -i content-length | awk '{print $2}' | tr -d '\r')
        # 获取本地文件大小（以字节为单位）
        LOCAL_SIZE=$(stat -c%s "$IMAGE_NAME")
        
        if [[ -n "$REMOTE_SIZE" && "$LOCAL_SIZE" == "$REMOTE_SIZE" ]]; then
            echo "镜像大小一致（$LOCAL_SIZE 字节），使用现有镜像。"
            return 0
        else
            echo "镜像大小不一致或无法获取远程大小"
            echo "本地大小: $LOCAL_SIZE"
            echo "远程大小: $REMOTE_SIZE"
            read -p "是否重新下载镜像？(y/n): " REDOWNLOAD
            if [[ $REDOWNLOAD == "y" ]]; then
                echo "重新下载镜像..."
                rm -f $IMAGE_NAME
                return 1
            else
                echo "使用现有镜像继续..."
                return 0
            fi
        fi
    else
        echo "本地镜像不存在，开始下载..."
        return 1
    fi
}

# 函数：检查模板是否存在并处理
check_template_existence() {
    if qm list | grep -q "$TEMPLATE_ID"; then
        echo "模板 ID $TEMPLATE_ID 已存在。"
        read -p "是否更新模板？(y/n): " UPDATE_TEMPLATE
        if [[ $UPDATE_TEMPLATE == "y" ]]; then
            echo "停止现有模板..."
            qm stop $TEMPLATE_ID &>/dev/null
            sleep 2
            echo "删除旧模板..."
            qm destroy $TEMPLATE_ID
            return 0
        else
            echo "保留现有模板。"
            return 1
        fi
    fi
    return 0
}

# 函数：检查虚拟机是否存在并处理
check_vm_existence() {
    if qm list | grep -q "$VM_ID"; then
        echo "虚拟机 ID $VM_ID 已存在。"
        read -p "是否更新该虚拟机？(y/n): " UPDATE_VM
        if [[ $UPDATE_VM == "y" ]]; then
            echo "停止现有虚拟机..."
            qm stop $VM_ID &>/dev/null
            sleep 5
            echo "删除现有虚拟机..."
            qm destroy $VM_ID
            return 0
        else
            echo "保留现有虚拟机。"
            return 1
        fi
    fi
    return 0
}

# 函数：创建模板
create_template() {
    echo "创建虚拟机模板..."
    qm create $TEMPLATE_ID --name "ubuntu-template" --memory 2048 --cores 2 --net0 virtio,bridge=$BRIDGE

    echo "导入镜像..."
    qm importdisk $TEMPLATE_ID $IMAGE_NAME $STORAGE

    echo "等待磁盘导入完成..."
    sleep 5

    # 获取最新导入的磁盘文件
    DISK_NAME=$(ls -t /var/lib/vz/images/$TEMPLATE_ID/vm-$TEMPLATE_ID-disk-*.raw | head -n1)
    if [[ -z "$DISK_NAME" ]]; then
        echo "错误：找不到导入的磁盘文件"
        exit 1
    fi

    DISK_BASE=$(basename "$DISK_NAME")
    echo "使用磁盘: $DISK_BASE"

    echo "配置磁盘..."
    qm set $TEMPLATE_ID --scsihw virtio-scsi-pci --scsi0 "$STORAGE:$TEMPLATE_ID/$DISK_BASE"

    echo "配置 Cloud-Init..."
    qm set $TEMPLATE_ID --ide2 $STORAGE:cloudinit
    qm set $TEMPLATE_ID --boot c --bootdisk scsi0
    qm set $TEMPLATE_ID --serial0 socket --vga serial0
    qm set $TEMPLATE_ID --ciuser $USERNAME --cipassword $PASSWORD

    echo "配置网络..."
    qm set $TEMPLATE_ID --ipconfig0 ip=dhcp

    # 检查是否已经是模板
    if ! qm config $TEMPLATE_ID | grep -q "template: 1"; then
        echo "转换为模板..."
        qm template $TEMPLATE_ID
    fi
}

# 函数：克隆和启动虚拟机
create_vm() {
    echo "克隆模板创建新虚拟机..."
    qm clone $TEMPLATE_ID $VM_ID --name $VM_NAME --full

    echo "等待克隆完成..."
    sleep 5

    if qm status $VM_ID &>/dev/null; then
        echo "启动虚拟机..."
        qm start $VM_ID
    else
        echo "错误：虚拟机创建失败"
        exit 1
    fi
}

# 主程序开始
echo "开始执行虚拟机创建流程..."

# 下载镜像（如果需要）
if ! check_image; then
    echo "下载 Ubuntu Cloud 镜像..."
    wget $IMAGE_URL -O $IMAGE_NAME || {
        echo "错误：下载镜像失败"
        exit 1
    }
fi

# 检查并创建/更新模板
if check_template_existence; then
    create_template
fi

# 检查并创建/更新虚拟机
if check_vm_existence; then
    create_vm
fi

# 显示最终状态
echo "操作完成！当前状态："
qm list | grep -E "$TEMPLATE_ID|$VM_ID"
