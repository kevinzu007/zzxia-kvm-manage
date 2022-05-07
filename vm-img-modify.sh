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
#QUIET=
#TEMPLATE_VM_LV=
#TEMPLATE_VM_NET_1_FILE=



F_HELP()
{
    echo "
    用途：修改KVM虚拟机主机名及网卡信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  <-q|--quiet>  [ {VM_NAME}  {NEW_IP}  {NEW_IP_MASK}  {NEW_GATEWAY} ]  <{NEW_DOMAIN}>  <{NEW_DNS1}<,{NEW_DNS2}>>
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -q|--quiet     静默方式
    示例:
        #
        $0  -h        #--- 帮助
        # 一般
        $0  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3,192.168.11.4
        $0  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3
        $0  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1
        # 静默方式
        $0  -q  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3,192.168.11.4
    "
}


# 用法：F_VM_SEARCH 虚拟机名
F_VM_SEARCH ()
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
    done < ${VM_LIST_ONLINE}
    #
    if [ "${GET_IT}" = 'YES' ]; then
        echo -e "${F_VM_STATUS}"
        return 0
    else
        return 1
    fi
}



TEMP=`getopt -o hq  -l help,quiet -- "$@"`
if [ $? != 0 ]; then
    echo -e "\n峰哥说：参数不合法，请查看帮助【$0 --help】\n"
    exit 1
fi
#
eval set -- "${TEMP}"


while true
do
    case $1 in
        -h|--help)
            F_HELP
            exit
            ;;
        -q|--quiet)
            QUIET='yes'
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done



if [ $# -lt 4 ] ; then
    echo -e "\n缺少参数，请检查！\n"
    exit 1
fi


VM_NAME=${1}
NEW_HOSTNAME=${VM_NAME}
NEW_IP=${2}
NEW_IP_MASK=${3}
NEW_GATEWAY=${4}
NEW_DOMAIN=${5}
NEW_FQDN="${NEW_HOSTNAME}.${NEW_DOMAIN}"
NEW_DNS="${6}"
NEW_DNS1=`echo ${NEW_DNS} | cut -d "," -f 1`
NEW_DNS2=`echo ${NEW_DNS} | cut -d "," -f 2`


MOUNT_PATH='/mnt/img-disk-1'
if [ ! -d "${MOUNT_PATH}" ]; then
    mkdir -p "${MOUNT_PATH}"
fi


# 现有vm
VM_LIST_ONLINE="/tmp/${SH_NAME}-vm.list.online"
virsh list --all | sed  '1,2d;s/[ ]*//;/^$/d'  > ${VM_LIST_ONLINE}


# 匹配？
if [ `F_VM_SEARCH  "${VM_NAME}" > /dev/null; echo $?` -ne 0 ]; then
    echo -e "\n峰哥说：虚拟机【${VM_NAME}】不存在，请检查\n"
    exit 1
fi

if [ "`F_VM_SEARCH ${VM_NAME}`" = 'running' ]; then
    echo -e "\n峰哥说：虚拟机【${VM_NAME}】已启动，请先shutdown\n"
    exit 1
fi


echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "------------------------------------------------"
echo "待修改虚拟机名称：${VM_NAME}"
echo "新FQDN名：${NEW_FQDN}"
echo "新IP：${NEW_IP}"
echo "新IP掩码：${NEW_IP_MASK}"
echo "新网关：${NEW_GATEWAY}"
echo "新DNS：${NEW_DNS1} ${NEW_DNS2}"
echo "挂载的逻辑卷：${TEMPLATE_VM_LV}"
echo "挂载路径：${MOUNT_PATH}"
echo "------------------------------------------------"

#
if [ "${QUIET}" = 'no' ] ; then
    echo "以上信息正确吗？"
    echo "如果正确，请输入：'"y"'"
    read -p "请输入："  ANSWER
    if [ ${ANSWER}x != "y"x ] ; then
        echo "OK，请重新设置参数"
        exit 1
    fi
fi


which guestmount >/dev/null 2>&1
GUESTFS_ERR=$?
if [ ${GUESTFS_ERR} -ne 0 ]; then
    echo -e "\n峰哥说：请先安装guestfs，已退出！\n"
    exit 1
else
    #IMG_PATH='/var/lib/libvirt/images'
    #guestmount -a "${IMG_PATH}/${VM_NAME}.img" -w -m ${TEMPLATE_VM_LV} ${MOUNT_PATH}
    guestmount -d ${VM_NAME} -w -m ${TEMPLATE_VM_LV} ${MOUNT_PATH}
fi


echo "mount DIRECTORY list : ------------------------------------------------"
ls ${MOUNT_PATH}

echo "------------------------------------------------"
# hostname
sed -i  "s/.*/${NEW_FQDN}/"  "${MOUNT_PATH}/etc/hostname"
# hosts
sed -i  "/${NEW_FQDN}/d"  "${MOUNT_PATH}/etc/hosts"
echo  "${NEW_IP} ${NEW_FQDN}" >> "${MOUNT_PATH}/etc/hosts"
# machine-id
cat /dev/null  > "${MOUNT_PATH}/etc/machine-id"
# ssh_host_key
rm -f  ${MOUNT_PATH}/etc/ssh/ssh_host_*
# 关闭IPv6
sed -i  's/IPV6INIT=.*/IPV6INIT="no"/'  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"

# NET
sed -i  '/^UUID.*/s/^/#/'  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"
grep -q 'IPADDR='  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
    && sed -i  "s/IPADDR=.*/IPADDR=${NEW_IP}/"  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
    || echo "IPADDR=${NEW_IP}" >> "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"
grep -q '^PREFIX=' "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
    && sed -i  "s/^PREFIX=.*/PREFIX=${NEW_IP_MASK}/"  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
    || echo "PREFIX=${NEW_IP_MASK}" >> "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"
grep -q 'GATEWAY=' "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
    && sed -i  "s/GATEWAY=.*/GATEWAY=${NEW_GATEWAY}/"  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
    || echo "GATEWAY=${NEW_GATEWAY}" >> "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"
## 可选
# 域名
if [ -n "${NEW_DOMAIN}" ]; then
    grep -q 'DOMAIN=' "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
        && sed -i  "s/DOMAIN=.*/DOMAIN=${NEW_DOMAIN}/"  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
        || echo "DOMAIN=${NEW_DOMAIN}" >> "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"
fi
# DNS1
if [ -n "${NEW_DNS1}" ]; then
    grep -q '^DNS1=' "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
        && sed -i  "s/^DNS1=.*/DNS1=${NEW_DNS1}/"  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
        || echo "DNS1=${NEW_DNS1}" >> "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"
fi
# DNS2
if [ -n "${NEW_DNS2}" ]; then
    grep -q '^DNS2=' "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
        && sed -i  "s/^DNS2=.*/DNS2=${NEW_DNS2}/"  "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}" \
        || echo "DNS2=${NEW_DNS2}" >> "${MOUNT_PATH}/${TEMPLATE_VM_NET_1_FILE}"
fi

SED_ERR=$?
echo "sed错误代码 : ${SED_ERR}"
if [ ${SED_ERR} -eq 0 ] ; then
    echo "恭喜修改成功！"
else
    echo "修改失败，请检查！"
fi
echo "------------------------------------------------"

#---取消挂载
guestunmount ${MOUNT_PATH}


