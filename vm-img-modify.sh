#!/bin/bash
#############################################################################
# Create By: zhf_sy
# License: GNU GPLv3
# Test On: CentOS 7
#############################################################################


# 虚拟机模板ENV（根据实际情况修改）
## 【/】逻辑卷
#MODEL_VM_LV='/dev/m-ubu-1604-vg/root'
#MODEL_VM_LV='/dev/mapper/centos-root'
MODEL_VM_LV='/dev/mapper/cl-root'
## 网卡
MODEL_VM_NET_1_FILE='/etc/sysconfig/network-scripts/ifcfg-eth0'   #--- centos 7



F_HELP()
{
    echo "
    用途：KVM虚拟机信息修改（主机名、IP、IP子网掩码、网关、域名、DNS）
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  [{VM_NAME}  {NEW_IP}  {NEW_IP_MASK}  {NEW_GATEWAY}]  {NEW_DOMAIN}  <{NEW_DNS1}>  <{NEW_DNS2}>
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
    示例:
        #
        $0  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3  192.168.11.4
        $0  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1
    "
}



if [ $# -lt 4 ] ; then
    F_HELP
    exit 1
fi



VM_NAME=${1}
NEW_HOSTNAME=${VM_NAME}
NEW_IP=${2}
NEW_IP_MASK=${3}
NEW_GATEWAY=${4}
NEW_DOMAIN=${5}
NEW_FQDN="${NEW_HOSTNAME}.${NEW_DOMAIN}"
NEW_DNS1="${6}"
NEW_DNS2="${7}"


MOUNT_PATH='/mnt/img-disk-1'
if [ ! -d "${MOUNT_PATH}" ]; then
    mkdir -p "${MOUNT_PATH}"
fi




echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "------------------------------------------------"
echo "待修改虚拟机名称：${VM_NAME}"
echo "新FQDN名：${NEW_FQDN}"
echo "新IP：${NEW_IP}"
echo "新IP掩码：${NEW_IP_MASK}"
echo "新网关：${NEW_GATEWAY}"
echo "新DNS：${NEW_DNS1} ${NEW_DNS2}"
echo "挂载的逻辑卷：${MODEL_VM_LV}"
echo "挂载路径：${MOUNT_PATH}"
echo "------------------------------------------------"

#---如果不是在vm-clone.sh中调用运行，则添加确认环节
ps -ef | grep -v 'grep' | grep vm-clone.sh > /dev/null 2>&1
if [ $? -ne 0 ] ; then
    echo "以上信息正确吗？"
    echo "如果正确，请输入：'"y"'"
    read -p "请输入："  ANSWER
    if [ ${ANSWER}x != "y"x ] ; then
        echo "请重新设置参数"
        exit 1
    fi
fi



which guestmount >/dev/null 2>&1
GUESTFS_ERR=$?
if [ ${GUESTFS_ERR} -ne 0 ]; then
    echo "请先安装guestfs，即将退出！"
    exit 1
else
    #IMG_PATH='/var/lib/libvirt/images'
    #guestmount -a "${IMG_PATH}/${VM_NAME}.img" -w -m ${MODEL_VM_LV} ${MOUNT_PATH}
    guestmount -d ${VM_NAME} -w -m ${MODEL_VM_LV} ${MOUNT_PATH}
fi


echo "mount DIRECTORY list : ------------------------------------------------"
ls ${MOUNT_PATH}

echo "------------------------------------------------"
# HOSTNAME
sed -i  "s/.*/${NEW_FQDN}/"  "${MOUNT_PATH}/etc/hostname"
# machine-id
cat /dev/null  > "${MOUNT_PATH}/etc/machine-id"
# ssh_host_key
rm -f  ${MOUNT_PATH}/etc/ssh/ssh_host_*
# 关闭IPv6
sed -i  's/IPV6INIT=.*/IPV6INIT="no"/'  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"
# NET
sed -i  '/^UUID.*/s/^/#/'  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"
grep -q 'IPADDR='  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    && sed -i  "s/IPADDR=.*/IPADDR=${NEW_IP}/"  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    || echo "IPADDR=${NEW_IP}" >> "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"
grep -q '^PREFIX=' "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    && sed -i  "s/^PREFIX=.*/PREFIX=${NEW_IP_MASK}/"  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    || echo "PREFIX=${NEW_IP_MASK}" >> "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"
grep -q 'GATEWAY=' "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    && sed -i  "s/GATEWAY=.*/GATEWAY=${NEW_GATEWAY}/"  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    || echo "GATEWAY=${NEW_GATEWAY}" >> "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"
grep -q 'DOMAIN=' "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    && sed -i  "s/DOMAIN=.*/DOMAIN=${NEW_DOMAIN}/"  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    || echo "DOMAIN=${NEW_DOMAIN}" >> "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"
grep -q '^DNS1=' "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    && sed -i  "s/^DNS1=.*/DNS1=${NEW_DNS1}/"  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    || echo "DNS1=${NEW_DNS1}" >> "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"
grep -q '^DNS2=' "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    && sed -i  "s/^DNS2=.*/DNS2=${NEW_DNS2}/"  "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}" \
    || echo "DNS2=${NEW_DNS2}" >> "${MOUNT_PATH}/${MODEL_VM_NET_1_FILE}"


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

