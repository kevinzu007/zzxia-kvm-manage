#!/bin/bash
#############################################################################
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: Rocky Linux 9
#############################################################################

# sh
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

# 脚本名称和版本
SCRIPT_NAME="${SH_NAME}"
VERSION="1.0.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 引入环境变量
if [ -f "${SH_PATH}/env.sh" ]; then
    source "${SH_PATH}/env.sh"
fi

# 日志函数
LOG() {
    echo -e "${GREEN}[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*${NC}"
}

ERROR() {
    echo -e "${RED}[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*${NC}" >&2
}

WARN() {
    echo -e "${YELLOW}[$(date "+%Y-%m-%d %H:%M:%S")] ${SH_NAME}: $*${NC}"
}

# 显示帮助信息
F_HELP() {
    echo -e "
${GREEN}用途：${NC}扩展KVM虚拟机的磁盘空间并调整分区和文件系统
${GREEN}支持存储类型：${NC}
    * 本地文件（qcow2/raw）
    * 本地块设备（LVM/分区）
${RED}不支持的类型：${NC}
    * RBD/CEPH存储
    * iSCSI存储
    * 其他网络存储
${GREEN}依赖：${NC}
    * libguestfs-tools (包含virt-resize, virt-customize等工具)
    * qemu-img
    * virsh
    * xmllint
${GREEN}注意：${NC}
    * 建议在虚拟机关机状态下操作
    * 重要数据请提前备份
    * 需要root权限执行
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
    $0 [-f|--force] {<虚拟机名称> <目标分区> <扩展大小(GB)>}
${GREEN}参数说明：${NC}
    -h|--help       显示此帮助信息
    -v|--version    显示脚本版本
    -l|--list       列出所有KVM虚拟机
    -c|--check      检查虚拟机磁盘和分区信息
    -f|--force      强制在虚拟机运行时操作(不推荐)
    -q|--quiet      安静模式，减少输出
    -d|--dry-run    试运行，只显示将要执行的操作
${GREEN}使用示例：${NC}
    $0 -h                          # 显示帮助信息
    $0 -l                          # 列出所有虚拟机
    $0 -c vm1                      # 检查【vm1】的磁盘信息
    $0 vm1 /dev/sda1 10            # 扩展【vm1】的【/dev/sda1】分区【10GB】
    $0 -f vm1 /dev/vda2 20         # 强制扩展(虚拟机运行时)
    $0 -d vm1 /dev/sdb1 5          # 试运行，不实际执行
"
}

# 获取虚拟机系统磁盘路径（支持所有存储类型）
get_vm_disk_path() {
    local vm_name="$1"
    local disk_xml=""
    local disk_path=""

    # 获取磁盘配置XML片段
    disk_xml=$(virsh dumpxml "$vm_name" | xmllint --xpath '/domain/devices/disk[@device="disk"][1]/source' - 2>/dev/null || true)

    # 解析不同类型存储（移除函数内的LOG调用）
    if [[ "$disk_xml" =~ file=\"([^\"]+)\" ]]; then
        disk_path="${BASH_REMATCH[1]}"
    elif [[ "$disk_xml" =~ dev=\"([^\"]+)\" ]]; then
        disk_path="${BASH_REMATCH[1]}"
    elif [[ "$disk_xml" =~ name=\"([^\"]+)\" ]]; then
        if [[ "$disk_xml" =~ protocol=\"rbd\" ]]; then
            local pool=$(virsh dumpxml "$vm_name" | xmllint --xpath 'string(/domain/devices/disk[@device="disk"][1]/source/@pool)' - 2>/dev/null || true)
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
        disk_path=$(echo "$disk_path" | xargs)  # 去除首尾空白字符
    fi

    # 验证结果
    if [ -z "$disk_path" ]; then
        ERROR "无法获取虚拟机的系统磁盘路径！"
        exit 1
    fi

    if [[ "$disk_path" =~ ^(rbd:|iscsi:|net:) ]]; then
        ERROR "不支持的网络存储类型: ${disk_path}"
        exit 1
    fi

    if [ ! -f "$disk_path" ] && [[ ! "$disk_path" =~ ^/dev/ ]]; then
        ERROR "磁盘路径不存在或不是有效设备: ${disk_path}"
        exit 1
    fi

    # 只返回纯净的磁盘路径
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
        exit 1
    fi

    LOG "虚拟机 ${vm_name} 磁盘信息："
    virsh domblklist "$vm_name"

    LOG "磁盘详细信息："
    local disk_path=$(get_vm_disk_path "$vm_name")
    LOG "检测到磁盘路径: ${disk_path}"
    qemu-img info "$disk_path"

    # 新增磁盘健康检查
    LOG "开始磁盘健康检查..."
    local check_result=$(qemu-img check "$disk_path" 2>&1)
    if [[ "$check_result" =~ "No errors found" ]]; then
        LOG "磁盘健康状态: ${GREEN}正常${NC}"
    else
        WARN "磁盘健康检查结果："
        echo "$check_result"
    fi
    LOG "=============================================="
}

# 获取虚拟机内文件系统信息
get_vm_fs_info() {
    local disk_path="$1"
    local target_part="$2"

    # 使用virt-filesystems获取精确信息
    local fs_info=$(virt-filesystems --format=qcow2 -a "$disk_path" --long -h | grep "$target_part")

    # 提取文件系统类型和挂载点
    local fs_type=$(echo "$fs_info" | awk '{print $2}')
    local mount_point=$(echo "$fs_info" | awk '{print $1}')

    # 如果没有挂载点，尝试通过blkid获取类型
    if [[ -z "$fs_type" ]]; then
        fs_type=$(virt-customize -a "$disk_path" --run-command "blkid -o value -s TYPE $target_part 2>/dev/null" | tail -1)
    fi

    echo "$fs_type $mount_point"
}

# 单位转换函数
human_size() {
    local bytes=$1
    if command -v bc &>/dev/null; then
        # 转换为TB (1TB = 1024^4 bytes)
        if (( bytes >= 1099511627776 )); then  # 1TB = 1024^4
            echo "$(echo "scale=1; $bytes / (1024^4)" | bc | awk '{printf "%.1fTiB", $1}')"
        # 转换为GB (1GB = 1024^3 bytes)
        else
            echo "$(echo "scale=1; $bytes / (1024^3)" | bc | awk '{printf "%.1fGiB", $1}')"
        fi
    else
        if (( bytes >= 1099511627776 )); then
            echo "$(( bytes / 1024 / 1024 / 1024 / 1024 ))TiB"
        else
            echo "$(( bytes / 1024 / 1024 / 1024 ))GiB"
        fi
        WARN "未找到bc命令，已切换为整数计算"
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
    if ! [[ "$add_size_gb" =~ ^[0-9]+$ ]]; then
        ERROR "扩展大小必须是正整数(GB)！"
        exit 1
    fi
    
    if ! [[ "$target_part" =~ ^/dev/[a-z]+[0-9]+$ ]]; then
        ERROR "分区格式不正确，请使用类似/dev/sda1的格式！"
        exit 1
    fi
    
    # 检查虚拟机是否存在
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        ERROR "虚拟机 ${vm_name} 不存在！"
        exit 1
    fi
    
    # 获取磁盘路径
    local disk_path=$(get_vm_disk_path "$vm_name")
    
    # 检查虚拟机状态
    local vm_state=$(virsh domstate "$vm_name")
    if [ "$vm_state" != "shut off" ] && [ "$force" != "yes" ]; then
        ERROR "虚拟机 ${vm_name} 正在运行，请先关闭虚拟机或使用 -f 强制操作！"
        exit 1
    fi
    
    # 获取当前磁盘大小
    local current_size_bytes=$(qemu-img info "$disk_path" | awk -F'[ ()]' '/virtual size/ {print $6}')
    
    # 计算新大小（保持GB单位用于计算）
    local current_size_gb=$(echo "scale=1; $current_size_bytes / (1024^3)" | bc)
    local new_size_gb=$(echo "$current_size_gb + $add_size_gb" | bc)

    # 显示操作信息
    if [ "$quiet" != "yes" ]; then
        LOG "=============================================="
        LOG "操作摘要："
        LOG "虚拟机名称:      ${vm_name}"
        LOG "磁盘文件:        ${disk_path}"
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
            LOG "3. 调整文件系统"
            LOG "=============================================="
            exit 0
        fi
        
        read -p "确认以上信息是否正确? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            WARN "操作已取消。"
            exit 0
        fi
    fi
    
    # 1. 扩展磁盘文件
    LOG "[1/3] 正在扩展磁盘文件..."
    if ! qemu-img resize "$disk_path" "+${add_size_gb}G"; then
        ERROR "磁盘扩展失败！"
        exit 1
    fi
    
    # 2. 调整分区表
    LOG "[2/3] 正在调整分区表..."
    
    # 使用临时文件进行操作
    local temp_disk="${disk_path}.resized"
    
    if ! virt-resize --expand "${target_part}" "${disk_path}" "${temp_disk}"; then
        ERROR "分区调整失败！"
        rm -f "$temp_disk"
        exit 1
    fi
    
    # 替换原磁盘文件
    mv "$temp_disk" "$disk_path"
    
    # 3. 调整文件系统（自动检测类型）
    LOG "[3/3] 正在检测并调整文件系统..."

    # 获取文件系统信息
    read fs_type mount_point <<< $(get_vm_fs_info "$disk_path" "$target_part")

    if [[ -z "$fs_type" ]]; then
        WARN "无法自动检测文件系统类型，请手动处理！"
        WARN "可能需要登录虚拟机执行以下命令之一："
        WARN "  resize2fs $target_part    # 对于ext2/3/4"
        WARN "  xfs_growfs $mount_point   # 对于XFS"
        exit 1
    fi

    case "$fs_type" in
        ext*)
            LOG "检测到${fs_type}文件系统，挂载点: ${mount_point:-未挂载}"
            if [[ -n "$mount_point" ]]; then
                virt-customize -a "$disk_path" --run-command "resize2fs $target_part"
            else
                WARN "分区未挂载，建议启动虚拟机后执行: resize2fs $target_part"
            fi
            ;;
        xfs)
            LOG "检测到XFS文件系统，挂载点: ${mount_point:-未挂载}"
            if [[ -n "$mount_point" ]]; then
                virt-customize -a "$disk_path" --run-command "xfs_growfs $mount_point"
            else
                WARN "分区未挂载，建议启动虚拟机后执行: xfs_growfs $target_part"
            fi
            ;;
        swap)
            LOG "检测到SWAP分区，无需调整"
            ;;
        *)
            WARN "不支持的文件系统类型: ${fs_type}"
            WARN "需要手动处理该文件系统的扩容"
            exit 1
            ;;
    esac
    
    
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
    # 参数处理
    local action="expand"
    local vm_name=""
    local target_part=""
    local add_size_gb=""
    local force="no"
    local quiet="no"
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
            -f|--force)
                force="yes"
                ;;
            -q|--quiet)
                quiet="yes"
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
            F_CHECK_DISK "$vm_name"
            ;;
        expand)
            if [ -z "$vm_name" ] || [ -z "$target_part" ] || [ -z "$add_size_gb" ]; then
                ERROR "缺少必要参数！"
                F_HELP
                exit 1
            fi
            F_EXPAND_DISK "$vm_name" "$target_part" "$add_size_gb" "$force" "$quiet" "$dry_run"
            ;;
        *)
            ERROR "未知操作！"
            exit 1
            ;;
    esac
}

# 执行主程序
main "$@"

