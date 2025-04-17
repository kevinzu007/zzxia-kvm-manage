#!/bin/bash
#############################################################################
# Script Name: vm-snapshot.sh
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: Rocky Linux 9, CentOS 7/8, Ubuntu 20.04/22.04
# Updated By: DeepSeek & Gemini
# Update Date: 2025-04-17
# Current Version: 1.1.2
# Description: KVM虚拟机多磁盘快照管理工具
#
# Version History:
# 1.0.0 [2024-04-14] - 初始版本，支持单磁盘基础快照操作
# 1.0.6 [2025-04-15] - 增强错误处理和日志功能
# 1.1.0 [2025-04-17] - 新增多磁盘支持，增加--disk/--all-disks参数，增强安全控制
# 1.1.1 [2025-04-17] - 社区审查和初步改进建议
# 1.1.2 [2025-04-17] - 根据反馈优化错误处理、输出解析和参数要求
#
# Features:
# - 支持多磁盘虚拟机快照管理
# - 支持创建/回滚/删除/列出快照
# - 交互式确认和彩色输出
# - 完善的错误处理和日志记录
#############################################################################

# 脚本名称和版本
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

SCRIPT_NAME="${SH_NAME}"
VERSION="1.1.2" # 版本号更新

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 日志文件
LOG_FILE="/var/log/vm-snapshot.log"

# 临时文件列表 (当前未使用，保留供未来扩展)
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

# 清理临时文件 (当前未使用，保留供未来扩展)
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

# 获取虚拟机所有文件类型的磁盘路径 (已更新)
F_GET_DISKS() {
    local vm_name=$1
    local disk_list_output
    # 尝试获取磁盘列表，并将错误输出重定向，检查命令退出状态
    if ! disk_list_output=$(virsh domblklist "$vm_name" --details 2>/dev/null); then
        ERROR "无法获取虚拟机 '${vm_name}' 的磁盘列表。请检查 libvirtd 服务状态和权限。"
    fi
    # 使用 grep 和 awk 提取路径，精确匹配 'file' 类型的 'disk'，移除 sort -u
    echo "$disk_list_output" | grep -w 'disk' | grep -w 'file' | awk '{print $4}'
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

    # 获取磁盘列表
    if [[ -n "$SPECIFIC_DISK" ]]; then
        # 检查指定磁盘是否存在且为 qcow2
        if [[ ! -e "$SPECIFIC_DISK" ]]; then
             ERROR "指定的磁盘文件不存在：${SPECIFIC_DISK}"
        fi
        local disk_info
        disk_info=$(qemu-img info "$SPECIFIC_DISK" 2>/dev/null)
         if [[ -z "$disk_info" ]]; then
             ERROR "无法读取指定磁盘信息：${SPECIFIC_DISK}，可能文件损坏或被占用。"
         fi
         if ! echo "$disk_info" | grep -q "file format: qcow2"; then
             ERROR "指定的磁盘格式不是 qcow2：${SPECIFIC_DISK}"
         fi
        DISK_PATHS=("$SPECIFIC_DISK")
    else
        DISK_PATHS=()
        while IFS= read -r disk; do
            if [[ ! -e "$disk" ]]; then
                WARN "磁盘文件不存在：${disk}，跳过此磁盘"
                continue
            fi

            local disk_info
            disk_info=$(qemu-img info "$disk" 2>/dev/null)
            if [[ -z "$disk_info" ]]; then
                WARN "无法读取磁盘信息：${disk}，可能文件损坏或被占用，跳过此磁盘"
                continue
            fi
            if ! echo "$disk_info" | grep -q "file format: qcow2"; then
                WARN "磁盘格式不是 qcow2：${disk}，跳过此磁盘"
                continue
            fi

            DISK_PATHS+=("$disk")
        done < <(F_GET_DISKS "$VM_NAME") # 使用更新后的函数
    fi

    if [[ ${#DISK_PATHS[@]} -eq 0 ]]; then
        if [[ -n "$SPECIFIC_DISK" ]]; then
             ERROR "指定的磁盘 ${SPECIFIC_DISK} 无效或不是qcow2格式！"
        else
             ERROR "虚拟机 ${VM_NAME} 没有找到可用的qcow2格式磁盘！"
        fi
    fi
}

# 显示帮助信息 (已更新 --force 说明)
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
${GREEN}多磁盘支持：${NC}
    * 默认操作所有自动检测到的qcow2磁盘
    * 可使用 --disk 指定单个磁盘
    * 可使用 --all-disks 显式操作所有磁盘
${GREEN}依赖：${NC}
    * qemu-img
    * virsh
${GREEN}注意：${NC}
    * 必须在虚拟机关机状态下操作
    * 重要数据请提前备份，脚本会提示备份
    * 需要root权限执行
${GREEN}参数语法规范：${NC}
    无包围符号  ：-a              : 必选【选项】
                ：val             : 必选【参数值】
                ：val1 val2 -a -b : 必选【选项或参数值】，且不分先后顺序
    []          ：[-a]            : 可选【选项】
                ：[val]           : 可选【参数值】
    <>          ：<val>           : 需替换的具体值（用户必须提供）
    %%          ：%val%           : 通配符（包含匹配，如%error%匹配error_code）
    |           ：val1|val2|<valn> : 多选一
    {}          ：{-a <val>}      : 必须成组出现【选项+参数值】
                ：{val1 val2}     : 必须成组的【参数值组合】，且必须按顺序提供
${GREEN}用法：${NC}
    $0 -h|--help                                            #-- 显示帮助
    $0 -v|--version                                         #-- 显示版本
    $0 -l|--list {-n|--name <虚拟机名称>} [--disk <磁盘路径>] #-- 列出快照
    $0 {-c|--create <快照名称>} {-n|--name <虚拟机名称>} [--disk <磁盘路径> | --all-disks] #-- 创建快照
    $0 {-r|--revert <快照名称>} {-n|--name <虚拟机名称>} [--disk <磁盘路径> | --all-disks] [--force] #-- 回滚快照
    $0 {-d|--delete <快照名称>} {-n|--name <虚拟机名称>} [--disk <磁盘路径> | --all-disks] [--force] #-- 删除快照
${GREEN}参数说明：${NC}
    -h|--help           显示此帮助信息
    -v|--version        显示脚本版本
    -n|--name           指定虚拟机名称（必须与 -c|-r|-d|-l 成组使用）
    -c|--create         创建快照（需提供快照名称）
    -r|--revert         回滚到指定快照（需提供快照名称）
    -d|--delete         删除指定快照（需提供快照名称）
    -l|--list           列出虚拟机磁盘的所有快照
    --disk              指定要操作的单个磁盘路径 (与 --all-disks 互斥)
    --all-disks         显式指定操作所有自动检测到的qcow2磁盘（默认行为, 与 --disk 互斥）
    --force             (用于回滚/删除) 如果磁盘上不存在指定的快照，则跳过该磁盘而不报错，继续处理其他磁盘
    <虚拟机名称>        KVM虚拟机名称
    <快照名称>          快照的名称（如 before_extend_20250416）
    <磁盘路径>          磁盘文件的完整路径
${GREEN}使用示例：${NC}
    $0 -h                                       # 显示帮助信息
    $0 -v                                       # 显示版本信息
    $0 -c snap1 -n vm1                          # 为【vm1】所有qcow2磁盘创建快照【snap1】
    $0 -c snap1 -n vm1 --disk /path/to/disk1.qcow2 # 为【vm1】的指定磁盘创建快照
    $0 -r snap1 -n vm1                          # 将【vm1】所有qcow2磁盘回滚到快照【snap1】
    $0 -r snap1 -n vm1 --force                  # 回滚【vm1】所有qcow2磁盘，如果某磁盘无此快照则跳过
    $0 -d snap1 -n vm1 --disk /path/to/disk1.qcow2 # 删除【vm1】指定磁盘的快照
    $0 -l -n vm1                                # 列出【vm1】的所有qcow2磁盘上的快照
    $0 -l -n vm1 --disk /path/to/disk1.qcow2    # 列出【vm1】指定磁盘的快照
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

# 创建快照
F_CREATE_SNAPSHOT() {
    echo -e "
${GREEN}快照操作摘要：${NC}
  虚拟机：${VM_NAME}
  操作：创建快照
  快照名称：${SNAP_NAME}
  目标磁盘：${#DISK_PATHS[@]}块
======================================"

    for disk in "${DISK_PATHS[@]}"; do
        echo -e "  - ${disk}"
    done

    F_PROMPT "请确认以上信息是否正确？"

    local success_count=0
    local fail_count=0
    for disk in "${DISK_PATHS[@]}"; do
        LOG "正在为磁盘 ${disk} 创建快照 '${SNAP_NAME}'..."
        if ! qemu-img snapshot -c "$SNAP_NAME" "$disk"; then
            WARN "为磁盘 ${disk} 创建快照 '${SNAP_NAME}' 失败！" # 改为 WARN，允许继续处理其他磁盘
            ((fail_count++))
        else
             LOG "磁盘 ${disk} 快照 '${SNAP_NAME}' 创建成功"
            ((success_count++))
        fi
    done

    echo -e "${GREEN}======================================${NC}"
    if [[ $fail_count -gt 0 ]]; then
         WARN "${success_count} 个磁盘快照创建成功, ${fail_count} 个失败。"
         # 可以在这里考虑是否需要根据失败情况返回不同的退出码
    else
         echo -e "${GREEN}所有 ${success_count} 个磁盘快照 '${SNAP_NAME}' 创建成功${NC}"
    fi
}

# 回滚快照
F_REVERT_SNAPSHOT() {
    echo -e "
${GREEN}快照操作摘要：${NC}
  虚拟机：${VM_NAME}
  操作：回滚快照
  快照名称：${SNAP_NAME}
  目标磁盘：${#DISK_PATHS[@]}块
======================================"

    local disks_to_revert=()
    for disk in "${DISK_PATHS[@]}"; do
        # 检查快照是否存在
        if ! qemu-img snapshot -l "$disk" 2>/dev/null | grep -qw "$SNAP_NAME"; then
            if [[ "$FORCE" != "yes" ]]; then
                ERROR "磁盘 ${disk} 不存在快照 '${SNAP_NAME}'。请检查快照名称或使用 --force 跳过。"
            else
                WARN "磁盘 ${disk} 不存在快照 '${SNAP_NAME}'，根据 --force 选项跳过此磁盘。"
                continue # 跳过当前磁盘
            fi
        fi
        echo -e "  - ${disk}"
        disks_to_revert+=("$disk") # 将需要回滚的磁盘加入列表
    done

    if [[ ${#disks_to_revert[@]} -eq 0 ]]; then
        WARN "没有找到需要回滚的磁盘（可能所有磁盘都不存在该快照且使用了 --force）。"
        return # 直接返回，不提示确认
    fi

    F_PROMPT "请确认以上信息是否正确？（将回滚 ${#disks_to_revert[@]} 个磁盘）"

    local success_count=0
    local fail_count=0
    for disk in "${disks_to_revert[@]}"; do
         LOG "正在回滚磁盘 ${disk} 到快照 '${SNAP_NAME}'..."
         if ! qemu-img snapshot -a "$SNAP_NAME" "$disk"; then
             WARN "回滚磁盘 ${disk} 到快照 '${SNAP_NAME}' 失败！" # 改为 WARN
             ((fail_count++))
         else
             LOG "磁盘 ${disk} 已成功回滚到快照 '${SNAP_NAME}'"
            ((success_count++))
         fi
    done

    echo -e "${GREEN}======================================${NC}"
     if [[ $fail_count -gt 0 ]]; then
         WARN "${success_count} 个磁盘回滚成功, ${fail_count} 个失败。"
    else
         echo -e "${GREEN}所有 ${success_count} 个磁盘已成功回滚到快照 '${SNAP_NAME}'${NC}"
    fi
}

# 删除快照
F_DELETE_SNAPSHOT() {
    echo -e "
${GREEN}快照操作摘要：${NC}
  虚拟机：${VM_NAME}
  操作：删除快照
  快照名称：${SNAP_NAME}
  目标磁盘：${#DISK_PATHS[@]}块
======================================"

    local disks_to_delete_from=()
    for disk in "${DISK_PATHS[@]}"; do
        # 检查快照是否存在
        if ! qemu-img snapshot -l "$disk" 2>/dev/null | grep -qw "$SNAP_NAME"; then
             if [[ "$FORCE" != "yes" ]]; then
                 ERROR "磁盘 ${disk} 不存在快照 '${SNAP_NAME}'。请检查快照名称或使用 --force 跳过。"
             else
                 WARN "磁盘 ${disk} 不存在快照 '${SNAP_NAME}'，根据 --force 选项跳过此磁盘。"
                 continue # 跳过当前磁盘
             fi
        fi
         echo -e "  - ${disk}"
         disks_to_delete_from+=("$disk") # 将需要删除快照的磁盘加入列表
    done

     if [[ ${#disks_to_delete_from[@]} -eq 0 ]]; then
        WARN "没有找到需要删除快照的磁盘（可能所有磁盘都不存在该快照且使用了 --force）。"
        return # 直接返回，不提示确认
    fi

    F_PROMPT "请确认以上信息是否正确？（将从 ${#disks_to_delete_from[@]} 个磁盘删除快照）"

    local success_count=0
    local fail_count=0
    for disk in "${disks_to_delete_from[@]}"; do
        LOG "正在删除磁盘 ${disk} 的快照 '${SNAP_NAME}'..."
        if ! qemu-img snapshot -d "$SNAP_NAME" "$disk"; then
            WARN "删除磁盘 ${disk} 的快照 '${SNAP_NAME}' 失败！" # 改为 WARN
            ((fail_count++))
        else
            LOG "磁盘 ${disk} 的快照 '${SNAP_NAME}' 已删除"
            ((success_count++))
        fi
    done

    echo -e "${GREEN}======================================${NC}"
    if [[ $fail_count -gt 0 ]]; then
         WARN "${success_count} 个磁盘的快照删除成功, ${fail_count} 个失败。"
    else
         echo -e "${GREEN}所有 ${success_count} 个磁盘的快照 '${SNAP_NAME}' 已删除${NC}"
    fi
}

# 列出快照 (已更新)
F_LIST_SNAPSHOTS() {
    echo -e "${GREEN}列出虚拟机 ${VM_NAME} 的快照${NC}"
    local has_snapshots=0

    for disk in "${DISK_PATHS[@]}"; do
        echo -e "\n${BLUE}磁盘: ${disk}${NC}"
        local snapshots_output
        # 尝试获取快照列表，抑制错误输出
        snapshots_output=$(qemu-img snapshot -l "$disk" 2>/dev/null)
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
             WARN "无法列出磁盘 ${disk} 的快照 (qemu-img 返回错误码 ${exit_code})"
             continue # 处理下一个磁盘
        fi

        # 使用 grep 过滤表头，检查是否有快照内容
        local snapshot_list
        snapshot_list=$(echo "$snapshots_output" | grep -vE '^ID|^Snapshot list')

        if [[ -z "$snapshot_list" ]]; then
            echo -e "${YELLOW}  未找到快照${NC}"
        else
            has_snapshots=1
            # 输出过滤后的快照列表
            echo "$snapshot_list"
        fi
    done

    [[ $has_snapshots -eq 0 ]] && echo -e "\n${YELLOW}所有检查的磁盘均未找到快照${NC}"
}

# 主函数
F_MAIN() {
    F_CHECK_ROOT
    F_CHECK_DEPS
    F_CHECK # 执行检查，填充 DISK_PATHS

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
            # 这个分支理论上不应该被执行，因为参数解析阶段会检查 ACTION
            ERROR "未知的内部错误：无效的操作 '$ACTION'"
            ;;
    esac

    # LOG "操作完成" # 在每个具体操作函数末尾已有总结信息，此处可省略
    # echo -e "${GREEN}======================================${NC}"
    # echo -e "${GREEN}操作完成${NC}"
}

# 解析参数
# 注意：移除了处理末尾非选项参数作为 VM 名称的逻辑
TEMP=$(getopt -o n:c:r:d:lhv --long name:,create:,revert:,delete:,list,help,version,disk:,all-disks,force -n "$SCRIPT_NAME" -- "$@")
if [[ $? -ne 0 ]]; then
    ERROR "解析参数失败！请检查命令语法或使用 -h 查看帮助。"
fi
eval set -- "$TEMP"

VM_NAME=""
SNAP_NAME=""
ACTION=""
QUIET="no"
SPECIFIC_DISK=""
FORCE="no"
DISK_OPTION_SET=0 # 标记是否设置了 --disk 或 --all-disks

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
            if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"; fi
            ACTION="create"
            SNAP_NAME="$2"
            shift 2
            ;;
        -r|--revert)
             if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"; fi
            ACTION="revert"
            SNAP_NAME="$2"
            shift 2
            ;;
        -d|--delete)
             if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"; fi
            ACTION="delete"
            SNAP_NAME="$2"
            shift 2
            ;;
        -l|--list)
             if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作！仅支持 -c|-r|-d|-l 之一"; fi
            ACTION="list"
            shift
            ;;
        --disk)
            if [[ $DISK_OPTION_SET -ne 0 ]]; then ERROR "不能同时使用 --disk 和 --all-disks"; fi
            if [[ -n "$SPECIFIC_DISK" ]]; then ERROR "磁盘路径只能指定一次！"; fi
            SPECIFIC_DISK="$2"
            DISK_OPTION_SET=1
            shift 2
            ;;
        --all-disks)
             if [[ $DISK_OPTION_SET -ne 0 ]]; then ERROR "不能同时使用 --disk 和 --all-disks"; fi
            SPECIFIC_DISK="" # 显式要求操作所有磁盘 (保持用于代码可读性)
            DISK_OPTION_SET=1
            shift
            ;;
        --force)
            FORCE="yes"
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
            ERROR "内部错误：未知的 getopt 输出 '$1'" # getopt 正常工作时不应出现
            ;;
    esac
done

# 验证参数
if [[ -z "$ACTION" ]]; then
    ERROR "必须指定一个操作！请使用 -c, -r, -d 或 -l 中的一个。"
fi

# 强制要求使用 -n 或 --name
if [[ -z "$VM_NAME" ]]; then
    ERROR "必须使用 -n 或 --name 指定虚拟机名称！"
fi

if [[ "$ACTION" != "list" && -z "$SNAP_NAME" ]]; then
    ERROR "必须为操作 '${ACTION}' 指定快照名称！"
fi

# 执行主逻辑
F_MAIN

exit 0

