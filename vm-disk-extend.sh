#!/bin/bash
#############################################################################
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: Rocky Linux 9
# Updated By: Grok 3 (xAI)
# Update Date: 2025-04-16
# Version: 1.1.15
#############################################################################

# sh
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

# 脚本名称和版本
SCRIPT_NAME="${SH_NAME}"
VERSION="1.1.15"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 日志文件
LOG_FILE="/var/log/vm-disk-extend.log"

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
cleanup() {
    for file in "${TEMP_FILES[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file" && LOG "已清理临时文件: $file"
        fi
    done
}

trap cleanup EXIT INT TERM

# 检查 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        ERROR "此脚本需要 root 权限运行！请使用 sudo 或以 root 用户执行。"
    fi
}

# 检查依赖工具
check_dependencies() {
    local deps=("qemu-img" "virsh" "xmllint" "virt-resize" "guestfish" "bc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            ERROR "缺少依赖工具：${dep}。请安装后再运行。"
        fi
    done
}

# 显示帮助信息
F_HELP() {
    echo -e "
${GREEN}用途：${NC}管理KVM虚拟机的磁盘空间（扩展、检查等）
${GREEN}支持存储类型：${NC}
    * 本地文件（qcow2/raw）
    * 本地块设备（LVM/分区）
${RED}不支持的类型：${NC}
    * RBD/CEPH存储
    * iSCSI存储
    * 其他网络存储
${GREEN}依赖：${NC}
    * libguestfs-tools (包含virt-resize, guestfish等工具)
    * qemu-img
    * virsh
    * xmllint
    * bc
${GREEN}注意：${NC}
    * 必须在虚拟机关机状态下操作（-f 强制模式仅用于特殊场景）
    * 重要数据请提前备份，脚本会提示备份
    * 需要root权限执行
    * 分区命名支持 sdaX、vdaX、sdbX、vdbX 等（如 sda1、vdb2）
${GREEN}参数语法规范：${NC}
    无包围符号 ：-a                : 必选【选项】
               ：val               : 必选【参数值】
               ：val1 val2 -a -b   : 必选【选项或参数值】，且不分先后顺序
    []         ：[-a]              : 可选【选项】
               ：[val]             : 可选【参数值】
    <>         ：<val>             : 需替换的具体值（用户必须提供）
    %%         ：%val%             : 通配符（包含匹配，如%error%匹配error_code）
    |          ：val1|val2|<valn>  : 多选一
    {}         ：{-a <val>}        : 必须成组出现【选项+参数值】
               ：{val1 val2}       : 必须成组的【参数值组合】，且必须按顺序提供
${GREEN}用法：${NC}
    $0 -h|--help
    $0 -v|--version
    $0 -l|--list
    $0 -c|--check <虚拟机名称>
    $0 -e|--extend [-f|--force] [-q|--quiet] [-d|--dry-run] {<虚拟机名称> <目标分区> <扩展大小(GB)>}
${GREEN}参数说明：${NC}
    -h|--help       显示此帮助信息
    -v|--version    显示脚本版本
    -l|--list       列出所有KVM虚拟机
    -c|--check      检查虚拟机磁盘和分区信息
    -e|--extend     扩展虚拟机磁盘空间（必选用于扩容操作）
    -f|--force      强制在虚拟机运行时操作（仅扩展磁盘，需手动调整文件系统）
    -q|--quiet      安静模式，减少输出
    -d|--dry-run    试运行，只显示将要执行的操作
    <虚拟机名称>    KVM虚拟机名称
    <目标分区>      目标分区（如 vda1、vdb1、sda1、sdb2）
    <扩展大小(GB)>  扩展的磁盘空间大小（单位：GB）
${GREEN}使用示例：${NC}
    $0 -h                          # 显示帮助信息
    $0 -l                          # 列出所有虚拟机
    $0 -c vm1                      # 检查【vm1】的磁盘信息
    $0 -e vm1 vda1 10              # 扩展【vm1】的【vda1】分区【10GB】
    $0 -e vm1 vdb1 5               # 扩展【vm1】的【vdb1】分区【5GB】
    $0 -e -f vm1 sda1 20           # 强制扩展（运行时，仅扩展磁盘）
    $0 -e -d vm1 vdb1 5            # 试运行扩展，不实际执行
"
}

# 显示版本信息
F_VERSION() {
    echo -e "${GREEN}${SCRIPT_NAME} ${VERSION}${NC}"
}

# 列出所有KVM虚拟机
F_LIST_VMS() {
    LOG "可用KVM虚拟机列表："
    virsh list --all
}

# 获取虚拟机磁盘路径（支持多磁盘）
get_vm_disk_path() {
    local vm_name="$1"
    local target_part="$2"
    local disk_xml=""
    local disk_path=""

    # 获取磁盘配置XML
    local vm_xml
    vm_xml=$(virsh dumpxml "$vm_name" 2>/dev/null)
    if [ -z "$vm_xml" ]; then
        ERROR "无法获取虚拟机 ${vm_name} 的 XML 配置！"
    fi

    # 提取磁盘前缀（如 vdb）
    local disk_prefix=""
    if [[ "$target_part" =~ ^/dev/([a-z]+)[0-9]+$ ]]; then
        disk_prefix="${BASH_REMATCH[1]}"  # 如 vdb
    fi

    # 查找匹配的磁盘
    if [ -n "$disk_prefix" ]; then
        disk_xml=$(echo "$vm_xml" | xmllint --xpath "/domain/devices/disk[source and target[@dev='$disk_prefix']]/source" - 2>/dev/null)
    fi
    if [ -z "$disk_xml" ]; then
        # 回退到第一个磁盘
        disk_xml=$(echo "$vm_xml" | xmllint --xpath '/domain/devices/disk[@device="disk"][1]/source' - 2>/dev/null)
    fi
    if [ -z "$disk_xml" ]; then
        ERROR "虚拟机 ${vm_name} 的磁盘配置无效或无磁盘定义！"
    fi

    # 解析存储路径
    if [[ "$disk_xml" =~ file=\"([^\"]+)\" ]]; then
        disk_path="${BASH_REMATCH[1]}"
    elif [[ "$disk_xml" =~ dev=\"([^\"]+)\" ]]; then
        disk_path="${BASH_REMATCH[1]}"
    elif [[ "$disk_xml" =~ name=\"([^\"]+)\" ]]; then
        if [[ "$disk_xml" =~ protocol=\"rbd\" ]]; then
            local pool=$(virsh dumpxml "$vm_name" 2>/dev/null | xmllint --xpath 'string(/domain/devices/disk[@device="disk"][1]/source/@pool)' - 2>/dev/null)
            disk_path="rbd:${pool}/${BASH_REMATCH[1]}"
        elif [[ "$disk_xml" =~ protocol=\"iscsi\" ]]; then
            disk_path="iscsi:${BASH_REMATCH[1]}"
        else
            disk_path="net:${BASH_REMATCH[1]}"
        fi
    fi

    # 验证结果
    if [ -z "$disk_path" ]; then
        disk_path=$(virsh domblklist "$vm_name" --details | awk '
            $2=="disk" && $3!="cdrom" && $4!~"\.iso$" && $4!~"^$" {print $4; exit}
        ')
        disk_path=$(echo "$disk_path" | xargs)
    fi

    if [ -z "$disk_path" ]; then
        ERROR "无法获取虚拟机 ${vm_name} 的磁盘路径！"
    fi

    if [[ "$disk_path" =~ ^(rbd:|iscsi:|net:) ]]; then
        ERROR "不支持的网络存储类型: ${disk_path}"
    fi

    if [ ! -e "$disk_path" ]; then
        ERROR "磁盘路径不存在: ${disk_path}"
    fi

    if [ ! -w "$disk_path" ]; then
        ERROR "磁盘路径不可写: ${disk_path}"
    fi

    echo "$disk_path"
}

# 检查虚拟机磁盘信息
F_CHECK_DISK() {
    local vm_name="$1"

    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
    fi

    LOG "虚拟机 ${vm_name} 磁盘信息："
    virsh domblklist "$vm_name"

    LOG "磁盘详细信息："
    local vm_xml=$(virsh dumpxml "$vm_name" 2>/dev/null)
    local disk_nodes=$(echo "$vm_xml" | xmllint --xpath "/domain/devices/disk[@device='disk']/source" - 2>/dev/null)
    local i=1
    while IFS= read -r disk_xml; do
        local disk_path=""
        if [[ "$disk_xml" =~ file=\"([^\"]+)\" ]]; then
            disk_path="${BASH_REMATCH[1]}"
        elif [[ "$disk_xml" =~ dev=\"([^\"]+)\" ]]; then
            disk_path="${BASH_REMATCH[1]}"
        fi
        if [ -n "$disk_path" ]; then
            LOG "磁盘 ${i}: ${disk_path}"
            qemu-img info "$disk_path"
            LOG "分区信息："
            guestfish --ro -a "$disk_path" run : list-filesystems
            LOG "开始磁盘健康检查..."
            if qemu-img check "$disk_path" | grep -q "No errors"; then
                LOG "磁盘健康状态: 正常"
            else
                WARN "磁盘健康检查发现问题："
                qemu-img check "$disk_path"
            fi
            ((i++))
        fi
    done <<< "$disk_nodes"
    LOG "=============================================="
}

# 获取虚拟机内文件系统信息
get_vm_fs_info() {
    local disk_path="$1"
    local target_part="$2"
    local fs_type=""

    # 提取分区号（如 vdb1 -> 1）
    local part_num="${target_part##*[a-z]}"
    # 固定使用 sdaX
    local virt_part="/dev/sda${part_num}"

    # 使用 guestfish 获取文件系统类型
    fs_type=$(guestfish --ro -a "$disk_path" <<EOF 2>/dev/null
        run
        blkid $virt_part
EOF
    )
    fs_type=$(echo "$fs_type" | grep -E "^TYPE:" | cut -d' ' -f2- | tr -d '"')
    if [ -z "$fs_type" ]; then
        fs_type="unknown"
    fi

    echo "$fs_type"
}

# 获取挂载点
get_mount_point() {
    local disk_path="$1"
    local target_part="$2"
    local mount_point=""
    local part_num="${target_part##*[a-z]}"  # 提取分区号，如 1
    local virt_part="/dev/sda${part_num}"
    local disk_prefix="${target_part#/dev/}"
    disk_prefix="${disk_prefix%%[0-9]*}"  # 如 vda, vdb

    # 获取 UUID
    local uuid=$(guestfish --ro -a "$disk_path" <<EOF 2>/dev/null
        run
        blkid $virt_part | grep UUID
EOF
    )
    uuid=$(echo "$uuid" | grep -E "^UUID:" | cut -d' ' -f2- | tr -d '"')

    # 获取文件系统类型
    local fs_type=$(guestfish --ro -a "$disk_path" <<EOF 2>/dev/null
        run
        blkid $virt_part | grep TYPE
EOF
    )
    fs_type=$(echo "$fs_type" | grep -E "^TYPE:" | cut -d' ' -f2- | tr -d '"')

    # 如果是 swap，分区无挂载点
    if [ "$fs_type" = "swap" ]; then
        echo ""
        return
    fi

    # 查找根分区（优先 xfs，其次 ext4）
    local fs_list=$(guestfish --ro -a "$disk_path" run : list-filesystems)
    local root_part=""
    if echo "$fs_list" | grep -q "/dev/sda[0-9]*:xfs"; then
        root_part=$(echo "$fs_list" | grep ":xfs" | head -1 | cut -d' ' -f1)
    elif echo "$fs_list" | grep -q "/dev/sda[0-9]*:ext[234]"; then
        root_part=$(echo "$fs_list" | grep ":ext[234]" | head -1 | cut -d' ' -f1)
    fi

    if [ -n "$root_part" ]; then
        mount_point=$(guestfish --ro -a "$disk_path" <<EOF 2>/dev/null
            run
            mount-ro $root_part /
            cat /etc/fstab | grep -E "$uuid|/dev/${disk_prefix}${part_num}"
EOF
        )
        mount_point=$(echo "$mount_point" | awk '{print $2}' | head -1)
    fi

    # 如果未找到，尝试其他分区
    if [ -z "$mount_point" ] && [ -n "$fs_list" ]; then
        local part
        while IFS= read -r part; do
            part=${part%%:*}
            if [ "$part" != "$root_part" ] && [ "$part" != "$virt_part" ]; then
                mount_point=$(guestfish --ro -a "$disk_path" <<EOF 2>/dev/null
                    run
                    mount-ro $part /
                    cat /etc/fstab | grep -E "$uuid|/dev/${disk_prefix}${part_num}"
EOF
                )
                mount_point=$(echo "$mount_point" | awk '{print $2}' | head -1)
                [ -n "$mount_point" ] && break
            fi
        done <<< "$fs_list"
    fi

    echo "$mount_point"
}

# 单位转换函数
human_size() {
    local bytes=$1
    if command -v bc &>/dev/null; then
        if (( bytes >= 1125899906842624 )); then
            echo "$(echo "scale=1; $bytes / (1024^5)" | bc | awk '{printf "%.1fPiB", $1}')"
        elif (( bytes >= 1099511627776 )); then
            echo "$(echo "scale=1; $bytes / (1024^4)" | bc | awk '{printf "%.1fTiB", $1}')"
        else
            echo "$(echo "scale=1; $bytes / (1024^3)" | bc | awk '{printf "%.1fGiB", $1}')"
        fi
    else
        if (( bytes >= 1125899906842624 )); then
            echo "$(( bytes / 1024 / 1024 / 1024 / 1024 / 1024 ))PiB"
        elif (( bytes >= 1099511627776 )); then
            echo "$(( bytes / 1024 / 1024 / 1024 / 1024 ))TiB"
        else
            echo "$(( bytes / 1024 / 1024 / 1024 ))GiB"
        fi
        WARN "未找到 bc 命令，已切换为整数计算"
    fi
}

# 扩展虚拟机磁盘
F_EXPAND_DISK() {
    local vm_name="$1"
    local target_part="$2"
    local add_size_gb="$3"
    local force="$4"
    local quiet="$5"
    local dry_run="$6"

    # 验证参数
    if ! [[ "$add_size_gb" =~ ^[0-9]+$ ]] || [ "$add_size_gb" -eq 0 ]; then
        ERROR "扩展大小必须是正整数（单位：GB）！"
    fi

    # 规范化分区名
    if ! [[ "$target_part" =~ ^[sv]d[a-z][0-9]+$ ]]; then
        ERROR "分区格式不正确，请使用 sd[a-z]X 或 vd[a-z]X 格式（如 vda1、vdb2）！"
    fi
    target_part="/dev/$target_part"

    # 检查虚拟机是否存在
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
    fi

    # 获取磁盘路径
    local disk_path=$(get_vm_disk_path "$vm_name" "$target_part")

    # 验证分区存在性
    local part_list=$(guestfish --ro -a "$disk_path" run : list-filesystems | grep -E "/dev/[sv]d[a-z][0-9]+")
    local part_num="${target_part##*[a-z]}"  # 提取分区号，如 1
    if ! echo "$part_list" | grep -q "[sv]d[a-z]${part_num}"; then
        WARN "可用分区：\n$part_list"
        ERROR "分区 ${target_part} 不存在于磁盘 ${disk_path}！"
    fi

    # 检查虚拟机状态
    local vm_state=$(virsh domstate "$vm_name")
    if [ "$vm_state" != "shut off" ] && [ "$force" != "yes" ]; then
        ERROR "虚拟机 ${vm_name} 正在运行，请先关闭虚拟机或使用 -f 强制操作（仅扩展磁盘）！"
    fi

    # 获取当前磁盘和分区大小
    local disk_format=$(qemu-img info "$disk_path" | awk '/format:/ {print $3}')
    local disk_size_bytes=$(qemu-img info "$disk_path" | awk -F'[ ()]' '/virtual size/ {print $6}')
    local disk_size_gb=$(( disk_size_bytes / 1024 / 1024 / 1024 ))  # 整数 GB
    local target_disk_size_gb=$(( disk_size_gb + add_size_gb ))      # 目标磁盘大小
    local current_size_bytes=""
    local current_size_gb=""
    local new_size_gb=""
    local part_size_bytes=""
    local part_size_gb=""
    local fs_type=$(get_vm_fs_info "$disk_path" "$target_part")

    # 获取分区大小
    local virt_part="/dev/sda${part_num}"
    if [ "$fs_type" = "swap" ]; then
        part_size_bytes=$(guestfish --ro -a "$disk_path" <<EOF 2>/dev/null
            run
            part-list /dev/sda
EOF
        )
        part_size_bytes=$(echo "$part_size_bytes" | awk -v pn="$part_num" '
            $1 == "part_num:" && $2 == pn {p=1}
            p && $1 == "part_size:" {print $2; p=0}
        ')
    else
        part_size_bytes=$(guestfish --ro -a "$disk_path" <<EOF 2>/dev/null
            run
            blockdev-getsize64 $virt_part
EOF
        )
    fi
    if [ -n "$part_size_bytes" ]; then
        part_size_gb=$(echo "scale=1; $part_size_bytes / 1024 / 1024 / 1024" | bc | awk '{printf "%.0f", $1}')
        current_size_gb=$part_size_gb
        new_size_gb=$(( current_size_gb + add_size_gb ))  # 分区新大小，仅用于显示
    else
        WARN "无法获取分区 ${target_part} 的大小，使用磁盘总大小 ${disk_size_gb}GB"
        current_size_gb=$disk_size_gb
        new_size_gb=$(( current_size_gb + add_size_gb ))
    fi

    # 检查临时磁盘空间
    local required_space=$(( target_disk_size_gb * 1024 * 1024 * 1024 ))
    local available_space=$(df --output=avail -B1 "$(dirname "$disk_path")" | tail -1)
    if [ "$available_space" -lt "$required_space" ]; then
        ERROR "磁盘空间不足！需要 ${target_disk_size_gb}GB，当前可用 $(human_size $available_space)。"
    fi

    # 备份提示
    if [ "$quiet" != "yes" ] && [ "$dry_run" != "yes" ]; then
        WARN "警告：扩容操作可能导致数据丢失，请确认已备份磁盘：${disk_path}"
        read -p "是否已完成备份？(y/N): " backup_confirm
        if [[ ! "$backup_confirm" =~ ^[Yy] ]]; then
            ERROR "请先备份数据后重试！"
        fi
    fi

    # 显示操作信息
    if [ "$quiet" != "yes" ]; then
        LOG "=============================================="
        LOG "操作摘要："
        LOG "虚拟机名称:      ${vm_name}"
        LOG "磁盘文件:        ${disk_path}"
        LOG "磁盘格式:        ${disk_format:-未知}"
        LOG "当前分区大小:    ${current_size_gb}G"
        LOG "目标分区:        ${target_part}"
        LOG "扩展大小:        +${add_size_gb}G"
        LOG "新分区大小:      ${new_size_gb}G"
        LOG "虚拟机状态:      ${vm_state}"
        LOG "=============================================="

        if [ "$dry_run" == "yes" ]; then
            WARN "[试运行] 将执行以下操作："
            LOG "1. 扩展磁盘文件: qemu-img resize \"${disk_path}\" \"+${add_size_gb}G\""
            local resize_part="/dev/sda${part_num}"
            LOG "2. 调整分区表: virt-resize --expand \"${resize_part}\" \"${disk_path}\" \"${disk_path}.resized\""
            LOG "3. 检测文件系统..."
            local fs_type=$(get_vm_fs_info "$disk_path" "$target_part")
            local mount_point=$(get_mount_point "$disk_path" "$target_part")
            if [ -z "$fs_type" ] || [ "$fs_type" = "unknown" ]; then
                LOG "   无法检测文件系统类型，将提示手动调整"
            else
                LOG "   检测到文件系统: ${fs_type}"
                case "$fs_type" in
                    ext[234])
                        LOG "   将执行: virt-resize 自动扩展 ext${fs_type##ext} 文件系统"
                        ;;
                    xfs)
                        LOG "   将执行: virt-resize 自动扩展 XFS 文件系统"
                        ;;
                    swap)
                        LOG "   SWAP 分区无需调整文件系统"
                        ;;
                    *)
                        LOG "   不支持的文件系统类型: ${fs_type}，将提示手动调整"
                        ;;
                esac
            fi
            LOG "4. 启动虚拟机: virsh start ${vm_name}"
            LOG "=============================================="
            exit 0
        fi

        read -p "确认以上信息是否正确？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            WARN "操作已取消。"
            exit 0
        fi
    fi

    # 1. 扩展磁盘文件
    LOG "[1/3] 正在扩展磁盘文件..."
    if ! qemu-img resize "$disk_path" "+${add_size_gb}G"; then
        ERROR "磁盘扩展失败！"
    fi
    local new_disk_size_bytes=$(qemu-img info "$disk_path" | awk -F'[ ()]' '/virtual size/ {print $6}')
    if [ -z "$new_disk_size_bytes" ]; then
        ERROR "无法获取新磁盘大小，扩展可能失败！"
    fi
    if [ "$new_disk_size_bytes" -le "$disk_size_bytes" ]; then
        ERROR "磁盘大小未增加，扩展可能失败！"
    fi

    if [ "$force" == "yes" ] && [ "$vm_state" != "shut off" ]; then
        LOG "虚拟机运行中，仅扩展磁盘大小，请手动调整分区和文件系统。"
        LOG "建议执行以下步骤："
        LOG "  1. 通知内核重新扫描：echo '1' > /sys/block/${target_part#/dev/}/device/rescan"
        LOG "  2. 调整分区表（使用 fdisk/parted）"
        LOG "  3. 扩展文件系统（xfs_growfs/resize2fs）"
        exit 0
    fi

    # 2. 调整分区表
    LOG "[2/3] 正在调整分区表..."
    local temp_disk="${disk_path}.resized"
    TEMP_FILES+=("$temp_disk")

    # 创建临时磁盘
    if ! qemu-img create -f "$disk_format" "$temp_disk" "${target_disk_size_gb}G"; then
        ERROR "创建临时磁盘失败！"
    fi

    # 使用 sdaX 作为 resize_part
    local resize_part="/dev/sda${part_num}"

    if ! virt-resize --expand "$resize_part" "$disk_path" "$temp_disk"; then
        ERROR "分区调整失败！"
    fi

    # 替换原磁盘文件
    if ! mv "$temp_disk" "$disk_path"; then
        ERROR "替换磁盘文件失败！"
    fi
    TEMP_FILES=()

    # 3. 调整文件系统
    LOG "[3/3] 正在检测文件系统..."
    local fs_type=$(get_vm_fs_info "$disk_path" "$target_part")
    local mount_point=$(get_mount_point "$disk_path" "$target_part")
    local resize_part="/dev/sda${part_num}"

    if [ -z "$fs_type" ] || [ "$fs_type" = "unknown" ]; then
        WARN "无法检测文件系统类型！"
        WARN "请启动虚拟机后手动调整文件系统："
        WARN "  - ext2/3/4: resize2fs $target_part"
        WARN "  - XFS: xfs_growfs <挂载点>"
        LOG "磁盘和分区已扩展，请启动虚拟机：virsh start $vm_name"
        exit 0
    fi

    LOG "检测到文件系统: ${fs_type}"
    case "$fs_type" in
        ext[234])
            LOG "ext${fs_type##ext} 文件系统已由 virt-resize 扩展，无需手动调整。"
            ;;
        xfs)
            LOG "XFS 文件系统已由 virt-resize 扩展，无需手动调整。"
            ;;
        swap)
            LOG "SWAP 分区无需调整文件系统。"
            ;;
        *)
            WARN "不支持的文件系统类型: ${fs_type}"
            WARN "请手动调整文件系统。"
            ;;
    esac

    LOG "磁盘和分区已扩展，请启动虚拟机：virsh start $vm_name"
    LOG "=============================================="
    LOG "操作成功完成！"
    LOG "虚拟机:        ${vm_name}"
    LOG "分区:          ${target_part}"
    LOG "扩展大小:      +${add_size_gb}G"
    LOG "新分区大小:    ${new_size_gb}G"
    LOG "=============================================="
}

# 主程序
main() {
    check_root
    check_dependencies

    # 确保日志文件可写
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/vm-disk-extend.log"

    # 参数处理
    local action=""
    local vm_name=""
    local target_part=""
    local add_size_gb=""
    local force="no"
    QUIET="no"
    local dry_run="no"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                F_HELP
                exit 0
                ;;
            -v|--version)
                F_VERSION
                exit 0
                ;;
            -l|--list)
                F_LIST_VMS
                exit 0
                ;;
            -c|--check)
                action="check"
                vm_name="$2"
                shift
                ;;
            -e|--extend)
                action="extend"
                ;;
            -f|--force)
                force="yes"
                ;;
            -q|--quiet)
                QUIET="yes"
                ;;
            -d|--dry-run)
                dry_run="yes"
                ;;
            *)
                if [ "$action" = "extend" ]; then
                    if [ -z "$vm_name" ]; then
                        vm_name="$1"
                    elif [ -z "$target_part" ]; then
                        target_part="$1"
                    elif [ -z "$add_size_gb" ]; then
                        add_size_gb="$1"
                    else
                        ERROR "未知参数或参数过多：$1"
                        F_HELP
                        exit 1
                    fi
                else
                    ERROR "未知参数：$1"
                    F_HELP
                    exit 1
                fi
                ;;
        esac
        shift
    done

    # 检查操作类型
    if [ -z "$action" ]; then
        ERROR "请指定操作类型（如 -e|--extend 或 -c|--check）！"
        F_HELP
        exit 1
    fi

    # 执行相应操作
    case "$action" in
        check)
            if [ -z "$vm_name" ]; then
                ERROR "请提供虚拟机名称！"
            fi
            F_CHECK_DISK "$vm_name"
            ;;
        extend)
            if [ -z "$vm_name" ] || [ -z "$target_part" ] || [ -z "$add_size_gb" ]; then
                ERROR "缺少必要参数！需要提供虚拟机名称、目标分区和扩展大小。"
                F_HELP
                exit 1
            fi
            F_EXPAND_DISK "$vm_name" "$target_part" "$add_size_gb" "$force" "$QUIET" "$dry_run"
            ;;
        *)
            ERROR "未知操作类型！"
            F_HELP
            exit 1
            ;;
    esac
}

# 执行主程序
main "$@"

