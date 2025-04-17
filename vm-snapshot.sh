#!/bin/bash
#############################################################################
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: Rocky Linux 9
# Updated By: Grok 3 (xAI)
# Update Date: 2025-04-17
# Version: 1.0.6
#############################################################################

# 脚本名称和版本
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

SCRIPT_NAME="${SH_NAME}"
VERSION="1.0.6"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 日志文件
LOG_FILE="/var/log/vm-snapshot.log"

# 临时文件列表
TEMP_FILES=()

# 引入环境变量
if [ -f "${SH_PATH}/env.sh" ]; then
    source "${SH_PATH}/env.sh"
fi

# 日志函数
LOG() {
    if [ "$QUIET" != "yes" ]; then
        echo -e "${GREEN}[$(date "+%H:%M:%S")] ${SH_NAME}: $*${NC}"
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*" >> "$LOG_FILE"
    fi
}

ERROR() {
    echo -e "${RED}[$(date "+%H:%M:%S")] ${SH_NAME}: $*${NC}" >&2
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: ERROR: $*" >> "$LOG_FILE"
    exit 1
}

WARN() {
    if [ "$QUIET" != "yes" ]; then
        echo -e "${YELLOW}[$(date "+%H:%M:%S")] ${SH_NAME}: $*${NC}"
        echo "[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: WARN: $*" >> "$LOG_FILE"
    fi
}

# 清理临时文件
F_CLEANUP() {
    for file in "${TEMP_FILES[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file" && LOG "已清理临时文件: $file"
        fi
    done
}

trap F_CLEANUP EXIT INT TERM

# 检查 root 权限
F_CHECK_ROOT() {
    if [ "$(id -u)" != "0" ]; then
        ERROR "此脚本需要 root 权限运行！请使用 sudo 或以 root 用户执行。"
    fi
}

# 检查依赖工具
F_CHECK_DEPS() {
    local deps=("qemu-img" "virsh")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            ERROR "缺少依赖工具：${dep}。请安装后再运行。"
        fi
    done
}

# 显示帮助信息
F_HELP() {
    echo -e "
${GREEN}用途：${NC}管理KVM虚拟机的磁盘快照（创建、回滚、删除、列出）
${GREEN}支持存储类型：${NC}
    * 本地文件（qcow2）
${RED}不支持的类型：${NC}
    * raw 格式磁盘
    * RBD/CEPH存储
    * iSCSI存储
    * 其他网络存储
${GREEN}依赖：${NC}
    * qemu-img
    * virsh
${GREEN}注意：${NC}
    * 必须在虚拟机关机状态下操作
    * 重要数据请提前备份，脚本会提示备份
    * 需要root权限执行
${GREEN}参数语法规范：${NC}
    无包围符号  ：-a               : 必选【选项】
                  ：val              : 必选【参数值】
                  ：val1 val2 -a -b  : 必选【选项或参数值】，且不分先后顺序
    []            ：[-a]             : 可选【选项】
                  ：[val]            : 可选【参数值】
    <>            ：<val>            : 需替换的具体值（用户必须提供）
    %%            ：%val%            : 通配符（包含匹配，如%error%匹配error_code）
    |             ：val1|val2|<valn> : 多选一
    {}            ：{-a <val>}       : 必须成组出现【选项+参数值】
                  ：{val1 val2}      : 必须成组的【参数值组合】，且必须按顺序提供
${GREEN}用法：${NC}
    $0 -h|--help                                        #-- 显示帮助
    $0 -v|--version                                     #-- 显示版本
    $0 -l|--list {-n|--name <虚拟机名称>}               #-- 列出快照
    $0 {-c|--create <快照名称>} {-n|--name <虚拟机名称>}    #-- 创建快照
    $0 {-r|--revert <快照名称>} {-n|--name <虚拟机名称>}    #-- 回滚快照
    $0 {-d|--delete <快照名称>} {-n|--name <虚拟机名称>}    #-- 删除快照
${GREEN}参数说明：${NC}
    -h|--help           显示此帮助信息
    -v|--version        显示脚本版本
    -n|--name           指定虚拟机名称（必须与 -c|-r|-d|-l 成组使用）
    -c|--create         创建快照（需提供快照名称）
    -r|--revert         回滚到指定快照（需提供快照名称）
    -d|--delete         删除指定快照（需提供快照名称）
    -l|--list           列出虚拟机磁盘的所有快照
    <虚拟机名称>        KVM虚拟机名称
    <快照名称>          快照的名称（如 before_extend_20250416）
${GREEN}使用示例：${NC}
    $0 -h                                # 显示帮助信息
    $0 -v                                # 显示版本信息
    $0 -c -n vm1 snap1                   # 为【vm1】创建快照【snap1】
    $0 -r -n vm1 snap1                   # 将【vm1】回滚到快照【snap1】
    $0 -d -n vm1 snap1                   # 删除【vm1】的快照【snap1】
    $0 -l -n vm1                         # 列出【vm1】的所有快照
"
}

# 显示版本信息
F_VERSION() {
    echo -e "${GREEN}${SCRIPT_NAME} ${VERSION}${NC}"
}

# 提示用户确认
F_PROMPT() {
    local prompt="$1"
    local response
    echo -e "${YELLOW}${prompt}${NC}"
    echo -n "是否确认？(y/N): "
    read -r response
    if [[ ! "$response" =~ ^[yY]$ ]]; then
        ERROR "用户取消操作！"
    fi
}

# 检查虚拟机和磁盘
F_CHECK() {
    # 检查虚拟机存在
    if ! virsh list --all --name | grep -q "^${VM_NAME}$"; then
        ERROR "虚拟机 '${VM_NAME}' 不存在！"
    fi

    # 检查虚拟机状态
    local vm_state
    vm_state=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "未定义")
    if [[ "$vm_state" != "shut off" ]]; then
        ERROR "虚拟机 '${VM_NAME}' 必须处于关机状态！当前状态：${vm_state}，请先运行 'virsh shutdown ${VM_NAME}'"
    fi

    # 检查磁盘文件
    DISK_PATH="/mnt/disk_1t_ssd/kvm-images/${VM_NAME}.img"
    if [[ ! -f "$DISK_PATH" ]]; then
        ERROR "磁盘文件不存在：${DISK_PATH}"
    fi

    # 检查磁盘格式
    local disk_info
    disk_info=$(qemu-img info "$DISK_PATH" 2>/dev/null)
    if [[ -z "$disk_info" ]]; then
        ERROR "无法读取磁盘信息：${DISK_PATH}，可能文件损坏或被占用"
    fi
    if ! echo "$disk_info" | grep -q "file format: qcow2"; then
        ERROR "磁盘格式不是 qcow2：${DISK_PATH}"
    fi
}

# 创建快照
F_CREATE_SNAPSHOT() {
    echo -e "
${GREEN}快照操作摘要：${NC}
  虚拟机：${VM_NAME}
  磁盘文件：${DISK_PATH}
  操作：创建快照
  快照名称：${SNAP_NAME}
======================================"
    LOG "快照操作摘要："
    LOG "虚拟机：${VM_NAME}"
    LOG "磁盘文件：${DISK_PATH}"
    LOG "操作：创建快照"
    LOG "快照名称：${SNAP_NAME}"
    F_PROMPT "请确认以上信息是否正确？"

    LOG "正在创建快照 '${SNAP_NAME}' 于 ${DISK_PATH}..."
    if ! qemu-img snapshot -c "$SNAP_NAME" "$DISK_PATH"; then
        ERROR "创建快照 '${SNAP_NAME}' 失败！"
    fi
    LOG "快照 '${SNAP_NAME}' 创建成功"
    echo -e "${GREEN}快照 '${SNAP_NAME}' 创建成功${NC}"
}

# 回滚快照
F_REVERT_SNAPSHOT() {
    echo -e "
${GREEN}快照操作摘要：${NC}
  虚拟机：${VM_NAME}
  磁盘文件：${DISK_PATH}
  操作：回滚快照
  快照名称：${SNAP_NAME}
======================================"
    LOG "快照操作摘要："
    LOG "虚拟机：${VM_NAME}"
    LOG "磁盘文件：${DISK_PATH}"
    LOG "操作：回滚快照"
    LOG "快照名称：${SNAP_NAME}"
    F_PROMPT "请确认以上信息是否正确？"

    LOG "正在回滚到快照 '${SNAP_NAME}' 于 ${DISK_PATH}..."
    if ! qemu-img snapshot -a "$SNAP_NAME" "$DISK_PATH"; then
        ERROR "回滚快照 '${SNAP_NAME}' 失败！"
    fi
    LOG "快照 '${SNAP_NAME}' 回滚成功"
    echo -e "${GREEN}快照 '${SNAP_NAME}' 回滚成功${NC}"
}

# 删除快照
F_DELETE_SNAPSHOT() {
    echo -e "
${GREEN}快照操作摘要：${NC}
  虚拟机：${VM_NAME}
  磁盘文件：${DISK_PATH}
  操作：删除快照
  快照名称：${SNAP_NAME}
======================================"
    LOG "快照操作摘要："
    LOG "虚拟机：${VM_NAME}"
    LOG "磁盘文件：${DISK_PATH}"
    LOG "操作：删除快照"
    LOG "快照名称：${SNAP_NAME}"
    F_PROMPT "请确认以上信息是否正确？"

    LOG "正在删除快照 '${SNAP_NAME}' 从 ${DISK_PATH}..."
    if ! qemu-img snapshot -d "$SNAP_NAME" "$DISK_PATH"; then
        ERROR "删除快照 '${SNAP_NAME}' 失败！"
    fi
    LOG "快照 '${SNAP_NAME}' 删除成功"
    echo -e "${GREEN}快照 '${SNAP_NAME}' 删除成功${NC}"
}

# 列出快照
F_LIST_SNAPSHOTS() {
    LOG "正在列出 ${DISK_PATH} 的快照..."
    local snapshots
    snapshots=$(qemu-img snapshot -l "$DISK_PATH" 2>/dev/null) || ERROR "列出快照失败！"
    if [[ -z "$snapshots" ]]; then
        LOG "未找到快照"
        echo -e "${YELLOW}未找到快照${NC}"
    else
        LOG "快照列表："
        echo -e "${GREEN}快照列表：${NC}"
        echo "$snapshots" | tee -a "$LOG_FILE"
    fi
}

# 主函数
F_MAIN() {
    F_CHECK_ROOT
    F_CHECK_DEPS
    F_CHECK

    case "$ACTION" in
        create)
            F_CREATE_SNAPSHOT
            ;;
        revert)
            F_REVERT_SNAPSHOT
            ;;
        delete)
            F_DELETE_SNAPSHOT
            ;;
        list)
            F_LIST_SNAPSHOTS
            ;;
        *)
            ERROR "未指定操作！请使用 -c|-r|-d|-l"
            ;;
    esac

    LOG "操作完成"
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}操作完成${NC}"
}

# 解析参数
TEMP=$(getopt -o n:c:r:d:lhv --long name:,create:,revert:,delete:,list,help,version -- "$@")
if [[ $? -ne 0 ]]; then
    ERROR "解析参数失败！"
fi
eval set -- "$TEMP"

VM_NAME=""
SNAP_NAME=""
ACTION=""
QUIET="no"

while true; do
    case "$1" in
        -n|--name)
            if [[ -n "$VM_NAME" ]]; then
                ERROR "虚拟机名称只能指定一次！"
            fi
            VM_NAME="$2"
            shift 2
            ;;
        -c|--create)
            if [[ "$ACTION" && "$ACTION" != "create" ]]; then
                ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"
            fi
            ACTION="create"
            SNAP_NAME="$2"
            shift 2
            ;;
        -r|--revert)
            if [[ "$ACTION" && "$ACTION" != "revert" ]]; then
                ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"
            fi
            ACTION="revert"
            SNAP_NAME="$2"
            shift 2
            ;;
        -d|--delete)
            if [[ "$ACTION" && "$ACTION" != "delete" ]]; then
                ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"
            fi
            ACTION="delete"
            SNAP_NAME="$2"
            shift 2
            ;;
        -l|--list)
            if [[ "$ACTION" && "$ACTION" != "list" ]]; then
                ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"
            fi
            ACTION="list"
            shift
            ;;
        -h|--help)
            F_HELP
            exit 0
            ;;
        -v|--version)
            F_VERSION
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            ERROR "未知选项或参数：$1"
            ;;
    esac
done

# 处理剩余参数（仅用于省略 -n 的情况）
while [[ $# -gt 0 ]]; do
    if [[ -z "$VM_NAME" && "$1" != -* ]]; then
        VM_NAME="$1"
    else
        ERROR "无效参数：$1"
    fi
    shift
done

# 验证参数
if [[ -z "$VM_NAME" && "$ACTION" ]]; then
    ERROR "必须指定虚拟机名称！请使用 -n|--name 或直接提供虚拟机名称"
fi

if [[ "$ACTION" != "list" && -z "$SNAP_NAME" ]]; then
    ERROR "必须为操作 ${ACTION} 指定快照名称！"
fi

# 执行主逻辑
F_MAIN

exit 0

