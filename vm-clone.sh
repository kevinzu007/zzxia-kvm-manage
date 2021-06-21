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
#VM_IMG_PATH=
#VM_XML_PATH=
#TEMPLATE_VM_NET_ON_KVM=
#QUIET=

# 本地env
VM_LIST="${SH_PATH}/list.csv"



F_HELP()
{
    echo "
    用途：KVM上虚拟机克隆，并修改相关信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    依赖：
        ./vm-img-modify.sh
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  <-f|--file {清单文件}>  < -q|--quiet  [-t|--template {虚拟机模板}] >
        $0  <-f|--file {清单文件}>  <-t|--template {虚拟机模板}>
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -f|--file      虚拟机清单文件，默认为【./list.csv】
            文件格式如下（字段之间用【,】分隔）：
            #VM_NAME,CPU(个),MEM(GB),NET名, IP1,IP_MASK1,GATEWAY1 ,DOMAIN,DNS1 DNS2
            v-192-168-1-2-nextcloud,2,4,br1, 192.168.1.2,24,192.168.11.1, zjlh.lan,192.168.11.3 192.168.11.4
            v-192-168-1-3-nexxxx,2,4,br1, 192.168.1.3,24,192.168.11.1, zjlh.lan,192.168.11.3
        -q|--quiet     静默方式
        -t|--templat   指定虚拟机模板
    示例:
        #
        $0  -h
        # 一般
        $0                       #--- 默认虚拟机清单文件【./list.csv】，非静默方式，手动选择模板
        $0  -t v-centos-1        #--- 默认虚拟机清单文件【./list.csv】，非静默方式，基于模板【v-centos-1】创建
        # 指定vm清单文件
        $0  -f vm.list                      #--- 使用虚拟机清单文件【vm.list】，非静默方式，手动选择模
        $0  -f vm.list  -t v-centos-1       #--- 使用虚拟机清单文件【vm.list】，非静默方式，基于模板【v-centos-1】创建
        # 静默方式
        $0  -q  -t v-centos-1               #--- 默认虚拟机清单文件【./list.csv】，静默方式，基于模板【v-centos-1】创建
        $0  -q  -t v-centos-1  -f vm.list   #--- 使用虚拟机清单文件【vm.list】，静默方式，基于模板【v-centos-1】创建
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



# 参数检查
TEMP=`getopt -o hf:qt:  -l help,file:,quiet,template: -- "$@"`
if [ $? != 0 ]; then
    echo "参数不合法，退出"
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
        -f|--file)
            VM_LIST=$2
            shift 2
            ;;
        -t|--template)
            VM_TEMPLATE=$2
            shift 2
            ;;
        -q|--quiet)
            QUIET='yes'
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "参数不合法！【请查看帮助：\$0 --help】"
            exit 1
            ;;
    esac
done


# vm清单
if [ ! -f "${VM_LIST}" ] ; then
    echo -e "\n峰哥说：${VM_LIST}文件不存在，请检查！\n"
    exit 2
fi
#
VM_LIST_TMP="${VM_LIST}.tmp"
sed  -e '/^#/d' -e '/^$/d' -e '/^[ ]*$/d' ${VM_LIST}  > ${VM_LIST_TMP}


# 现有vm
VM_LIST_ONLINE="/tmp/${SH_NAME}-vm.list.online"
virsh list --all | sed  '1,2d;s/[ ]*//;/^$/d'  > ${VM_LIST_ONLINE}



# 模板
if [ -n "${VM_TEMPLATE}" ]; then
    if [ `F_VM_SEARCH  "${VM_TEMPLATE}" > /dev/null; echo $?` -ne 0 ]; then
        echo -e "\n峰哥说：模板【${VM_TEMPLATE}】不存在，请检查！\n"
        exit 1
    fi
else
    if [ "${QUIET}" = "no" ]; then
        echo  "虚拟机模板："
        echo "---------------------------------------------"
        awk '{printf "%c : %-40s %s %s\n", NR+96,$2,$3,$4}' ${VM_LIST_ONLINE}
        echo "---------------------------------------------"
        echo "请选择你想使用的模版，如果模版机在“running”状态，可能会clone失败！"
        read -p "请输入："  ANSWER

        # 获取选择的项并回显
        VM_TEMPLATE=$(awk '{printf "%c:%s\n", NR+96, $2}' ${VM_LIST_ONLINE} | awk -F ":"  "/^${ANSWER}/{print \$2}")
        echo "OK！"
        echo "你选择的是：${VM_TEMPLATE}"
        read -p "按任意键继续......"
    else
        #
        if [ -z "${VM_TEMPLATE}" ]; then
            echo -e "\n峰哥说：在静默方式下必须提供参数【-t|--template】！\n"
            exit 2
        fi
    fi
fi



echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "新虚拟机清单："
echo "---------------------------------------------"
cat ${VM_LIST_TMP}
echo "---------------------------------------------"
#
if [ "${QUIET}" = 'no' ]; then
    echo "以上信息正确吗？如果正确，请输入 "'y'""
    read -p "请输入："  ANSWER
else
    ANSWER='y'
fi
#
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
        echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        echo "源模板： ${VM_TEMPLATE}"
        echo "新虚拟机名称：${VM_NAME}"
        echo "新虚拟机CPU(核)： ${VM_CPU}"
        echo "新虚拟机内存(GiB)：${VM_MEM}"
        echo "新虚拟机网卡：${VM_NET}"
        echo "新虚拟机IMG： ${VM_IMG_PATH}/${VM_IMG}"
        echo "新虚拟机XML： ${VM_XML_PATH}/${VM_XML}"
        echo "---------------------------------------------"
        # 是否已存在？
        if [ `F_VM_SEARCH  "${VM_NAME}" > /dev/null; echo $?` -eq 0 ]; then
            echo -e "\n峰哥说：虚拟机【${VM_NAME}】已存在，跳过\n"
            continue
        fi
        # clone
        virt-clone -o ${VM_TEMPLATE}  -n ${VM_NAME}  -f ${VM_IMG_PATH}/${VM_IMG}  > /tmp/${SH_NAME}-clone-${VM_NAME}.log 2>&1
        if [ `grep -q 'ERROR' /tmp/${SH_NAME}-clone-${VM_NAME}.log; echo $?` -eq 0 ]; then
            echo "【${VM_NAME}】clone error, 请检查!"
            exit 1
        fi
        sed -i  s/"<vcpu.*vcpu>"/"<vcpu placement='static'>${VM_CPU}<\/vcpu>"/g  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"<memory.*memory>"/"<memory unit='GiB'>${VM_MEM}<\/memory>"/g  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"<currentMemory.*currentMemory>"/"<currentMemory unit='GiB'>${VM_MEM}<\/currentMemory>"/g  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"${TEMPLATE_VM_NET_ON_KVM}"/"${VM_NET}"/g  "${VM_XML_PATH}/${VM_XML}"
        # On CentOS7.1 BUG修复，参考：https://bugs.centos.org/view.php?id=10402
        #sed -i  s/'domain-m-centos-2c-4g'/"domain-${VM_NAME}"/  "${VM_XML_PATH}/${VM_XML}"
        sed -i  s/"domain-${VM_TEMPLATE}"/"domain-${VM_NAME}"/  "${VM_XML_PATH}/${VM_XML}"
        #重新define虚拟机
        virsh define  "${VM_XML_PATH}/${VM_XML}"
        echo "---------------------------------------------"
        # 修改vm image
        ./vm-img-modify.sh  --quiet  "${VM_NAME}"  "${VM_IP}"  "${VM_IP_MASK}"  "${VM_GATEWAY}"  "${VM_DOMAIN}"  "${VM_DNS1}"  "${VM_DNS2}"
    done < ${VM_LIST_TMP}
    ;;
*)
    echo "小子，好好检查吧！"
    exit 4
esac

echo  "OK！"


