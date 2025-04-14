#!/bin/bash
#############################################################################
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: Rocky Linux 9
# Purpose: Add a new or existing qcow2 disk to a KVM virtual machine
# Created Date: 2025-04-14
# Updated By: Grok 3 (xAI)
# Update Date: 2025-04-14
#############################################################################

# sh
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

# 脚本名称和版本
SCRIPT_NAME="${SH_NAME}"
VERSION="1.0.1"  # 更新版本号以反映修复

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
${GREEN}用途：${NC}为KVM虚拟机添加新创建或现有的qcow2硬盘
${GREEN}支持操作：${NC}
    * 创建新qcow2硬盘（自动分区并格式化）
    * 添加现有qcow2硬盘
${GREEN}支持 => 支持存储类型：${NC}
    * 本地qcow2文件
${RED}不支持的类型：${NC}
    * raw格式磁盘
    * 块设备（LVM/分区）
    * 网络存储（RBD、iSCSI等）
${GREEN}依赖：${NC}
    * libguestfs-tools (包含guestfish等工具)
    * qemu-img
    * virsh
${GREEN}注意：${NC}
    * 建议在虚拟机关机状态下操作（-f 可尝试热插拔）
    * 重要数据请提前备份
    * 需要root权限执行
    * 新硬盘将分为一个主分区，格式化为指定文件系统（ext4或xfs）
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
    $0 -a|--add [-f|--force] [-q|--quiet] [-d|--dry-run] {<虚拟机名称> <硬盘路径>}
    $0 -c|--create [-f|--force] [-q|--quiet] [-d|--dry-run] {<虚拟机名称> <硬盘路径> <大小(GB)> <文件系统(ext4|xfs)>}
${GREEN}参数说明：${NC}
    -h|--help       显示此帮助信息
    -v|--version    显示脚本版本
    -l|--list       列出所有KVM虚拟机及其磁盘
    -a|--add        添加现有qcow2硬盘到虚拟机
    -c|--create     创建新qcow2硬盘（分区并格式化）并添加到虚拟机
    -f|--force      强制在虚拟机运行时操作（尝试热插拔）
    -q|--quiet      安静模式，减少输出
    -d|--dry-run    试运行，只显示将要执行的操作
${GREEN}使用示例：${NC}
    $0 -h                          # 显示帮助信息
    $0 -l                          # 列出所有虚拟机
    $0 -a vm1 /path/to/existing.qcow2  # 添加现有硬盘到vm1
    $0 -c vm1 /path/to/new.qcow2 10 ext4  # 创建10GB新硬盘，格式化为ext4，添加到vm1
    $0 -c -f vm1 /path/to/new.qcow2 20 xfs  # 运行时创建并添加20GB xfs硬盘
    $0 -c -d vm1 /path/to/new.qcow2 5 ext4  # 试运行创建5GB ext4硬盘
"
}

# 显示版本信息
F_VERSION() {
    echo -e "${GREEN}${SCRIPT_NAME} ${VERSION}${NC}"
}

# 列出所有KVM虚拟机及其磁盘
F_LIST_VMS() {
    LOG "可用KVM虚拟机列表："
    virsh list --all
    LOG "虚拟机磁盘信息："
    for vm in $(virsh list --all --name); do
        LOG "虚拟机: $vm"
        virsh domblklist "$vm"
    done
}

# 验证虚拟机存在
check_vm_exists() {
    local vm_name="$1"
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
    fi
}

# 验证硬盘路径
check_disk_path() {
    local disk_path="$1"
    local operation="$2"  # add 或 create

    if [ "$operation" = "add" ]; then
        if [ ! -f "$disk_path" ]; then
            ERROR "硬盘文件 ${disk_path} 不存在！"
        fi
        if ! qemu-img info "$disk_path" | grep -q "format: qcow2"; then
            ERROR "硬盘文件 ${disk_path} 不是 qcow2 格式！"
        fi
    elif [ "$operation" = "create" ]; then
        if [ -f "$disk_path" ]; then
            ERROR "硬盘文件 ${disk_path} 已存在，请选择其他路径！"
        fi
        local dir=$(dirname "$disk_path")
        if [ ! -d "$dir" ] || [ ! -w "$dir" ]; then
            ERROR "目标目录 ${dir} 不存在或不可写！"
        fi
    fi
}

# 创建并格式化新硬盘
create_disk() {
    local disk_path="$1"
    local size_gb="$2"
    local fs_type="$3"
    local dry_run="$4"

    if [ "$dry_run" = "yes" ]; then
        LOG "[试运行] 将创建硬盘: qemu-img create -f qcow2 \"$disk_path\" ${size_gb}G"
        LOG "[试运行] 将分区并格式化为 ${fs_type}"
        return
    fi

    LOG "正在创建新 qcow2 硬盘..."
    if ! qemu-img create -f qcow2 "$disk_path" "${size_gb}G"; then
        ERROR "创建硬盘 ${disk_path} 失败！"
    fi

    LOG "正在分区并格式化硬盘为 ${fs_type}..."
    if [ "$fs_type" = "ext4" ]; then
        if ! guestfish --rw -a "$disk_path" <<EOF
run
part-disk /dev/sda mbr
mkfs ext4 /dev/sda1
EOF
        then
            rm -f "$disk_path"
            ERROR "分区或格式化 ${disk_path} 失败！"
        fi
    elif [ "$fs_type" = "xfs" ]; then
        if ! guestfish --rw -a "$disk_path" <<EOF
run
part-disk /dev/sda mbr
mkfs xfs /dev/sda1
EOF
        then
            rm -f "$disk_path"
            ERROR "分区或格式化 ${disk_path} 失败！"
        fi
    else
        rm -f "$disk_path"
        ERROR "不支持的文件系统类型: ${fs_type}"
    fi

    # 验证硬盘文件存在
    if [ ! -f "$disk_path" ]; then
        ERROR "硬盘文件 ${disk_path} 创建后未找到！"
    fi
}

# 添加硬盘到虚拟机
add_disk_to_vm() {
    local vm_name="$1"
    local disk_path="$2"
    local force="$3"
    local dry_run="$4"

    local vm_state=$(virsh domstate "$vm_name")
    local persistent="--persistent"
    if [ "$vm_state" != "shut off" ]; then
        if [ "$force" != "yes" ]; then
            ERROR "虚拟机 ${vm_name} 正在运行，请先关闭或使用 -f 强制热插拔！"
        fi
        persistent=""  # 热插拔不使用持久化
    fi

    if [ "$dry_run" = "yes" ]; then
        LOG "[试运行] 将添加硬盘到虚拟机: virsh attach-disk \"$vm_name\" \"$disk_path\" vdb --targetbus virtio --subdriver qcow2 $persistent"
        return
    fi

    LOG "正在将硬盘添加到虚拟机 ${vm_name}..."
    if ! virsh attach-disk "$vm_name" "$disk_path" vdb --targetbus virtio --subdriver qcow2 $persistent; then
        ERROR "添加硬盘到虚拟机 ${vm_name} 失败！"
    fi

    LOG "硬盘已添加，目标设备为 /dev/vdb"
    if [ "$vm_state" != "shut off" ]; then
        LOG "虚拟机运行中，请登录虚拟机挂载新磁盘（例如：mkfs.<fs_type> /dev/vdb1 && mount /dev/vdb1 /mnt）"
    else
        LOG "虚拟机已关机，请启动后挂载新磁盘"
    fi
}

# 主操作函数
F_ADD_DISK() {
    local operation="$1"
    local vm_name="$2"
    local disk_path="$3"
    local size_gb="$4"
    local fs_type="$5"
    local force="$6"
    local quiet="$7"
    local dry_run="$8"

    # 验证虚拟机
    check_vm_exists "$vm_name"

    # 验证硬盘路径
    check_disk_path "$disk_path" "$operation"

    # 验证大小和文件系统（仅 create）
    if [ "$operation" = "create" ]; then
        if ! [[ "$size_gb" =~ ^[0-9]+$ ]] || [ "$size_gb" -eq 0 ]; then
            ERROR "硬盘大小必须是正整数（单位：GB）！"
        fi
        if [ "$fs_type" != "ext4" ] && [ "$fs_type" != "xfs" ]; then
            ERROR "文件系统必须是 ext4 或 xfs！"
        fi
    fi

    # 显示操作信息
    if [ "$quiet" != "yes" ]; then
        LOG "=============================================="
        LOG "操作摘要："
        LOG "操作类型:        ${operation}"
        LOG "虚拟机名称:      ${vm_name}"
        LOG "硬盘路径:        ${disk_path}"
        if [ "$operation" = "create" ]; then
            LOG "硬盘大小:        ${size_gb}GB"
            LOG "文件系统:        ${fs_type}"
        fi
        LOG "虚拟机状态:      $(virsh domstate "$vm_name")"
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

    # 执行操作
    if [ "$operation" = "create" ]; then
        create_disk "$disk_path" "$size_gb" "$fs_type" "$dry_run"
    fi

    if [ "$dry_run" != "yes" ] || [ "$operation" = "add" ]; then
        add_disk_to_vm "$vm_name" "$disk_path" "$force" "$dry_run"
    fi

    LOG "=============================================="
    LOG "操作成功完成！"
    LOG "虚拟机:        ${vm_name}"
    LOG "硬盘路径:      ${disk_path}"
    if [ "$operation" = "create" ]; then
        LOG "硬盘大小:      ${size_gb}GB"
        LOG "文件系统:      ${fs_type}"
    fi
    LOG "目标设备:      /dev/vdb"
    LOG "=============================================="
}

# 主程序
main() {
    check_root

    # 参数处理
    local action=""
    local vm_name=""
    local disk_path=""
    local size_gb=""
    local fs_type=""
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
            -a|--add)
                action="add"
                ;;
            -c|--create)
                action="create"
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
                if [ "$action" = "add" ]; then
                    if [ -z "$vm_name" ]; then
                        vm_name="$1"
                    elif [ -z "$disk_path" ]; then
                        disk_path="$1"
                    else
                        ERROR "未知参数或参数过多：$1"
                        F_HELP
                        exit 1
                    fi
                elif [ "$action" = "create" ]; then
                    if [ -z "$vm_name" ]; then
                        vm_name="$1"
                    elif [ -z "$disk_path" ]; then
                        disk_path="$1"
                    elif [ -z "$size_gb" ]; then
                        size_gb="$1"
                    elif [ -z "$fs_type" ]; then
                        fs_type="$1"
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
        ERROR "请指定操作类型（如 -a|--add 或 -c|--create）！"
        F_HELP
        exit 1
    fi

    # 验证参数完整性
    case "$action" in
        add)
            if [ -z "$vm_name" ] || [ -z "$disk_path" ]; then
                ERROR "缺少必要参数！需要提供虚拟机名称和硬盘路径。"
                F_HELP
                exit 1
            fi
            ;;
        create)
            if [ -z "$vm_name" ] || [ -z "$disk_path" ] || [ -z "$size_gb" ] || [ -z "$fs_type" ]; then
                ERROR "缺少必要参数！需要提供虚拟机名称、硬盘路径、大小和文件系统类型。"
                F_HELP
                exit 1
            fi
            ;;
        *)
            ERROR "未知操作类型！"
            F_HELP
            exit 1
            ;;
    esac

    # 执行操作
    F_ADD_DISK "$action" "$vm_name" "$disk_path" "$size_gb" "$fs_type" "$force" "$QUIET" "$dry_run"
}

# 执行主程序
main "$@"

