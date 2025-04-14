#!/bin/bash
#############################################################################
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: Rocky Linux 9
# Updated By: Grok 3 (xAI)
# Update Date: 2025-04-14
#############################################################################

# sh
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

# 脚本名称和版本
SCRIPT_NAME="${SH_NAME}"
VERSION="1.1.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 临时文件列表
TEMP_FILES=()

# 引入环境变量
if [ -f "${SH_PATH}/env.sh" ]; then
    source "${SH_PATH}/env.sh"
fi

# 日志函数
LOG() {
    if [ "$QUIET" != "yes" ]; then
        echo -e "${GREEN}[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*${NC}"
    fi
}

ERROR() {
    echo -e "${RED}[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*${NC}" >&2
    exit 1
}

WARN() {
    if [ "$QUIET" != "yes" ]; then
        echo -e "${YELLOW}[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*${NC}"
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
    * libguestfs-tools (包含virt-resize, virt-filesystems等工具)
    * qemu-img
    * virsh
    * xmllint
${GREEN}注意：${NC}
    * 必须在虚拟机关机状态下操作（-f 强制模式仅用于特殊场景）
    * 重要数据请提前备份，脚本会提示备份
    * 需要root权限执行
    * 分区命名支持 /dev/sdaX 或 /dev/vdaX
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
${GREEN}使用示例：${NC}
    $0 -h                          # 显示帮助信息
    $0 -l                          # 列出所有虚拟机
    $0 -c vm1                      # 检查【vm1】的磁盘信息
    $0 -e vm1 /dev/vda2 10         # 扩展【vm1】的【/dev/vda2】分区【10GB】
    $0 -e -f vm1 /dev/sda1 20      # 强制扩展（运行时，仅扩展磁盘）
    $0 -e -d vm1 /dev/vda1 5       # 试运行扩展，不实际执行
"
}

# 获取虚拟机系统磁盘路径（支持所有存储类型）
get_vm_disk_path() {
    local vm_name="$1"
    local disk_xml=""
    local disk_path=""

    # 获取磁盘配置XML片段
    disk_xml=$(virsh dumpxml "$vm_name" 2>/dev/null | xmllint --xpath '/domain/devices/disk[@device="disk"][1]/source' - 2>/dev/null)

    # 解析不同类型存储
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

    # 备用方案
    if [ -z "$disk_path" ]; then
        disk_path=$(virsh domblklist "$vm_name" --details | awk '
            $2=="disk" && $3!="cdrom" && $4!~"\.iso$" && $4!~"^$" {print $4; exit}
        ')
        disk_path=$(echo "$disk_path" | xargs)
    fi

    # 验证结果
    if [ -z "$disk_path" ]; then
        ERROR "无法获取虚拟机 ${vm_name} 的系统磁盘路径！"
    fi

    if [[ "$disk_path" =~ ^(rbd:|iscsi:|net:) ]]; then
        ERROR "不支持的网络存储类型: ${disk_path}"
    fi

    if [ ! -e "$disk_path" ]; then
        ERROR "磁盘路径不存在: ${disk_path}"
    fi

    # 检查是否可写
    if [ ! -w "$disk_path" ]; then
        ERROR "磁盘路径不可写: ${disk_path}"
    fi

    echo "$disk_path"
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

# 检查虚拟机磁盘信息
F_CHECK_DISK() {
    local vm_name="$1"

    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
    fi

    LOG "虚拟机 ${vm_name} 磁盘信息："
    virsh domblklist "$vm_name"

    LOG "磁盘详细信息："
    local disk_path=$(get_vm_disk_path "$vm_name")
    LOG "检测到磁盘路径: ${disk_path}"
    qemu-img info "$disk_path"

    LOG "分区信息："
    virt-filesystems -a "$disk_path" --long -h

    LOG "开始磁盘健康检查..."
    if qemu-img check "$disk_path" | grep -q "No errors found"; then
        LOG "磁盘健康状态: ${GREEN}正常${NC}"
    else
        WARN "磁盘健康检查发现问题："
        qemu-img check "$disk_path"
    fi
    LOG "=============================================="
}

# 获取虚拟机内文件系统信息
get_vm_fs_info() {
    local disk_path="$1"
    local target_part="$2"
    local fs_type=""
    local mount_point=""

    # 规范化分区名（适配 vda/sda）
    local part_name="${target_part##*/}"  # 提取 sda1 或 vda1
    local disk_prefix=$(echo "$target_part" | grep -oE '/dev/[a-z]+')  # 提取 /dev/sda 或 /dev/vda

    # virt-filesystems 使用 sda 命名，替换 vda 为 sda
    if [[ "$target_part" =~ /dev/vda ]]; then
        target_part="${target_part/vda/sda}"
    fi

    # 使用 virt-filesystems 获取精确信息
    local fs_info=$(virt-filesystems -a "$disk_path" --long -h | grep -E "[[:space:]]${part_name}[[:space:]]")

    if [ -n "$fs_info" ]; then
        fs_type=$(echo "$fs_info" | awk '{print $2}')
        mount_point=$(echo "$fs_info" | awk '{print $NF}' | grep -E '^/|^-' | head -1)
        [ "$mount_point" == "-" ] && mount_point=""
    fi

    # 备用方案：使用 blkid
    if [ -z "$fs_type" ]; then
        fs_type=$(guestfish --ro -a "$disk_path" run : blkid "$target_part" : get TYPE 2>/dev/null)
    fi

    echo "$fs_type $mount_point"
}

# 单位转换函数
human_size() {
    local bytes=$1
    if command -v bc &>/dev/null; then
        if (( bytes >= 1125899906842624 )); then  # 1PB = 1024^5
            echo "$(echo "scale=1; $bytes / (1024^5)" | bc | awk '{printf "%.1fPiB", $1}')"
        elif (( bytes >= 1099511627776 )); then  # 1TB = 1024^4
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

    if ! [[ "$target_part" =~ ^/dev/[sv]da[0-9]+$ ]]; then
        ERROR "分区格式不正确，请使用 /dev/sdaX 或 /dev/vdaX 格式！"
    fi

    # 检查虚拟机是否存在
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
    fi

    # 获取磁盘路径
    local disk_path=$(get_vm_disk_path "$vm_name")

    # 检查虚拟机状态
    local vm_state=$(virsh domstate "$vm_name")
    if [ "$vm_state" != "shut off" ] && [ "$force" != "yes" ]; then
        ERROR "虚拟机 ${vm_name} 正在运行，请先关闭虚拟机或使用 -f 强制操作（仅扩展磁盘）！"
    fi

    # 获取当前磁盘大小
    local disk_format=$(qemu-img info "$disk_path" | awk '/format:/ {print $3}')
    local current_size_bytes=$(qemu-img info "$disk_path" | awk -F'[ ()]' '/virtual size/ {print $6}')
    local current_size_gb=$(echo "scale=1; $current_size_bytes / (1024^3)" | bc)
    local new_size_gb=$(echo "$current_size_gb + $add_size_gb" | bc)

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
        LOG "当前磁盘大小:    ${current_size_gb}G"
        LOG "目标分区:        ${target_part}"
        LOG "扩展大小:        +${add_size_gb}G"
        LOG "新磁盘大小:      ${new_size_gb}G"
        LOG "虚拟机状态:      ${vm_state}"
        LOG "=============================================="

        if [ "$dry_run" == "yes" ]; then
            WARN "[试运行] 将执行以下操作："
            LOG "1. 扩展磁盘文件: qemu-img resize \"${disk_path}\" \"+${add_size_gb}G\""
            LOG "2. 调整分区表: virt-resize --expand \"${target_part}\" \"${disk_path}\" \"${disk_path}.resized\""
            LOG "3. 启动虚拟机并调整文件系统（视情况手动执行）"
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

    if [ "$force" == "yes" ] && [ "$vm_state" != "shut off" ]; then
        LOG "虚拟机运行中，仅扩展磁盘大小，请手动调整分区和文件系统。"
        LOG "建议执行以下步骤："
        LOG "  1. 通知内核重新扫描：echo '1' > /sys/block/vda/device/rescan"
        LOG "  2. 调整分区表（使用 fdisk/parted）"
        LOG "  3. 扩展文件系统（xfs_growfs/resize2fs）"
        exit 0
    fi

    # 2. 调整分区表
    LOG "[2/3] 正在调整分区表..."
    local temp_disk="${disk_path}.resized"
    TEMP_FILES+=("$temp_disk")

    # 创建临时磁盘
    if ! qemu-img create -f "$disk_format" "$temp_disk" "${new_size_gb}G"; then
        ERROR "创建临时磁盘失败！"
    fi

    # 规范化分区名（virt-resize 使用 sda）
    local resize_part="$target_part"
    if [[ "$resize_part" =~ /dev/vda ]]; then
        resize_part="${resize_part/vda/sda}"
    fi

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
    read fs_type mount_point <<< $(get_vm_fs_info "$disk_path" "$target_part")

    if [ -z "$fs_type" ]; then
        WARN "无法检测文件系统类型！"
        WARN "请启动虚拟机后手动调整文件系统："
        WARN "  - ext2/3/4: resize2fs $target_part"
        WARN "  - XFS: xfs_growfs ${mount_point:-/}"
        LOG "磁盘和分区已扩展，请启动虚拟机：virsh start $vm_name"
        exit 0
    fi

    LOG "检测到文件系统: ${fs_type}，挂载点: ${mount_point:-未挂载}"
    case "$fs_type" in
        ext[234])
            WARN "ext 文件系统需在虚拟机内调整，请启动虚拟机后执行："
            WARN "  resize2fs $target_part"
            ;;
        xfs)
            WARN "XFS 文件系统需在虚拟机内调整，请启动虚拟机后执行："
            WARN "  xfs_growfs ${mount_point:-/}"
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
    LOG "新磁盘大小:    ${new_size_gb}G"
    LOG "=============================================="
}

# 主程序
main() {
    check_root

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
                ;;
        esac
        shift
    done

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
            ERROR "请指定操作类型（如 -e|--extend 或 -c|--check）！"
            F_HELP
            exit 1
            ;;
    esac
}

# 执行主程序
main "$@"

