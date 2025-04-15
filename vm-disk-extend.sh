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
VERSION="1.1.4"  # 更新版本号以反映分区名简化

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
    * 目标分区指定为 vda1、vdb1 等，脚本自动推断设备（如 vda、vdb）
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
    <目标分区>      目标分区（如 vda1、vdb1）
    <扩展大小(GB)>  扩展的磁盘空间大小（单位：GB）
${GREEN}使用示例：${NC}
    $0 -h                          # 显示帮助信息
    $0 -l                          # 列出所有虚拟机
    $0 -c vm1                      # 检查【vm1】的磁盘信息
    $0 -e vm1 vda2 10              # 扩展【vm1】的【/dev/vda2】分区【10GB】
    $0 -e vm1 vdb1 10              # 扩展【vm1】的【/dev/vdb1】分区【10GB】
    $0 -e -f vm1 vda1 20           # 强制扩展（运行时，仅扩展磁盘）
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

# 获取虚拟机磁盘路径
get_vm_disk_path() {
    local vm_name="$1"
    local target_part="$2"  # 分区，如 vdb1
    local device=""
    local disk_path=""

    # 解析分区名
    if [[ "$target_part" =~ ^(vd[a-z])([0-9]+)$ ]]; then
        device="${BASH_REMATCH[1]}"  # 提取 vdb
    else
        ERROR "分区名无效！请使用 vda1、vdb1 等格式。"
    fi

    # 获取虚拟机 XML
    local xml
    xml=$(virsh dumpxml "$vm_name" 2>/dev/null)
    if [ -z "$xml" ]; then
        ERROR "无法获取虚拟机 ${vm_name} 的配置信息！"
    fi

    # 提取设备名的磁盘路径
    disk_path=$(echo "$xml" | xmllint --xpath "string(/domain/devices/disk[@device='disk']/source[@file][../target/@dev='$device']/@file)" - 2>/dev/null)
    if [ -z "$disk_path" ]; then
        ERROR "虚拟机 ${vm_name} 中未找到设备 ${device} 的磁盘文件！请检查分区名（可通过 virsh domblklist 查看）。"
    fi

    # 验证磁盘文件
    if [ ! -f "$disk_path" ]; then
        ERROR "磁盘文件 ${disk_path} 不存在！"
    fi
    if ! qemu-img info "$disk_path" | grep -q "format: qcow2"; then
        ERROR "磁盘 ${disk_path} 不是 qcow2 格式！"
    fi

    echo "$disk_path"
}

# 检查虚拟机磁盘和分区信息
F_CHECK_DISK() {
    local vm_name="$1"
    check_root
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
    fi

    LOG "正在检查虚拟机 ${vm_name} 的磁盘信息..."
    local disk_path=$(get_vm_disk_path "$vm_name" "vda1")
    LOG "主磁盘文件（vda）: ${disk_path}"

    LOG "分区信息："
    virt-filesystems --long --parts --blkdevs -a "$disk_path" 2>/dev/null || ERROR "无法获取分区信息！"
}

# 扩展虚拟机磁盘
F_EXPAND_DISK() {
    local vm_name="$1"
    local target_part="$2" # 分区，如 vdb1
    local add_size_gb="$3"
    local force="$4"
    local quiet="$5"
    local dry_run="$6"

    # 验证虚拟机是否存在
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
    fi

    # 解析设备名
    local device=""
    if [[ "$target_part" =~ ^(vd[a-z])[0-9]+$ ]]; then
        device="${BASH_REMATCH[1]}"  # 提取 vdb
    else
        ERROR "分区名无效！请使用 vda1、vdb1 等格式。"
    fi

    # 获取磁盘路径
    local disk_path=$(get_vm_disk_path "$vm_name" "$target_part")
    local disk_format=$(qemu-img info "$disk_path" | grep "file format" | awk '{print $3}')

    # 验证分区存在
    if [ "$dry_run" != "yes" ] && ! virt-filesystems --parts -a "$disk_path" | grep -q "$target_part"; then
        ERROR "磁盘 ${disk_path} 中未找到分区 ${target_part}！"
    fi

    # 验证扩展大小
    if ! [[ "$add_size_gb" =~ ^[0-9]+$ ]] || [ "$add_size_gb" -eq 0 ]; then
        ERROR "扩展大小必须是正整数（单位：GB）！"
    fi

    # 检查虚拟机状态
    local vm_state=$(virsh domstate "$vm_name")
    if [ "$vm_state" != "shut off" ] && [ "$force" != "yes" ]; then
        ERROR "虚拟机 ${vm_name} 正在运行，请先关闭或使用 -f 强制扩展！"
    fi

    # 规范化分区名用于显示
    local display_part="/dev/$target_part"

    # 显示操作信息
    if [ "$quiet" != "yes" ]; then
        LOG "=============================================="
        LOG "操作摘要："
        LOG "虚拟机名称:      ${vm_name}"
        LOG "磁盘文件:        ${disk_path}"
        LOG "目标分区:        ${display_part}"
        LOG "扩展大小:        ${add_size_gb}GB"
        LOG "虚拟机状态:      ${vm_state}"
        LOG "强制模式:        ${force}"
        LOG "=============================================="

        if [ "$dry_run" = "yes" ]; then
            WARN "[试运行] 以下操作不会实际执行"
        else
            WARN "警告：操作可能影响虚拟机，请确认已备份重要数据！"
            read -p "是否继续？(y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy] ]]; then
                WARN "操作已取消。"
                exit 0
            fi
        fi
    fi

    # 1. 扩展磁盘
    local new_size_gb=$(( $(qemu-img info "$disk_path" | grep "virtual size" | awk '{print $3}' | tr -d 'G') + add_size_gb ))
    if [ "$dry_run" = "yes" ]; then
        LOG "[试运行] 将扩展磁盘: qemu-img resize \"$disk_path\" ${new_size_gb}G"
    else
        LOG "[1/3] 正在扩展磁盘..."
        if ! qemu-img resize "$disk_path" "${new_size_gb}G"; then
            ERROR "扩展磁盘失败！"
        fi
    fi

    # 2. 调整分区表
    if [ "$force" = "yes" ] && [ "$vm_state" != "shut off" ]; then
        LOG "强制模式：仅扩展磁盘，需手动调整分区表和文件系统。"
        return
    fi

    LOG "[2/3] 正在调整分区表..."
    local temp_disk="${disk_path}.resized"
    TEMP_FILES+=("$temp_disk")

    # 创建临时磁盘
    if [ "$dry_run" = "yes" ]; then
        LOG "[试运行] 将创建临时磁盘: qemu-img create -f \"$disk_format\" \"$temp_disk\" ${new_size_gb}G"
    else
        if ! qemu-img create -f "$disk_format" "$temp_disk" "${new_size_gb}G"; then
            ERROR "创建临时磁盘失败！"
        fi
    fi

    # 规范化分区名（virt-resize 使用 sda）
    local resize_part="/dev/sda${target_part#vd[a-z]}"

    # 执行 virt-resize
    if [ "$dry_run" = "yes" ]; then
        LOG "[试运行] 将调整分区: virt-resize --expand \"$resize_part\" \"$disk_path\" \"$temp_disk\""
    else
        local virt_resize_output
        if ! virt_resize_output=$(virt-resize --expand "$resize_part" "$disk_path" "$temp_disk" 2>&1); then
            ERROR "分区调整失败！错误信息：\n$virt_resize_output"
        fi
    fi

    # 验证临时磁盘
    if [ "$dry_run" != "yes" ] && [ ! -s "$temp_disk" ]; then
        ERROR "临时磁盘 $temp_disk 为空或无效，无法继续！"
    fi

    # 3. 替换原磁盘
    if [ "$dry_run" = "yes" ]; then
        LOG "[试运行] 将替换磁盘: mv \"$temp_disk\" \"$disk_path\""
    else
        LOG "[3/3] 正在替换原磁盘文件..."
        if ! mv "$temp_disk" "$disk_path"; then
            ERROR "替换磁盘文件失败！"
        fi
        TEMP_FILES=()
    fi

    # 提示用户扩展文件系统
    if [ "$dry_run" != "yes" ]; then
        LOG "磁盘扩容完成，请启动虚拟机并登录执行以下命令扩展文件系统："
        if virt-filesystems --long -a "$disk_path" | grep "$resize_part" | grep -q "ext4"; then
            LOG "resize2fs $display_part"
        elif virt-filesystems --long -a "$disk_path" | grep "$resize_part" | grep -q "xfs"; then
            LOG "xfs_growfs <挂载点>"
        else
            LOG "请根据文件系统类型手动扩展（例如 resize2fs 或 xfs_growfs）。"
        fi
    fi
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
                elif [ "$action" = "check" ]; then
                    : # 已处理
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

