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
#VM_IMG_PATH='/var/lib/libvirt/images'    #--- 新虚拟机文件路径
#VM_XML_PATH='/etc/libvirt/qemu'          #--- 虚拟机配置文件路径，系统默认路径


F_HELP()
{
    echo "
    用途：KVM上虚拟机克隆，并修改相关信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    注意：本脚本在centos 7上测试通过，需要vm-img-modify.sh配合
    用法：
        $0  [-h|--help]
        $0  [-f|--file]
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -f|--file      虚拟机清单文件
            文件格式如下（字段之间用【,】分隔）：
            #VM_NAME,CPU(个),MEM(GB),NET名, IP1,IP_MASK1,GATEWAY1 ,DOMAIN,DNS1 DNS2
            v-192-168-1-2-nextcloud,2,4,br1, 192.168.1.2,24,192.168.11.1, zjlh.lan,192.168.11.3 192.168.11.4
            v-192-168-1-3-nexxxx,2,4,br1, 192.168.1.3,24,192.168.11.1, zjlh.lan,192.168.11.3
    示例:
        #
        $0  -f vm.list
    "
}


# 参数检查
TEMP=`getopt -o hf:  -l help,file: -- "$@"`
if [ $? != 0 ]; then
    echo "参数不合法，退出"
    F_HELP
    exit 1
fi
#
eval set -- "${TEMP}"


case "$1" in
    -h|--help)
        F_HELP
        exit
        ;;
    -f|--file)
        VM_LIST=$2
        shift 2
        ;;
esac



if [ ! -f "${VM_LIST}" ] ; then
    echo -e "\n峰哥说：${VM_LIST}文件不存在，请检查！\n"
    exit 2
fi


NEW_VM_LIST='/tmp/new_vm.list'
sed  -e '/^#/d' -e '/^$/d' -e '/^[ ]*$/d' ${VM_LIST} >${NEW_VM_LIST}

echo  "虚拟机模板："
echo "---------------------------------------------"
virsh list --all > /tmp/vm.list
sed -i '1,2d;s/[ ]*//;/^$/d'  /tmp/vm.list
awk '{printf "%c : %-40s %s %s\n", NR+96, $2,$3,$4}' /tmp/vm.list
echo "---------------------------------------------"
echo "请选择你想使用的模版，如果模版机在“running”状态，可能会clone失败！"
read -p "请输入："  ANSWER

# 获取选择的项并回显
VM_MODEL=$(awk '{printf "%c:%s\n", NR+96, $2}' /tmp/vm.list | awk -F ":"  "/^${ANSWER}/{print \$2}")
echo "OK！"
echo "你选择的是：${VM_MODEL}"
read -p "按任意键继续......"

echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "新虚拟机清单："
echo "---------------------------------------------"
cat ${NEW_VM_LIST}
echo "---------------------------------------------"
echo "以上信息正确吗？如果正确，请输入 "'y'""
read -p "请输入："  ANSWER
case "${ANSWER}" in
y)
    while read LINE
    do
        VM_NAME=`echo $LINE | cut -f 1 -d ,`
        VM_NAME=`echo $VM_NAME`
        VM_IMG="${VM_NAME}.img"
        VM_XML="${VM_NAME}.xml"
        VM_CPU=`echo $LINE | cut -f 2 -d ,`
        VM_CPU=`echo $VM_CPU`
        VM_MEM=`echo $LINE | cut -f 3 -d ,`
        VM_MEM=`echo $VM_MEM`
        VM_NET=`echo $LINE | cut -f 4 -d ,`
        VM_NET=`echo $VM_NET`
        echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        echo "源模板： ${VM_MODEL}"
        echo "新虚拟机名称：${VM_NAME}"
        echo "新虚拟机CPU(核)： ${VM_CPU}"
        echo "新虚拟机内存(GiB)：${VM_MEM}"
        echo "新虚拟机网卡：${VM_NET}"
        echo "新虚拟机IMG： ${VM_IMG_PATH}/${VM_IMG}"
        echo "新虚拟机XML： ${VM_XML_PATH}/${VM_XML}"
        echo "---------------------------------------------"
        echo "OK！"
        virt-clone -o ${VM_MODEL}  -n ${VM_NAME}  -f ${VM_IMG_PATH}/${VM_IMG}
        CLONE_ERR=$?
        if [ ${CLONE_ERR} != 0 ]; then
            echo "clone error, 请检查!"
            exit 1
        fi
        sed -i  s/"<vcpu.*vcpu>"/"<vcpu placement='static'>${VM_CPU}<\/vcpu>"/g  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"<memory.*memory>"/"<memory unit='GiB'>${VM_MEM}<\/memory>"/g  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"<currentMemory.*currentMemory>"/"<currentMemory unit='GiB'>${VM_MEM}<\/currentMemory>"/g  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"br1"/"${VM_NET}"/g  "${VM_XML_PATH}/${VM_XML}"
        # On CentOS7.1 BUG修复，参考：https://bugs.centos.org/view.php?id=10402
        #sed -i  s/'domain-m-centos-2c-4g'/"domain-${VM_NAME}"/  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"domain-${VM_MODEL}"/"domain-${VM_NAME}"/  "${VM_XML_PATH}/${VM_XML}"
        #重新define虚拟机
        virsh define  "${VM_XML_PATH}/${VM_XML}"
    done<${NEW_VM_LIST}
    ;;
*)
    echo "小子，好好检查吧！"
    exit 4
esac

echo  "虚拟机创建完成，请检查输出是否有错误"
echo  "OK！"



echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "你已进入虚拟机信息修改环节，如果虚拟机创建无错误信息，请输入 "'y'""
read -p "请输入："  ANSWER
if [ ! -x ./vm-img-modify.sh ] ; then
    echo "找不到文件：./vm-img-modify.sh，请检查文件是否存在，是否与" $0 "的路径相同"
    exit 5
fi

case "${ANSWER}" in
y)
    while read LINE
    do
        VM_NAME=`echo $LINE | cut -f 1 -d ,`
        VM_NAME=`echo ${VM_NAME}`    #---去掉两边的空格
        VM_IP=`echo $LINE | cut -f 5 -d ,`
        VM_IP=`echo ${VM_IP}`
        VM_IP_MASK=`echo $LINE | cut -f 6 -d ,`
        VM_IP_MASK=`echo ${VM_IP_MASK}`
        VM_GATEWAY=`echo $LINE | cut -f 7 -d ,`
        VM_GATEWAY=`echo ${VM_GATEWAY}`
        VM_DOMAIN=`echo $LINE | cut -f 8 -d ,`
        VM_DOMAIN=`echo ${VM_DOMAIN}`
        VM_DNS=`echo $LINE | cut -f 9 -d ,`
        VM_DNS=`echo ${VM_DNS}`
        VM_DNS1=`echo ${VM_DNS} | cut -d " " -f 1`
        VM_DNS2=`echo ${VM_DNS} | cut -d " " -f 2`
        ./vm-img-modify.sh  "${VM_NAME}"  "${VM_IP}"  "${VM_IP_MASK}"  "${VM_GATEWAY}"  "${VM_DOMAIN}"  "${VM_DNS1}"  "${VM_DNS2}"
    done<${NEW_VM_LIST}
    ;;
*)
    echo "小子，好好检查你的虚拟机文件清单吧！"
    exit 6
esac



