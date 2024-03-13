#!/bin/bash
#############################################################################
# Create By: 猪猪侠
# License: GNU GPLv3
# Test On: CentOS 7
#############################################################################


# sh
SH_NAME=${0##*/}
SH_PATH=$( cd "$( dirname "$0" )" && pwd )
cd ${SH_PATH}



F_HELP()
{
    echo "
    用途：列出KVM上的虚拟机
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        $0  <-h|--help>
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
        $0  -h                   #--- 帮助
        $0                       #--- 列出KVM上的虚拟机
    "
}



if [ "x$1" = 'x-h' -o "x$1" = 'x--help' ]; then
    F_HELP
    exit
fi


# 现有vm
VM_LIST_EXISTED="/tmp/${SH_NAME}-vm.list.online"
virsh list --all | sed  '1,2d;s/[ ]*//;/^$/d'  > ${VM_LIST_EXISTED}


echo  "KVM虚拟机清单："
#echo "---------------------------------------------"
#awk '{printf "%3s : %-40s %s %s\n", NR, $2,$3,$4}'  ${VM_LIST_EXISTED}
#echo "---------------------------------------------"
awk '{printf "%s,%s %s\n", $2,$3,$4}'  ${VM_LIST_EXISTED} > /tmp/vm.list
${SH_PATH}/format_table.sh  -d ','  -t 'NAME,STATUS'  -f /tmp/vm.list


