#!/bin/bash
#############################################################################
# Create By: zhf_sy
# License: GNU GPLv3
# Test On: Rocky Linux 9
#############################################################################


# sh
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd "${SH_PATH}" || exit 1

# 引入env
# shellcheck source=/home/kevin/git-projects/zzxia-kvm-manage/kvm.env.sample
. "${SH_PATH}/kvm.env"
#LOG_HOME=
#VM_DEFAULT_DNS=
#VM_DEFAULT_DOMAIN=
#KVM_DEFAULT_SSH_HOST=
#KVM_DEFAULT_SSH_PORT=
#KVM_DEFAULT_SSH_USER=

# 本地env
QUIET='NO'     #-- 静默方式
VM_LIST="${SH_PATH}/my_vm.list"
VM_LIST_APPEND_1="${SH_PATH}/my_vm.list.append.1"
#
VM_LIST_TMP="${LOG_HOME}/${SH_NAME}-my_vm.list.tmp"
VM_LIST_APPEND_1_TMP="${LOG_HOME}/${SH_NAME}-my_vm.list.append.1.tmp"
VM_LIST_EXISTED="${LOG_HOME}/${SH_NAME}-vm-list.existed"
#
FORMAT_TABLE_SH="${SH_PATH}/format_table.sh"


F_HELP()
{
    echo "
    用途：修改KVM虚拟机内部信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    依赖：
        ${SH_PATH}/kvm.env
        ${VM_LIST}
        ${VM_LIST_APPEND_1}
        ${FORMAT_TABLE_SH}
    注意：
        * 名称正则表达式完全匹配，会自动在正则表达式的头尾加上【^ $】，请规避
        * 输入命令时，参数顺序不分先后
    用法：
        $0  [-h|--help]
        $0  <-q|--quiet>  <{VM1}  {VM2} ... {VMn}> ... {VM名称正则表达式完全匹配}>
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help            此帮助
        -q|--quiet           静默方式
    示例:
        $0  -h             #--- 帮助
        $0                                        #-- 对所有虚拟机进行操作
        $0  v-192-168-1-3-a  v-192-168-1-44-bb    #-- 对正则完全匹配【^v-192-168-1-3-a$】及【^v-192-168-1-44-bb$】的虚拟机进行操作
        $0  v-192-168-1-3-a  v-172.*              #-- 对正则完全匹配【^v-192-168-1-3-a$】及【^v-172.*$】的虚拟机进行操作
        $0  -q  v-192-168-1-3-a                   #-- 用静默方式，对正则完全匹配【^v-192-168-1-3-a$】的虚拟机进行操作
    "
}



# 用法：F_SEARCH_EXISTED_VM  {虚拟机名}
F_SEARCH_EXISTED_VM ()
{
    FS_VM_NAME=$1
    GET_IT='NO'
    while read -r LINE
    do
        F_VM_NAME=$(echo "$LINE" | awk '{print $2}')
        F_VM_STATUS=$(echo "$LINE" | awk '{print $3}')
        if [ "x${FS_VM_NAME}" = "x${F_VM_NAME}" ]; then
            GET_IT='YES'
            break
        fi
    done < "${VM_LIST_EXISTED}"
    #
    if [ "${GET_IT}" = 'YES' ]; then
        echo -e "${F_VM_STATUS}"
        return 0
    else
        return 1
    fi
}



# chroot时运行
VIRT_RUN_SH ()
{
    cat << EOF
#!/bin/bash
# 这些改用 virt-sysprep 实现
# ## 换机器id
# :> /etc/machine-id       #-- 如果rm -f /etc/machine-id，且没有运行 systemd-machine-id-setup 则会出现问题，特别是网络部分
# systemd-machine-id-setup
# ## 换ssh_host_key
# rm -f /etc/ssh/ssh_host_*
# /usr/libexec/openssh/sshd-keygen ecdsa
# /usr/libexec/openssh/sshd-keygen ed25519
# /usr/libexec/openssh/sshd-keygen rsa
#
## hosts
sed -i '/localhost/!d' /etc/hosts
echo  "${VM_IP}    ${VM_NAME}.${VM_DOMAIN} ${VM_NAME}"  >> /etc/hosts
EOF
}



# 第一次boot时运行（就是在 virsh start 之后才会运行）
VIRT_FIRSTBOOT_SH ()
{
    cat << EOF
#!/bin/bash
# 注意：函数内部的变量必须转义
#
VIRT_FIRSTBOOT_SH_LOG="/var/log/${SH_NAME}-VIRT_FIRSTBOOT_SH.log"
:> \${VIRT_FIRSTBOOT_SH_LOG}
#
## 网卡
# 动态检测第一个非回环接口
NET_IF=\$(ip -o link show | awk '\$2 != "lo:" {print \$2; exit}' | sed 's/:$//')
if [ -z "\${NET_IF}" ]; then
  echo "猪猪侠警告：未发现网络接口，请检查！"  >> \${VIRT_FIRSTBOOT_SH_LOG}
  exit 1
fi
#
NET_IF_CONN_NAME="\${NET_IF}"
# 清理旧配置（如果存在）
nmcli connection delete \${NET_IF_CONN_NAME}  >/dev/null 2>&1
# 创建网络连接名称
nmcli connection add  \
    type ethernet  \
    ifname \${NET_IF}  \
    con-name \${NET_IF_CONN_NAME}  >> \${VIRT_FIRSTBOOT_SH_LOG}  2>&1
# 设置IP等
nmcli connection modify "\${NET_IF_CONN_NAME}" \
    ipv4.method manual \
    ipv4.addresses "${VM_IP}/${VM_IP_MASK}" \
    ipv4.gateway "${VM_IP_GATEWAY}" \
    ipv4.dns "${VM_DNS1},${VM_DNS2}" \
    ipv4.dns-search "${VM_DOMAIN}"  >> \${VIRT_FIRSTBOOT_SH_LOG}  2>&1
# up
nmcli connection up  \${NET_IF_CONN_NAME}  >> \${VIRT_FIRSTBOOT_SH_LOG}  2>&1
EOF
}


# 参数检查
TEMP=$(getopt -o hq  -l help,quiet -- "$@") || {
    echo -e "\n猪猪侠警告：参数不合法，请查看帮助【$0 --help】\n" >&2
    exit 1
}
#
eval set -- "${TEMP}" || {
    echo -e "\n猪猪侠警告：参数设置失败！\n" >&2
    exit 1
}



while true
do
    case "$1" in
        -h|--help)
            F_HELP
            exit
            ;;
        -q|--quiet)
            QUIET='YES'
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo -e "\n猪猪侠警告：未知参数，请查看帮助【$0 --help】\n"
            exit 1
            ;;
    esac
done


# 建立base目录
[ -d "${LOG_HOME}" ] || mkdir -p  "${LOG_HOME}"


# 待搜索的服务清单
:> "${VM_LIST_APPEND_1_TMP}"
# 参数个数为
if [[ $# -eq 0 ]]; then
    cp  "${VM_LIST_APPEND_1}"  "${VM_LIST_APPEND_1_TMP}"
    sed -i -e '/^#/d' -e '/^$/d' -e '/^[ ]*$/d' "${VM_LIST_APPEND_1_TMP}"
else
    for i in "$@"
    do
        #
        GET_IT='N'
        while read -r LINE
        do
            # 跳过以#开头的行或空行
            [[ $LINE =~ ^# ]] || [[ $LINE =~ ^[\ ]*$ ]] && continue
            #
            VM_NAME=$(echo "$LINE" | awk -F '|' '{print $2}' | xargs)
            if [[ ${VM_NAME} =~ ^$i$ ]]; then
                echo "$LINE" >> "${VM_LIST_APPEND_1_TMP}"
                GET_IT='YES'
                #break    #-- 匹配1次
            fi
        done < "${VM_LIST_APPEND_1}"
        #
        if [[ $GET_IT != 'YES' ]]; then
            echo -e "\n猪猪侠警告：虚拟机【${i}】不在列表【${VM_LIST}】中，请检查！\n"
            exit 51
        fi
    done
fi
# 加表头
sed -i  "1i#| **名称** | **IP地址** | IP掩码  | **IP网关** | **DNS** | **域名** |"  "${VM_LIST_APPEND_1_TMP}"
# 屏显
echo -e "${ECHO_NORMAL}=======================开始 Modify =======================${ECHO_CLOSE}"    #-- 60 ( 60==  50--  40== )
echo -e "\n【${SH_NAME}】待Modify虚拟机清单："
${FORMAT_TABLE_SH}  --delimeter '|'  --file "${VM_LIST_APPEND_1_TMP}"


# 交互
if [[ ${QUIET} == NO ]]; then
    echo "以上信息正确吗？如果正确，请输入 "'y'""
    read -r -p "请输入："  ANSWER
    #
    if [[ ! ${ANSWER} == y ]]; then
        echo "小子，好好检查吧！"
        exit 4
    fi
fi



# go
while read -r LINE
do
    # 跳过以#开头的行或空行
    [[ "$LINE" =~ ^# ]] || [[ "$LINE" =~ ^[\ ]*$ ]] && continue
    # 2
    VM_NAME=$(echo "${LINE}" | cut -f 2 -d '|' | xargs)
    # 3
    VM_IP=$(echo "${LINE}" | cut -d \| -f 3 | xargs)
    # 4
    VM_IP_MASK=$(echo "${LINE}" | cut -d \| -f 4 | xargs)
    # 5
    VM_IP_GATEWAY=$(echo "${LINE}" | cut -d \| -f 5 | xargs)
    # 6
    VM_DNS=$(echo "${LINE}" | cut -d \| -f 6 | xargs)
    VM_DNS=${VM_DNS:-${VM_DEFAULT_DNS}}
    VM_DNS1=$(echo "${VM_DNS}" | cut -d "," -f 1 | xargs)
    VM_DNS2=$(echo "${VM_DNS}" | cut -d "," -f 2 | xargs)
    # 7
    VM_DOMAIN=$(echo "${LINE}" | cut -d \| -f 7 | xargs)
    VM_DOMAIN=${VM_DOMAIN:-${VM_DEFAULT_DOMAIN}}
    #
    # + VM_LIST
    grep "${VM_NAME}" "${VM_LIST}" > "${VM_LIST_TMP}"
    GET_IT_A='NO'
    while read -r LINE_A
    do
        # 跳过以#开头的行或空行
        [[ "$LINE_A" =~ ^# ]] || [[ "$LINE_A" =~ ^[\ ]*$ ]] && continue
        # 2
        VM_NAME_A=$(echo "${LINE_A}" | cut -d \| -f 2 | xargs)
        #
        if [[ "${VM_NAME_A}" == "${VM_NAME}" ]]; then
            # 6
            KVM_HOST=$(echo "$LINE_A" | cut -f 6 -d '|' | xargs)
            #KVM_HOST=${KVM_HOST// /}
            # 初始化变量
            KVM_SSH_USER=""
            KVM_SSH_HOST=""
            KVM_SSH_PORT=""
            # 使用模式匹配提取用户、主机和端口
            if [[ -n "$KVM_HOST" ]]; then
                if [[ $KVM_HOST =~ ^([^@]+)@([^:]+)(:([0-9]+))?$ ]]; then
                    KVM_SSH_USER="${BASH_REMATCH[1]}"  # 提取用户
                    KVM_SSH_HOST="${BASH_REMATCH[2]}"  # 提取主机
                    KVM_SSH_PORT="${BASH_REMATCH[4]}"  # 提取端口
                elif [[ $KVM_HOST =~ ^([^:]+)(:([0-9]+))?$ ]]; then
                    KVM_SSH_HOST="${BASH_REMATCH[1]}"  # 提取主机
                    KVM_SSH_PORT="${BASH_REMATCH[3]}"  # 提取端口
                fi
            fi
            # 如果某个值为空，使用默认值
            KVM_SSH_USER="${KVM_SSH_USER:-$KVM_DEFAULT_SSH_USER}"
            KVM_SSH_HOST="${KVM_SSH_HOST:-$KVM_DEFAULT_SSH_HOST}"
            KVM_SSH_PORT="${KVM_SSH_PORT:-$KVM_DEFAULT_SSH_PORT}"
            #
            GET_IT_A='YES'
            break     #-- 匹配1次
        fi
    done < "${VM_LIST_TMP}"
    #
    if [[ ${GET_IT_A} != 'YES' ]];then
        echo -e "\n猪猪侠警告：在【${VM_LIST}】文件中没有找到虚拟机【${VM_NAME}】，请检查！\n"
        exit 51
    fi

    #
    echo "--------------------------------------------------"     #--- 50 (60-50-40)   == --
    echo "虚拟机：${VM_NAME}"
    echo "宿主机：${KVM_SSH_HOST}"
    echo "虚拟机IP：  ${VM_IP}/${VM_IP_MASK}"
    echo "虚拟机网关：${VM_IP_GATEWAY}"
    echo "虚拟机DNS： ${VM_DNS}"
    echo "虚拟机FQDN：${VM_NAME}.${VM_DOMAIN}"
    echo
    #
    KVM_LIBVIRT_URL="qemu+ssh://${KVM_SSH_USER}@${KVM_SSH_HOST}:${KVM_SSH_PORT}/system"
    #
    :> "${VM_LIST_EXISTED}"
    if ! virsh --connect "${KVM_LIBVIRT_URL}" list --all > "${VM_LIST_EXISTED}"; then
        echo -e "\n\033[31m猪猪侠警告：连接KVM宿主机失败，请检查以下问题：\033[0m"
        echo -e "1. libvirt服务是否运行？(systemctl status libvirtd)"
        echo -e "2. 连接URL是否正确？(当前尝试连接: ${KVM_LIBVIRT_URL})"
        echo -e "3. 是否有访问权限？(检查用户是否在libvirt组)\n"
        exit 1
    fi
    # 删除无用行
    sed -i '1,2d;s/[ ]*//;/^$/d'  "${VM_LIST_EXISTED}"
    #
    # 是否存在
    #
    VM_STATUS=$(F_SEARCH_EXISTED_VM  "${VM_NAME}")
    if [[ -z ${VM_STATUS} ]]; then
        echo -e "\n猪猪侠警告：虚拟机【${VM_NAME}】不存在，跳过\n"
        exit 1
    elif [[ ${VM_STATUS} =~ 'running'|'运行' ]]; then
        echo -e "\n猪猪侠警告：虚拟机【${VM_NAME}】正在运行中，请先停止，退出\n"
        exit 1
    fi
    #
#    ## 获取虚拟机OS版本信息
#    VM_OS_RELEASE_FILE="${LOG_HOME}/os-release"
#    virt-cat  --connect "${KVM_LIBVIRT_URL}"  -d "${VM_NAME}"  /etc/os-release  > "${VM_OS_RELEASE_FILE}"
#    VM_OS=$(cat ${VM_OS_RELEASE_FILE}  |  grep -E ^ID=  |  cut -d '"' -f 2)
#    VM_OS_VERSION=$(cat ${VM_OS_RELEASE_FILE}  |  grep -E ^VERSION_ID=  |  cut -d '"' -f 2)
#    VM_OS_PRETTY_NAME=$(cat ${VM_OS_RELEASE_FILE}  |  grep -E ^PRETTY_NAME=  |  cut -d '"' -f 2)
    #
    #
    ### virt-sysprep
    echo "开始 virt-sysprep ......"
    #
    time virt-sysprep -d "${VM_NAME}" --enable machine-id,ssh-hostkeys
    #
    ### virt-customize
    echo "开始 virt-customize ......"
    #
    VIRT_RUN_SH_FILE="${LOG_HOME}/virt-customize-run-script.sh"
    VIRT_RUN_SH  > ${VIRT_RUN_SH_FILE}
    chmod +x ${VIRT_RUN_SH_FILE}
    VIRT_FIRSTBOOT_SH_FILE="${LOG_HOME}/virt-customize-firstboot-script.sh"
    VIRT_FIRSTBOOT_SH  > ${VIRT_FIRSTBOOT_SH_FILE}
    chmod +x ${VIRT_FIRSTBOOT_SH_FILE}
    #
    VIRT_CUSTOMIZE_LOG_FILE="${LOG_HOME}/${SH_NAME}-virt-customize.log--${VM_NAME}"
    :> "${VIRT_CUSTOMIZE_LOG_FILE}"
    #
    time virt-customize  \
        --connect "${KVM_LIBVIRT_URL}"  \
        --hostname "${VM_NAME}.${VM_DOMAIN}"  \
        --run ${VIRT_RUN_SH_FILE}  \
        --firstboot ${VIRT_FIRSTBOOT_SH_FILE}  \
        -d "${VM_NAME}" 2>&1  | tee "${VIRT_CUSTOMIZE_LOG_FILE}"
    #
    if [ "$(grep -q -i 'ERROR' "${VIRT_CUSTOMIZE_LOG_FILE}"; echo $?)" -eq 0 ]; then
        echo -e "\n猪猪侠警告：【${VM_NAME}】virt-customize 出错，请检查！\n（检查方法：cat ${VIRT_CUSTOMIZE_LOG_FILE}）\n"
        exit 1
    fi
    #
done < "${VM_LIST_APPEND_1_TMP}"


