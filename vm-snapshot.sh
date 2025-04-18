#!/bin/bash
#############################################################################
# Script Name: vm-snapshot.sh
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: Rocky Linux 9, CentOS 7/8, Ubuntu 20.04/22.04
# Updated By: DeepSeek & Gemini
# Update Date: 2025-04-18
# Current Version: 1.2.2 # 更新版本号
# Description: KVM虚拟机多磁盘快照管理工具 (支持在线和离线模式)
#
# Version History:
# ... (previous history) ...
# 1.2.1 [2025-04-18] - 修正 F_CREATE_LIVE_SNAPSHOT 中条件输出的 Bash 语法错误
# 1.2.2 [2025-04-18] - 恢复 F_HELP 中的参数语法规范说明，统一帮助信息缩进
#
# Features:
# - 支持在线 (live) 和离线 (offline) 虚拟机快照管理
# - 在线模式使用 virsh 外部快照，支持 --quiesce (需Guest Agent), --disk-only
# - 离线模式使用 qemu-img 内部快照 (原功能)
# - 支持创建/回滚/删除/列出快照
# - 交互式确认和彩色输出
# - 完善的错误处理和日志记录
#############################################################################

# 脚本名称和版本
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

SCRIPT_NAME="${SH_NAME}"
VERSION="1.2.2" # 版本号更新

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

# --- 全局变量 ---
LIVE_MODE="no" # 是否为在线模式
DISK_ONLY="no" # 是否仅磁盘快照 (在线模式)
NO_QUIESCE="no" # 是否禁用静默 (在线模式)
QUIET="no"
FORCE="no"
VM_NAME=""
SNAP_NAME=""
ACTION=""
SPECIFIC_DISK="" # 用于离线模式指定磁盘路径
DISK_TARGETS=() # 存储磁盘信息 (路径或设备名)
DISK_PATHS=()   # 存储文件路径 (主要用于离线模式或获取基础信息)
DISK_DEVICES=() # 存储设备名 (如 vda, vdb，用于在线模式)

# --- 日志与清理函数 (无变化) ---
LOG() {
    if [ "$QUIET" != "yes" ]; then
        echo -e "${GREEN}[$(date "+%H:%M:%S")] ${SH_NAME}: $*${NC}"
    fi
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*" >> "$LOG_FILE"
}
ERROR() {
    echo -e "${RED}[$(date "+%H:%M:%S")] ${SH_NAME}: $*${NC}" >&2
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: ERROR: $*" >> "$LOG_FILE"
    exit 1
}
WARN() {
    if [ "$QUIET" != "yes" ]; then
        echo -e "${YELLOW}[$(date "+%H:%M:%S")] ${SH_NAME}: $*${NC}"
    fi
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: WARN: $*" >> "$LOG_FILE"
}
F_CLEANUP() {
    for file in "${TEMP_FILES[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file" && LOG "已清理临时文件: $file"
        fi
    done
}
trap F_CLEANUP EXIT INT TERM

# --- 检查函数 ---
F_CHECK_ROOT() {
    if [ "$(id -u)" != "0" ]; then
        ERROR "此脚本需要 root 权限运行！请使用 sudo 或以 root 用户执行。"
    fi
}
F_CHECK_DEPS() {
    local deps=("virsh") # virsh 是核心依赖
    if [[ "$LIVE_MODE" == "no" ]]; then
        deps+=("qemu-img") # 离线模式需要 qemu-img
    fi
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            ERROR "缺少依赖工具：${dep}。请安装后再运行。"
        fi
    done
}

# 获取虚拟机磁盘信息 (设备名和当前源文件)
# 输出格式: device:source_file (例如: vda:/var/lib/libvirt/images/vm1.qcow2)
F_GET_VM_DISKS_INFO() {
    local vm_name=$1
    local disk_list_output
    if ! disk_list_output=$(virsh domblklist "$vm_name" --details 2>/dev/null); then
        ERROR "无法获取虚拟机 '${vm_name}' 的磁盘列表。请检查 libvirtd 服务状态和权限。"
    fi
    # 过滤出类型为 'file' 或 'block' 的 'disk'，并提取 Target 和 Source
    echo "$disk_list_output" | awk '
        /disk/ && ($2 == "file" || $2 == "block") {
            target = $3
            source = $4
            # 尝试处理无 Source 的情况 (例如 CDROM)，虽然理论上不应匹配 disk
            if (source == "-") source = "N/A"
            print target ":" source
        }'
}

# 检查虚拟机和磁盘 (根据模式调整)
F_CHECK() {
    # 检查虚拟机存在
    if ! virsh list --all --name | grep -qw "^${VM_NAME}$"; then
        ERROR "虚拟机 '${VM_NAME}' 不存在！"
    fi

    # 检查虚拟机状态 (仅离线模式需要关机)
    local vm_state
    vm_state=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "未定义")

    if [[ "$LIVE_MODE" == "no" ]]; then
        if [[ "$vm_state" != "shut off" ]]; then
            ERROR "离线模式要求虚拟机 '${VM_NAME}' 处于关机状态！当前状态：${vm_state}。请先关机或使用 --live 参数。"
        fi
    else # 在线模式
        if [[ "$vm_state" != "running" ]]; then
             WARN "在线模式通常在虚拟机运行时使用。当前状态：${vm_state}。继续操作..."
        fi
        # 在线模式警告 Guest Agent
        if [[ "$ACTION" == "create" && "$NO_QUIESCE" == "no" ]]; then
             WARN "在线快照一致性依赖 QEMU Guest Agent。请确保 '${VM_NAME}' 内部已安装并运行 qemu-guest-agent 服务，否则快照可能不是文件系统一致的。"
             # 注意：从外部可靠检查 Guest Agent 状态比较困难，这里只做提示。
        fi
    fi

    # --- 获取和验证磁盘 ---
    DISK_PATHS=()
    DISK_DEVICES=()
    DISK_TARGETS=() # 清空数组

    local disk_info_list
    disk_info_list=$(F_GET_VM_DISKS_INFO "$VM_NAME")
    if [[ -z "$disk_info_list" ]]; then
        ERROR "未能获取到虚拟机 '${VM_NAME}' 的任何磁盘信息。"
    fi

    if [[ "$LIVE_MODE" == "no" && -n "$SPECIFIC_DISK" ]]; then
        # --- 离线模式：处理 --disk 参数 ---
        local found_specific=0
        while IFS= read -r line; do
            local device=${line%%:*}
            local source_file=${line#*:}
            if [[ "$source_file" == "$SPECIFIC_DISK" ]]; then
                 if [[ ! -e "$source_file" ]]; then
                      ERROR "指定的磁盘文件不存在：${source_file}"
                 fi
                 local qemu_info
                 qemu_info=$(qemu-img info "$source_file" 2>/dev/null)
                 if [[ -z "$qemu_info" ]]; then
                      ERROR "无法读取指定磁盘信息：${source_file}，可能文件损坏或被占用。"
                 fi
                 if ! echo "$qemu_info" | grep -q "file format: qcow2"; then
                      ERROR "离线模式仅支持 qcow2 格式。指定的磁盘 ${source_file} 格式不支持。"
                 fi
                 DISK_TARGETS+=("$source_file") # 离线模式目标是文件路径
                 DISK_PATHS+=("$source_file")
                 DISK_DEVICES+=("$device") # 也记录设备名备用
                 found_specific=1
                 break
            fi
        done <<< "$disk_info_list"
        if [[ $found_specific -eq 0 ]]; then
            ERROR "虚拟机 '${VM_NAME}' 中未找到路径为 '${SPECIFIC_DISK}' 的磁盘。"
        fi
    else
        # --- 在线模式 或 离线模式（所有磁盘） ---
        while IFS= read -r line; do
             local device=${line%%:*}
             local source_file=${line#*:}

             if [[ "$source_file" == "N/A" ]]; then
                 WARN "跳过设备 '${device}'，因为它没有有效的源文件/块设备。"
                 continue
             fi

             # 检查源是否存在 (文件或块设备)
             if [[ ! -e "$source_file" && ! -b "$source_file" ]]; then
                 WARN "磁盘源不存在：${source_file} (设备 ${device})，跳过此磁盘。"
                 continue
             fi

             # 离线模式下，只处理 qcow2 文件
             if [[ "$LIVE_MODE" == "no" ]]; then
                 if [[ -f "$source_file" ]]; then # 确保是文件
                     local qemu_info
                     qemu_info=$(qemu-img info "$source_file" 2>/dev/null)
                     if [[ -z "$qemu_info" ]]; then
                         WARN "无法读取磁盘信息：${source_file} (设备 ${device})，可能文件损坏或被占用，跳过此磁盘。"
                         continue
                     fi
                     if ! echo "$qemu_info" | grep -q "file format: qcow2"; then
                         WARN "离线模式仅支持 qcow2 格式：${source_file} (设备 ${device})，跳过此磁盘。"
                         continue
                     fi
                     DISK_TARGETS+=("$source_file") # 离线模式目标是文件路径
                 else
                      WARN "离线模式跳过非文件磁盘源：${source_file} (设备 ${device})"
                      continue
                 fi
             else # 在线模式
                 DISK_TARGETS+=("$device") # 在线模式目标是设备名
             fi
             # 始终记录路径和设备名
             DISK_PATHS+=("$source_file")
             DISK_DEVICES+=("$device")
        done <<< "$disk_info_list"
    fi

    if [[ ${#DISK_TARGETS[@]} -eq 0 ]]; then
        if [[ "$LIVE_MODE" == "no" && -n "$SPECIFIC_DISK" ]]; then
             ERROR "指定的磁盘 ${SPECIFIC_DISK} 无效或不满足离线模式要求 (qcow2 格式)！"
        elif [[ "$LIVE_MODE" == "no" ]]; then
             ERROR "虚拟机 ${VM_NAME} 没有找到可用的 qcow2 格式磁盘进行离线操作！"
        else
             ERROR "虚拟机 ${VM_NAME} 没有找到可用的磁盘进行在线操作！"
        fi
    fi
}

# --- 帮助和版本函数 ---
F_HELP() {
    # 使用 cat 和 HERE document 来简化多行 echo 的格式化
    cat <<-EOF

${GREEN}用途：${NC}管理KVM虚拟机的磁盘快照（支持在线和离线模式）
${GREEN}模式：${NC}
    * ${YELLOW}离线模式 (默认):${NC} 使用 qemu-img 管理 qcow2 文件的内部快照。
        - ${RED}要求：${NC}虚拟机必须处于关机 (shut off) 状态。
        - 支持 --disk 指定单个 qcow2 文件。
    * ${YELLOW}在线模式 (--live):${NC} 使用 virsh 管理虚拟机的外部快照。
        - ${GREEN}要求：${NC}虚拟机通常处于运行 (running) 状态。
        - ${GREEN}一致性：${NC}强烈建议虚拟机内部安装并运行 qemu-guest-agent 以确保一致性 (使用 --quiesce)。
        - 支持 --disk-only (仅磁盘快照) 和 --no-quiesce (禁用冻结)。
        - ${RED}在线删除警告：${NC}在线删除 (-d --live) 执行 blockcommit 合并当前层，**非常消耗I/O**，请在维护窗口操作。
${GREEN}支持存储类型：${NC}
    * 离线模式：本地 qcow2 文件
    * 在线模式：libvirt 支持的块设备 (文件、LVM、iSCSI 等，只要 virsh 能管理)
${GREEN}依赖：${NC}
    * virsh (所有模式)
    * qemu-img (仅离线模式)
${GREEN}注意：${NC}
    * 重要数据请提前备份。
    * 需要 root 权限执行。
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
    $0 -h|--help                                            # 显示帮助
    $0 -v|--version                                         # 显示版本

    # 离线模式 (VM需关机)
    $0 -l|--list {-n <VM名>} [--disk <qcow2路径>]           # 列出内部快照
    $0 {-c <快照名>} {-n <VM名>} [--disk <qcow2路径>]         # 创建内部快照
    $0 {-r <快照名>} {-n <VM名>} [--disk <qcow2路径>] [--force] # 回滚内部快照
    $0 {-d <快照名>} {-n <VM名>} [--disk <qcow2路径>] [--force] # 删除内部快照

    # 在线模式 (VM需运行, 推荐带 Guest Agent)
    $0 -l|--list {-n <VM名>} --live                         # 列出外部快照
    $0 {-c <快照名>} {-n <VM名>} --live [--disk-only] [--no-quiesce] # 创建外部快照
    $0 {-r <快照名>} {-n <VM名>} --live [--force]             # 回滚外部快照
    $0 {-d <快照名>} {-n <VM名>} --live [--force]             # ${RED}在线合并当前层 (高危I/O操作)${NC}

${GREEN}参数说明：${NC}
    -h|--help           显示此帮助信息
    -v|--version        显示脚本版本
    -n|--name <VM名>    指定虚拟机名称 (必需)
    -c|--create <快照名> 创建快照
    -r|--revert <快照名> 回滚到指定快照
    -d|--delete <快照名> 删除指定快照 (离线) / ${RED}在线合并当前层${NC} (在线)
    -l|--list           列出快照
    --live              启用在线快照模式 (使用 virsh 外部快照)
    --disk <路径>       (仅离线模式) 指定要操作的单个 qcow2 磁盘文件路径
    --all-disks         (仅离线模式) 显式指定操作所有 qcow2 磁盘 (默认行为)
    --force             离线模式: 跳过快照存在性检查; 在线回滚: 强制回滚; 在线删除: 跳过确认提示? (待定)
    --disk-only         (仅在线创建) 只创建磁盘快照，不包含内存状态
    --no-quiesce        (仅在线创建) 强制不使用 quiesce (冻结)，快照可能非一致
    <快照名>            快照的名称
${GREEN}使用示例：${NC}
    # 离线
    $0 -c snap_offline -n vm1
    $0 -l -n vm1 --disk /path/to/disk.qcow2
    # 在线
    $0 -c snap_live -n vm1 --live --disk-only # 创建在线仅磁盘快照 (推荐)
    $0 -l -n vm1 --live
    $0 -r snap_live -n vm1 --live
    $0 -d any_name -n vm1 --live # ${RED}警告：此操作将合并 vm1 当前的快照层，'any_name' 仅用于标识操作${NC}

EOF
}
F_VERSION() {
    echo -e "${GREEN}${SCRIPT_NAME} ${VERSION}${NC}"
}

# --- 交互与核心逻辑函数 ---
F_PROMPT() {
    # 如果设置了 --force (且非在线删除场景)，则跳过提示? - 待定，目前 force 只影响检查
    # if [[ "$FORCE" == "yes" && ! ("$ACTION" == "delete" && "$LIVE_MODE" == "yes") ]]; then
    #     WARN "--force 已指定，跳过确认提示。"
    #     return 0
    # fi

    local prompt="$1"
    local response
    echo -e "${YELLOW}${prompt}${NC}"
    echo -n "是否确认？(y/N): "
    read -r response
    if [[ ! "$response" =~ ^[yY]$ ]]; then
        ERROR "用户取消操作！"
    fi
}

# --- 离线模式函数 (qemu-img) ---
F_CREATE_OFFLINE_SNAPSHOT() {
    echo -e "\n${GREEN}[离线模式] 快照操作摘要：${NC}"
    echo "  虚拟机：${VM_NAME}"
    echo "  操作：创建内部快照"
    echo "  快照名称：${SNAP_NAME}"
    echo "  目标磁盘："
    for target in "${DISK_TARGETS[@]}"; do echo "    - ${target}"; done
    echo "======================================"
    F_PROMPT "请确认以上信息是否正确？"

    local success_count=0 fail_count=0
    for disk_path in "${DISK_TARGETS[@]}"; do
        LOG "[离线] 正在为磁盘 ${disk_path} 创建快照 '${SNAP_NAME}'..."
        if ! qemu-img snapshot -c "$SNAP_NAME" "$disk_path"; then
            WARN "[离线] 为磁盘 ${disk_path} 创建快照 '${SNAP_NAME}' 失败！"
            ((fail_count++))
        else
             LOG "[离线] 磁盘 ${disk_path} 快照 '${SNAP_NAME}' 创建成功"
            ((success_count++))
        fi
    done
    # ... (总结输出同前) ...
     echo -e "${GREEN}======================================${NC}"
    if [[ $fail_count -gt 0 ]]; then
         WARN "[离线] ${success_count} 个磁盘快照创建成功, ${fail_count} 个失败。"
    else
         echo -e "${GREEN}[离线] 所有 ${success_count} 个磁盘快照 '${SNAP_NAME}' 创建成功${NC}"
    fi
}
F_REVERT_OFFLINE_SNAPSHOT() {
     echo -e "\n${GREEN}[离线模式] 快照操作摘要：${NC}"
     echo "  虚拟机：${VM_NAME}"
     echo "  操作：回滚内部快照"
     echo "  快照名称：${SNAP_NAME}"
     echo "  目标磁盘："

    local disks_to_revert=()
    for disk_path in "${DISK_TARGETS[@]}"; do
        if ! qemu-img snapshot -l "$disk_path" 2>/dev/null | grep -qw "$SNAP_NAME"; then
            if [[ "$FORCE" != "yes" ]]; then
                ERROR "[离线] 磁盘 ${disk_path} 不存在快照 '${SNAP_NAME}'。请检查快照名称或使用 --force 跳过。"
            else
                WARN "[离线] 磁盘 ${disk_path} 不存在快照 '${SNAP_NAME}'，根据 --force 选项跳过此磁盘。"
                continue
            fi
        fi
        echo "    - ${disk_path}"
        disks_to_revert+=("$disk_path")
    done

    if [[ ${#disks_to_revert[@]} -eq 0 ]]; then
        WARN "[离线] 没有找到需要回滚的磁盘。"
        return
    fi
    echo "======================================"
    F_PROMPT "请确认以上信息是否正确？（将回滚 ${#disks_to_revert[@]} 个磁盘）"

    local success_count=0 fail_count=0
    for disk_path in "${disks_to_revert[@]}"; do
         LOG "[离线] 正在回滚磁盘 ${disk_path} 到快照 '${SNAP_NAME}'..."
         if ! qemu-img snapshot -a "$SNAP_NAME" "$disk_path"; then
             WARN "[离线] 回滚磁盘 ${disk_path} 到快照 '${SNAP_NAME}' 失败！"
             ((fail_count++))
         else
             LOG "[离线] 磁盘 ${disk_path} 已成功回滚到快照 '${SNAP_NAME}'"
            ((success_count++))
         fi
    done
    # ... (总结输出同前) ...
    echo -e "${GREEN}======================================${NC}"
     if [[ $fail_count -gt 0 ]]; then
         WARN "[离线] ${success_count} 个磁盘回滚成功, ${fail_count} 个失败。"
    else
         echo -e "${GREEN}[离线] 所有 ${success_count} 个磁盘已成功回滚到快照 '${SNAP_NAME}'${NC}"
    fi
}
F_DELETE_OFFLINE_SNAPSHOT() {
     echo -e "\n${GREEN}[离线模式] 快照操作摘要：${NC}"
     echo "  虚拟机：${VM_NAME}"
     echo "  操作：删除内部快照"
     echo "  快照名称：${SNAP_NAME}"
     echo "  目标磁盘："

    local disks_to_delete_from=()
    for disk_path in "${DISK_TARGETS[@]}"; do
        if ! qemu-img snapshot -l "$disk_path" 2>/dev/null | grep -qw "$SNAP_NAME"; then
             if [[ "$FORCE" != "yes" ]]; then
                 ERROR "[离线] 磁盘 ${disk_path} 不存在快照 '${SNAP_NAME}'。请检查快照名称或使用 --force 跳过。"
             else
                 WARN "[离线] 磁盘 ${disk_path} 不存在快照 '${SNAP_NAME}'，根据 --force 选项跳过此磁盘。"
                 continue
             fi
        fi
         echo "    - ${disk_path}"
         disks_to_delete_from+=("$disk_path")
    done

     if [[ ${#disks_to_delete_from[@]} -eq 0 ]]; then
        WARN "[离线] 没有找到需要删除快照的磁盘。"
        return
    fi
    echo "======================================"
    F_PROMPT "请确认以上信息是否正确？（将从 ${#disks_to_delete_from[@]} 个磁盘删除快照）"

    local success_count=0 fail_count=0
    for disk_path in "${disks_to_delete_from[@]}"; do
        LOG "[离线] 正在删除磁盘 ${disk_path} 的快照 '${SNAP_NAME}'..."
        if ! qemu-img snapshot -d "$SNAP_NAME" "$disk_path"; then
            WARN "[离线] 删除磁盘 ${disk_path} 的快照 '${SNAP_NAME}' 失败！"
            ((fail_count++))
        else
            LOG "[离线] 磁盘 ${disk_path} 的快照 '${SNAP_NAME}' 已删除"
            ((success_count++))
        fi
    done
    # ... (总结输出同前) ...
    echo -e "${GREEN}======================================${NC}"
    if [[ $fail_count -gt 0 ]]; then
         WARN "[离线] ${success_count} 个磁盘的快照删除成功, ${fail_count} 个失败。"
    else
         echo -e "${GREEN}[离线] 所有 ${success_count} 个磁盘的快照 '${SNAP_NAME}' 已删除${NC}"
    fi
}
F_LIST_OFFLINE_SNAPSHOTS() {
    echo -e "${GREEN}[离线模式] 列出虚拟机 ${VM_NAME} 的内部快照${NC}"
    local has_snapshots=0

    for disk_path in "${DISK_TARGETS[@]}"; do
        echo -e "\n${BLUE}磁盘: ${disk_path}${NC}"
        local snapshots_output
        snapshots_output=$(qemu-img snapshot -l "$disk_path" 2>/dev/null)
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
             WARN "[离线] 无法列出磁盘 ${disk_path} 的快照 (qemu-img 返回错误码 ${exit_code})"
             continue
        fi

        local snapshot_list
        snapshot_list=$(echo "$snapshots_output" | grep -vE '^ID|^Snapshot list') # 使用 grep 过滤

        if [[ -z "$snapshot_list" ]]; then
            echo -e "${YELLOW}  未找到快照${NC}"
        else
            has_snapshots=1
            echo "$snapshot_list"
        fi
    done

    [[ $has_snapshots -eq 0 ]] && echo -e "\n${YELLOW}所有检查的磁盘均未找到内部快照${NC}"
}

# --- 在线模式函数 (virsh) ---
F_CREATE_LIVE_SNAPSHOT() {
    echo -e "\n${GREEN}[在线模式] 快照操作摘要：${NC}"
    echo "  虚拟机：${VM_NAME}"
    echo "  操作：创建外部快照"
    echo "  快照名称：${SNAP_NAME}"
    # --- 已修正的部分 开始 ---
    local mode_str=""
    if [[ "$DISK_ONLY" == "yes" ]]; then
        mode_str="仅磁盘"
    else
        mode_str="磁盘和内存"
    fi
    echo "  模式：${mode_str}"

    local consistency_str=""
    if [[ "$NO_QUIESCE" == "yes" ]]; then
        consistency_str="${RED}未尝试冻结 (可能不一致)${NC}"
    else
        consistency_str="${GREEN}尝试冻结 (需 Guest Agent)${NC}"
    fi
    echo "  一致性：${consistency_str}"
    # --- 已修正的部分 结束 ---
    echo "  涉及磁盘设备："
    local diskspec_args=()
    local i=0
    for device in "${DISK_DEVICES[@]}"; do
        local base_file="${DISK_PATHS[$i]}"
        # 生成快照文件名 (放在原文件同目录)
        local base_dir=$(dirname "$base_file")
        local base_name=$(basename "$base_file")
        # 处理没有扩展名的情况
        local ext=""
        if [[ "$base_name" == *.* ]]; then
            ext=".${base_name##*.}"
        fi
        local name_noext="${base_name%.*}"
        # 确保快照文件名中不包含非法字符，例如空格（尽管快照名本身可能包含）
        local safe_snap_name=$(echo "$SNAP_NAME" | tr -s ' ' '_') # 简单替换空格为下划线
        local snap_file="${base_dir}/${name_noext}-${safe_snap_name}${ext}"

        echo "    - ${device} (快照文件: ${snap_file})"
        # 检查潜在的文件名冲突
        if [[ -e "$snap_file" ]]; then
            ERROR "目标快照文件已存在: ${snap_file}。请选择不同的快照名称或清理旧文件。"
        fi
        diskspec_args+=( "--diskspec" "${device},snapshot=external,file=${snap_file}" )
        ((i++))
    done
     echo "======================================"
     F_PROMPT "请确认以上信息是否正确？"

    local virsh_cmd=("virsh" "snapshot-create-as" "$VM_NAME" "$SNAP_NAME" "--atomic")

    if [[ "$DISK_ONLY" == "yes" ]]; then
        virsh_cmd+=("--disk-only")
    fi
    if [[ "$NO_QUIESCE" == "no" ]]; then
        virsh_cmd+=("--quiesce")
    fi

    virsh_cmd+=( "${diskspec_args[@]}" )

    LOG "[在线] 正在执行: ${virsh_cmd[*]}"
    if ! "${virsh_cmd[@]}"; then
        ERROR "[在线] 创建快照 '${SNAP_NAME}' 失败！请检查 virsh 输出和 libvirt 日志。"
    fi

    LOG "[在线] 快照 '${SNAP_NAME}' 创建成功！"
    echo -e "${GREEN}[在线] 快照 '${SNAP_NAME}' 创建成功！${NC}"
    echo -e "${GREEN}======================================${NC}"
}
F_REVERT_LIVE_SNAPSHOT() {
    echo -e "\n${GREEN}[在线模式] 快照操作摘要：${NC}"
    echo "  虚拟机：${VM_NAME}"
    echo "  操作：回滚外部快照"
    echo "  快照名称：${SNAP_NAME}"
    echo "======================================"
    # 检查快照是否存在
    if ! virsh snapshot-list "$VM_NAME" | grep -qw "$SNAP_NAME"; then
         ERROR "[在线] 虚拟机 '${VM_NAME}' 不存在名为 '${SNAP_NAME}' 的快照。"
    fi

    # 在线回滚通常比较危险，再次确认
    echo -e "${YELLOW}警告：回滚在线快照将丢失当前状态，恢复到 '${SNAP_NAME}' 的状态。${NC}"
    F_PROMPT "请确认要回滚到快照 '${SNAP_NAME}'？"

    local virsh_cmd=("virsh" "snapshot-revert" "$VM_NAME" "$SNAP_NAME")
    # virsh snapshot-revert 似乎没有明显的 --force 选项来跳过检查
    # 但可以添加 --force 来强制执行某些恢复操作（如果libvirt支持）
    if [[ "$FORCE" == "yes" ]]; then
        WARN "[在线] 使用 --force 强制回滚 (如果libvirt支持)..."
        virsh_cmd+=("--force")
    fi

    LOG "[在线] 正在执行: ${virsh_cmd[*]}"
    if ! "${virsh_cmd[@]}"; then
        ERROR "[在线] 回滚到快照 '${SNAP_NAME}' 失败！请检查 virsh 输出和 libvirt 日志。"
    fi

    LOG "[在线] 虚拟机已成功回滚到快照 '${SNAP_NAME}'。"
    echo -e "${GREEN}[在线] 虚拟机已成功回滚到快照 '${SNAP_NAME}'。${NC}"
    echo -e "${GREEN}======================================${NC}"
}
F_DELETE_LIVE_SNAPSHOT() {
    # 实现方案 A: blockcommit --active --pivot
    echo -e "\n${RED}[在线模式] ${YELLOW}快照删除 (Block Commit) 操作摘要：${NC}"
    echo "  虚拟机：${VM_NAME}"
    echo "  操作：${RED}在线合并当前活动的快照层${NC}"
    echo "  目标：将当前所有磁盘的最新更改合并到其父快照/基础镜像"
    echo "  涉及磁盘设备："
    for device in "${DISK_DEVICES[@]}"; do echo "    - ${device}"; done
    echo "======================================"
    echo -e "${RED}警告：此操作将在线合并磁盘数据，会产生大量磁盘 I/O，${NC}"
    echo -e "${RED}      可能显著影响虚拟机 '${VM_NAME}' 的性能！${NC}"
    echo -e "${YELLOW}      强烈建议在业务低峰期或维护窗口执行。${NC}"
    echo -e "${YELLOW}      快照名称 '${SNAP_NAME}' 在此操作中仅用于标识，实际操作是合并当前层。${NC}"

    # 如果指定了 --force，可以跳过确认？(根据需求决定)
    if [[ "$FORCE" != "yes" ]]; then
        F_PROMPT "请确认要执行在线 Block Commit 操作？"
    else
        WARN "--force 已指定，跳过 Block Commit 的最终确认！"
    fi

    local success_count=0 fail_count=0
    for device in "${DISK_DEVICES[@]}"; do
        LOG "[在线] 正在为磁盘设备 ${device} 执行 blockcommit --active --pivot..."
        local virsh_cmd=("virsh" "blockcommit" "$VM_NAME" "$device" "--active" "--verbose" "--pivot")
        LOG "[在线] 执行命令: ${virsh_cmd[*]}"

        # 执行 blockcommit 并捕获输出和错误
        local output
        if ! output=$("${virsh_cmd[@]}" 2>&1); then
            WARN "[在线] 磁盘 ${device} 的 blockcommit 操作失败！"
            WARN "错误信息: ${output}"
            ((fail_count++))
        else
            LOG "[在线] 磁盘 ${device} 的 blockcommit 操作成功。"
            LOG "输出信息: ${output}"
            ((success_count++))
        fi
    done

    echo -e "${GREEN}======================================${NC}"
    if [[ $fail_count -gt 0 ]]; then
         WARN "[在线] ${success_count} 个磁盘的 Block Commit 操作成功, ${fail_count} 个失败。请检查日志和虚拟机状态。"
    else
         echo -e "${GREEN}[在线] 所有 ${success_count} 个磁盘的 Block Commit 操作成功完成。${NC}"
    fi
}
F_LIST_LIVE_SNAPSHOTS() {
    echo -e "${GREEN}[在线模式] 列出虚拟机 ${VM_NAME} 的外部快照${NC}"
    local snapshot_list
    if ! snapshot_list=$(virsh snapshot-list "$VM_NAME" 2>/dev/null); then
        # 可能是没有快照，也可能是错误
        if virsh snapshot-list "$VM_NAME" --no-inactive >/dev/null 2>&1; then # 尝试用不同选项探测是否存在
             echo -e "${YELLOW}未找到任何外部快照。${NC}"
        else
             ERROR "[在线] 无法列出虚拟机 '${VM_NAME}' 的快照。请检查 libvirt 服务和权限。"
        fi
        return
    fi

    # 检查是否有实际内容 (除了表头)
    if [[ $(echo "$snapshot_list" | wc -l) -le 2 ]]; then
         echo -e "${YELLOW}未找到任何外部快照。${NC}"
    else
        echo "${snapshot_list}" # 直接输出 virsh 的格式化列表
        # 可以考虑添加 --tree 选项的解析
        # if virsh snapshot-list "$VM_NAME" --tree >/dev/null 2>&1; then
        #     echo -e "\n${BLUE}快照树状结构:${NC}"
        #     virsh snapshot-list "$VM_NAME" --tree
        # fi
    fi
    echo -e "${GREEN}======================================${NC}"
}


# --- 主函数 ---
F_MAIN() {
    F_CHECK_ROOT
    F_CHECK_DEPS # 检查依赖要在 F_CHECK 之前，因为 F_CHECK 会用到 virsh
    F_CHECK      # 执行检查，填充 DISK_* 数组

    # 根据模式分发任务
    if [[ "$LIVE_MODE" == "yes" ]]; then
        case "$ACTION" in
            create) F_CREATE_LIVE_SNAPSHOT ;;
            revert) F_REVERT_LIVE_SNAPSHOT ;;
            delete) F_DELETE_LIVE_SNAPSHOT ;; # 调用在线删除 (blockcommit)
            list)   F_LIST_LIVE_SNAPSHOTS ;;
            *)      ERROR "内部错误：无效的在线操作 '$ACTION'" ;;
        esac
    else # 离线模式
        case "$ACTION" in
            create) F_CREATE_OFFLINE_SNAPSHOT ;;
            revert) F_REVERT_OFFLINE_SNAPSHOT ;;
            delete) F_DELETE_OFFLINE_SNAPSHOT ;; # 调用离线删除 (qemu-img)
            list)   F_LIST_OFFLINE_SNAPSHOTS ;;
            *)      ERROR "内部错误：无效的离线操作 '$ACTION'" ;;
        esac
    fi
}

# --- 参数解析 ---
TEMP=$(getopt -o n:c:r:d:lhv \
             --long name:,create:,revert:,delete:,list,help,version,live,disk:,all-disks,force,disk-only,no-quiesce \
             -n "$SCRIPT_NAME" -- "$@")
if [[ $? -ne 0 ]]; then
    ERROR "解析参数失败！请检查命令语法或使用 -h 查看帮助。"
fi
eval set -- "$TEMP"

# 重置全局变量默认值
LIVE_MODE="no"; DISK_ONLY="no"; NO_QUIESCE="no"; QUIET="no"; FORCE="no";
VM_NAME=""; SNAP_NAME=""; ACTION=""; SPECIFIC_DISK="";
DISK_OPTION_SET=0 # 用于离线模式的 --disk/--all-disks 互斥检查

while true; do
    case "$1" in
        -n|--name) VM_NAME="$2"; shift 2 ;;
        -c|--create) if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作"; fi; ACTION="create"; SNAP_NAME="$2"; shift 2 ;;
        -r|--revert) if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作"; fi; ACTION="revert"; SNAP_NAME="$2"; shift 2 ;;
        -d|--delete) if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作"; fi; ACTION="delete"; SNAP_NAME="$2"; shift 2 ;;
        -l|--list)   if [[ -n "$ACTION" ]]; then ERROR "不能同时指定多个操作"; fi; ACTION="list"; shift ;;
        --live)      LIVE_MODE="yes"; shift ;;
        --disk)
            # 这个选项现在只用于离线模式
            if [[ $DISK_OPTION_SET -ne 0 ]]; then ERROR "不能同时使用 --disk 和 --all-disks"; fi
            if [[ -n "$SPECIFIC_DISK" ]]; then ERROR "磁盘路径只能指定一次！"; fi
            SPECIFIC_DISK="$2"; DISK_OPTION_SET=1; shift 2 ;;
        --all-disks)
             # 这个选项现在只用于离线模式
             if [[ $DISK_OPTION_SET -ne 0 ]]; then ERROR "不能同时使用 --disk 和 --all-disks"; fi
            SPECIFIC_DISK=""; DISK_OPTION_SET=1; shift ;; # 保持用于代码可读性
        --force)     FORCE="yes"; shift ;;
        --disk-only) DISK_ONLY="yes"; shift ;;
        --no-quiesce) NO_QUIESCE="yes"; shift ;;
        -h|--help)   F_HELP; exit 0 ;;
        -v|--version) F_VERSION; exit 0 ;;
        --) shift; break ;;
        *) ERROR "内部错误：未知的 getopt 输出 '$1'" ;;
    esac
done

# --- 参数验证 ---
if [[ -z "$ACTION" ]]; then ERROR "必须指定一个操作！(-c|-r|-d|-l)"; fi
if [[ -z "$VM_NAME" ]]; then ERROR "必须使用 -n 或 --name 指定虚拟机名称！"; fi
if [[ "$ACTION" != "list" && -z "$SNAP_NAME" ]]; then ERROR "必须为操作 '${ACTION}' 指定快照名称！"; fi

# 验证模式特定选项
if [[ "$LIVE_MODE" == "no" ]]; then
    if [[ "$DISK_ONLY" == "yes" || "$NO_QUIESCE" == "yes" ]]; then
        WARN "选项 --disk-only 和 --no-quiesce 仅在 --live 模式下生效，将被忽略。"
    fi
    # 离线模式下 --disk 和 --all-disks 是可选的，不设置则默认 all
else # 在线模式
    if [[ -n "$SPECIFIC_DISK" || "$DISK_OPTION_SET" -ne 0 ]]; then
         WARN "选项 --disk 和 --all-disks 仅在离线模式下生效，将被忽略。在线模式始终处理所有相关磁盘。"
         # 重置，防止 F_CHECK 误判
         SPECIFIC_DISK=""
    fi
     if [[ "$ACTION" == "delete" ]]; then
         WARN "在线删除模式将执行 Block Commit 操作合并当前层，快照名称 '$SNAP_NAME' 仅作标识。"
     fi
fi


# --- 执行主逻辑 ---
F_MAIN

exit 0

