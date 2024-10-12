#!/bin/bash
#############################################################################
# Create By: zhf_sy
# License: GNU GPLv3
# Test On: CentOS 7
#############################################################################


# sh
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}

# 引入env
. ${SH_PATH}/kvm.env
#LOG_HOME=
#VM_DEFAULT_DNS=
#VM_DEFAULT_DOMAIN=

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
    while read LINE
    do
        F_VM_NAME=`echo "$LINE" | awk '{print $2}'`
        F_VM_STATUS=`echo "$LINE" | awk '{print $3}'`
        if [ "x${FS_VM_NAME}" = "x${F_VM_NAME}" ]; then
            GET_IT='YES'
            break
        fi
    done < ${VM_LIST_EXISTED}
    #
    if [ "${GET_IT}" = 'YES' ]; then
        echo -e "${F_VM_STATUS}"
        return 0
    else
        return 1
    fi
}



# 生成hosts
# 用法：F_GEN_HOSTS
F_GEN_HOSTS ()
{
    cat  << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
${VM_IP}    ${VM_NAME}.${VM_DOMAIN} ${VM_NAME}
EOF
}



# 生成网卡配置
# 用法：F_GEN_NIC_CONF  [centos|ubuntu]
F_GEN_NIC_CONF ()
{
    case $1 in
        centos)
            cat << EOF
## 公共
TYPE="Ethernet"
#UUID="906417c0-e533-428f-ad64-ba8734603236"
NAME="eth0"
DEVICE="eth0"
ONBOOT="yes"              #-- 开机启动
PROXY_METHOD="none"       #-- 代理方式
BROWSER_ONLY="no"         #-- 只是浏览器:否

## v4
BOOTPROTO="none"          #-- none：不指定；static：静态指定；dhcp：动态dhcp获取；bootp：动态bootp获取
IPADDR=${VM_IP}
PREFIX=${VM_IP_MASK}
GATEWAY=${VM_IP_GATEWAY}
DNS1=${VM_DNS1}
DNS2=${VM_DNS2}
DOMAIN=${VM_DOMAIN}
#
DEFROUTE="yes"
IPV4_FAILURE_FATAL="no"

## v6
IPV6INIT="no"             #-- yes：启用IPV6
#
DHCPV6C=yes               #-- yes：动态DHCP获取；no：静态IP
#IPV6ADDR=<IPv6 address>[/<prefix length>]
#IPV6_DEFAULTGW=<IPv6 address[%interface]> (optional)
#
IPV6_DEFROUTE="yes"       #-- yes：多网卡时，默认路由使用此网卡路由。IPV4的参数是DEFROUTE
IPV6_FAILURE_FATAL="no"   #-- yes：获取IP失败时，不再继续，比如继续获取IPV4地址。IPV4的参数是IPV4_FAILURE_FATAL
IPV6_PEERDNS="yes"        #-- yes：修改/etc/resolv.conf后，重启系统后会还原，不会改变；no：会永久改变。IPV4的参数是PEERDNS。实测无效呢？
IPV6_PEERROUTES="yes"     #-- 如果route-ethXX配置了永久路由，且使用了DHCP时：： yes：DHCP会设置路由覆盖；no：DHCP不设置路由，使用route-ethXX中的路由。IPV4的参数是PEERROUTES。
IPV6_PRIVACY="no"
IPV6_ADDR_GEN_MODE="stable-privacy"
IPV6_AUTOCONF="yes"       #-- yes：接受路由器通告（RA）
EOF
            ;;
        ubuntu)
            cat  << EOF
#没搞没搞没搞
network:
  ethernets:
    ens33:
      dhcp4: no
      addresses: [${VM_IP}/${VM_IP_MASK}]
      routes:
        - to: default
          via: ${VM_IP_GATEWAY}
      nameservers:
        addresses: [${VM_DNS1},${VM_DNS2}]
  version: 2
EOF
            ;;
        *)
            echo 没搞，你来
            ;;
    esac
}



# 参数检查
TEMP=`getopt -o hq  -l help,quiet -- "$@"`
if [ $? != 0 ]; then
    echo -e "\n峰哥说：参数不合法，请查看帮助【$0 --help】\n"
    exit 1
fi
#
eval set -- "${TEMP}"


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
            echo -e "\n峰哥说：未知参数，请查看帮助【$0 --help】\n"
            exit 1
            ;;
    esac
done


# 建立base目录
[ -d "${LOG_HOME}" ] || mkdir -p  "${LOG_HOME}"


# 待搜索的服务清单
> ${VM_LIST_APPEND_1_TMP}
# 参数个数为
if [[ $# -eq 0 ]]; then
    cp  ${VM_LIST_APPEND_1}  ${VM_LIST_APPEND_1_TMP}
    sed -i -e '/^#/d' -e '/^$/d' -e '/^[ ]*$/d' ${VM_LIST_APPEND_1_TMP}
else
    for i in $@
    do
        #
        GET_IT='N'
        while read LINE
        do
            # 跳过以#开头的行或空行
            [[ "$LINE" =~ ^# ]] || [[ "$LINE" =~ ^[\ ]*$ ]] && continue
            #
            VM_NAME=`echo $LINE | awk -F '|' '{print $2}'`
            VM_NAME=`echo ${VM_NAME}`
            if [[ ${VM_NAME} =~ ^$i$ ]]; then
                echo $LINE >> ${VM_LIST_APPEND_1_TMP}
                GET_IT='YES'
                #break    #-- 匹配1次
            fi
        done < ${VM_LIST_APPEND_1}
        #
        if [[ $GET_IT != 'YES' ]]; then
            echo -e "\n猪猪侠警告：虚拟机【${i}】不在列表【${VM_LIST}】中，请检查！\n"
            exit 51
        fi
    done
fi
# 加表头
sed -i  "1i#| **名称** | **IP地址** | IP掩码  | **IP网关** | **DNS** | **域名** |"  ${VM_LIST_APPEND_1_TMP}
# 屏显
echo -e "${ECHO_NORMAL}=======================开始 Sysprep =======================${ECHO_CLOSE}"    #-- 60 ( 60==  50--  40== )
echo -e "\n【${SH_NAME}】待Sysprep虚拟机清单："
${FORMAT_TABLE_SH}  --delimeter '|'  --file ${VM_LIST_APPEND_1_TMP}


# 交互
if [[ ${QUIET} == NO ]]; then
    echo "以上信息正确吗？如果正确，请输入 "'y'""
    read -p "请输入："  ANSWER
    #
    if [[ ! ${ANSWER} == y ]]; then
        echo "小子，好好检查吧！"
        exit 4
    fi
fi



# go
while read LINE
do
    # 2
    VM_NAME=`echo $LINE | cut -f 2 -d '|'`
    VM_NAME=`echo $VM_NAME`
    # 3
    VM_IP=`echo ${LINE} | cut -d \| -f 3`
    VM_IP=`echo ${VM_IP}`
    # 4
    VM_IP_MASK=`echo ${LINE} | cut -d \| -f 4`
    VM_IP_MASK=`echo ${VM_IP_MASK}`
    # 5
    VM_IP_GATEWAY=`echo ${LINE} | cut -d \| -f 5`
    VM_IP_GATEWAY=`echo ${VM_IP_GATEWAY}`
    # 6
    VM_DNS=`echo ${LINE} | cut -d \| -f 6`
    VM_DNS=`echo ${VM_DNS}`
    VM_DNS=${VM_DNS-:${VM_DEFAULT_DOMAIN}}
    VM_DNS1=`echo ${VM_DNS} | cut -d "," -f 1`
    VM_DNS2=`echo ${VM_DNS} | cut -d "," -f 2`
    # 7
    VM_DOMAIN=`echo ${LINE} | cut -d \| -f 7`
    VM_DOMAIN=`echo ${VM_DOMAIN}`
    VM_DOMAIN=${VM_DOMAIN-:${VM_DEFAULT_DOMAIN}}
    #
    # + VM_LIST
    cat ${VM_LIST} | grep "${VM_NAME}"  >  ${VM_LIST_TMP}
    GET_IT_A='NO'
    while read LINE_A
    do
        # 跳过以#开头的行或空行
        [[ "$LINE_A" =~ ^# ]] || [[ "$LINE_A" =~ ^[\ ]*$ ]] && continue
        # 2
        VM_NAME_A=`echo ${LINE_A} | cut -d \| -f 2`
        VM_NAME_A=`echo ${VM_NAME_A}`
        #
        if [[ ${VM_NAME_A} == ${VM_NAME} ]]; then
            # 6
            KVM_HOST=`echo $LINE_A | cut -f 6 -d '|'`
            KVM_HOST=`echo ${KVM_HOST}`
            #
            GET_IT_A='YES'
            break     #-- 匹配1次
        fi
    done < ${VM_LIST_TMP}
    #
    if [[ ${GET_IT_A} != 'YES' ]];then
        echo -e "\n猪猪侠警告：在【${VM_LIST}】文件中没有找到虚拟机【${VM_NAME}】，请检查！\n"
        exit 51
    fi

    #
    echo "--------------------------------------------------"     #--- 50 (60-50-40)   == --
    echo "虚拟机：${VM_NAME}"
    echo "宿主机：${KVM_HOST}"
    echo "虚拟机IP：  ${VM_IP}/${VM_IP_MASK}"
    echo "虚拟机网关：${VM_IP_GATEWAY}"
    echo "虚拟机DNS： ${VM_DNS}"
    echo "虚拟机FQDN：${VM_NAME}.${VM_DOMAIN}"
    echo
    #
    KVM_LIBVIRT_URL="qemu+ssh://${KVM_SSH_USER}@${KVM_HOST}:${KVM_SSH_PORT}/system"
    #
    > ${VM_LIST_EXISTED}
    virsh  --connect ${KVM_LIBVIRT_URL}  list --all  > ${VM_LIST_EXISTED}
    if [[ $? -ne 0 ]]; then
        echo -e "\n峰哥说：连接KVM宿主机失败，退出！\n"
        exit 1
    fi
    # 删除无用行
    sed -i '1,2d;s/[ ]*//;/^$/d'  ${VM_LIST_EXISTED}
    #
    # 是否存在
    #
    VM_STATUS=$(F_SEARCH_EXISTED_VM  "${VM_NAME}")
    if [[ -z ${VM_STATUS} ]]; then
        echo -e "\n峰哥说：虚拟机【${VM_NAME}】不存在存在，跳过\n"
        exit 1
    elif [[ ${VM_STATUS} =~ 'running'|'运行' ]]; then
        echo -e "\n峰哥说：虚拟机【${VM_NAME}】正在运行中，请先停止，退出\n"
        exit 1
    fi
    #
    # sysprep
    #
    # 获取版本信息
    VM_OS_RELEASE_FILE="${LOG_HOME}/os-release"
    ssh  -p ${KVM_SSH_PORT}  ${KVM_SSH_USER}@${KVM_HOST}  "virt-cat  -d ${VM_NAME}  /etc/os-release"  > ${VM_OS_RELEASE_FILE}
    VM_OS=$(cat ${VM_OS_RELEASE_FILE}  |  grep -E ^ID=  |  cut -d '"' -f 2)
    #VM_OS_VERSION=$(cat ${VM_OS_RELEASE_FILE}  |  grep -E ^VERSION_ID=  |  cut -d '"' -f 2)
    #
    VM_CONF_SRC_DIR="/tmp"
    #
    # hosts
    VM_HOSTS_DEST_DIR="/etc"
    VM_HOSTS_FILENAME="hosts"
    #
    F_GEN_HOSTS     > ${VM_CONF_SRC_DIR}/${VM_HOSTS_FILENAME}
    scp  -P ${KVM_HOST}  ${VM_CONF_SRC_DIR}/${VM_HOSTS_FILENAME}     ${KVM_SSH_USER}@${KVM_HOST}:${VM_CONF_SRC_DIR}/
    #
    # nic
    case ${VM_OS} in
        centos)
            #
            VM_NIC_CONF_DEST_DIR="/etc/sysconfig/network-scripts"
            VM_NIC_CONF_FILENAME="ifcfg-eth0"
            ;;
        ubuntu)
            case ${VM_OS_VERSION} in
                1*)
                    VM_NIC_CONF_DEST_DIR="/etc/network"
                    VM_NIC_CONF_FILENAME="interface"
                    ;;
                2*)
                    VM_NIC_CONF_DEST_DIR="/etc/netplan"
                    VM_NIC_CONF_FILENAME="00-installer-config.yaml"
                    ;;
                *)
                    VM_NIC_CONF_DEST_DIR="/etc/netplan"
                    VM_NIC_CONF_FILENAME="00-installer-config.yaml"
                    ;;
            esac
            ;;
        *)
            echo 这是啥，没搞${VM_OS}
            ;;
    esac
    #
    F_GEN_NIC_CONF  > ${VM_CONF_SRC_DIR}/${VM_NIC_CONF_FILENAME}
    scp  -P ${KVM_HOST}  ${VM_CONF_SRC_DIR}/${VM_NIC_CONF_FILENAME}  ${KVM_SSH_USER}@${KVM_HOST}:${VM_CONF_SRC_DIR}/
    #
    VM_SYSPREP_LOG_FILE="${LOG_HOME}/${SH_NAME}-sysprep.log--${VM_NAME}"
    > ${VM_SYSPREP_LOG_FILE}
    #
    ssh  -p ${KVM_SSH_PORT}  ${KVM_SSH_USER}@${KVM_HOST}  "virt-sysprep  \
        --copy-in ${VM_CONF_SRC_DIR}/${VM_HOSTS_FILENAME}:${VM_HOSTS_DEST_DIR}/  \
        --copy-in ${VM_CONF_SRC_DIR}/${VM_NIC_CONF_FILENAME}:${VM_NIC_CONF_DEST_DIR}/  \
        --hostname ${VM_NAME}.${VM_DOMAIN}  \
        -d ${VM_NAME}"  | tee ${VM_SYSPREP_LOG_FILE} 2>&1
    #
    if [ `grep -q 'ERROR' ${VM_SYSPREP_LOG_FILE}; echo $?` -eq 0 ]; then
        echo "【${VM_NAME}】sysprep，请检查！"
        exit 1
    fi
    #
done < ${VM_LIST_APPEND_1_TMP}


