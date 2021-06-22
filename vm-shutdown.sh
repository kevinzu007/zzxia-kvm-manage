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

# 本地env
VM_LIST="${SH_PATH}/list.csv"



F_HELP()
{
    echo "
    用途：shutdown虚拟机
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  <-q|--quiet>  [ [-f|--file {清单文件}] | [-S|--select] | [-A|--ARG {虚拟机1} {虚拟机2} ... {虚拟机n}] ]
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -f|--file      从文件选择虚拟机（默认），默认文件为【./list.csv】
            文件格式如下（字段之间用【,】分隔）：
            #VM_NAME,CPU(个),MEM(GB),NET名, IP1,IP_MASK1,GATEWAY1 ,DOMAIN,DNS1 DNS2
            v-192-168-1-2-nextcloud,2,4,br1, 192.168.1.2,24,192.168.11.1, zjlh.lan,192.168.11.3 192.168.11.4
            v-192-168-1-3-nexxxx,2,4,br1, 192.168.1.3,24,192.168.11.1, zjlh.lan,192.168.11.3
        -S|--select    从KVM中选择虚拟机
        -A|--ARG       从参数获取虚拟机
        -q|--quiet     静默方式
    示例:
        #
        $0  -h
        # 一般（默认从默认文件）
        $0                   #--- shutdown默认虚拟机清单文件【./list.csv】中的虚拟机
        # 从指定文件
        $0  -f my_vm.list    #--- shutdown虚拟机清单文件【my_vm.list】中的虚拟机
        # 我选择
        $0  -S               #--- shutdown我选择的虚拟机
        # 指定虚拟机
        $0  -A  vm1 vm2      #--- shutdown虚拟机【vm1、vm2】
        # 静默方式
        $0  -q               #--- shutdown默认虚拟机清单文件【./list.csv】中的虚拟机，用静默方式
        $0  -q  -f my_vm.list #--- shutdown虚拟机清单文件【my_vm.list】中的虚拟机，用静默方式
        $0  -q  -S           #--- shutdown我选择的虚拟机，用静默方式
        $0  -q  -A  vm1 vm2  #--- shutdown虚拟机【vm1、vm2】，用静默方式
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
TEMP=`getopt -o hf:SAq  -l help,file:,select,ARG,quiet -- "$@"`
if [ $? != 0 ]; then
    echo "参数不合法，退出"
    exit 1
fi
#
eval set -- "${TEMP}"


VM_LIST_FROM='file'
while true
do
    case "$1" in
        -h|--help)
            F_HELP
            exit
            ;;
        -f|--file)
            VM_LIST_FROM='file'
            VM_LIST=$2
            shift 2
            if [ ! -f "${VM_LIST}" ]; then
                echo -e "\n峰哥说：文件【${VM_LIST}】不存在，请检查！\n"
                exit 1
            fi
            ;;
        -S|--select)
            VM_LIST_FROM='select'
            shift
            ;;
        -A|--ARG)
            VM_LIST_FROM='arg'
            shift
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


# 现有vm
VM_LIST_ONLINE="/tmp/${SH_NAME}-vm.list.online"
virsh list --all | sed  '1,2d;s/[ ]*//;/^$/d'  > ${VM_LIST_ONLINE}


case "${VM_LIST_FROM}" in
    arg)
        ARG_NUM=$#
        if [ ${ARG_NUM} -eq 0 ]; then
            echo -e "\n峰哥说：缺少参数，请查看帮助！\n"
            exit 2
        fi
        for ((i=1;i<=ARG_NUM;i++))
        do
            VM_NAME=$1
            shift
            # 匹配？
            if [ `F_VM_SEARCH "${VM_NAME}" > /dev/null; echo $?` -ne 0 ]; then
                echo -e "\n峰哥说：虚拟机【${VM_NAME}】没找到，跳过！\n"
                continue
            fi
            #
            if [ "${QUIET}" = 'yes' ]; then
                virsh shutdown  ${VM_NAME}
            else
                echo "准备shutdown虚拟机【${VM_NAME}】"
                read  -t 30  -p "请确认，默认[n]，[y|n]：" ACK
                if [ "x${ACK}" = 'xy' ]; then
                    virsh shutdown  ${VM_NAME}
                else
                    echo "OK，跳过"
                fi
            fi
        done
        ;;
    file)
        #
        VM_LIST_TMP="${VM_LIST}.tmp"
        sed  -e '/^#/d' -e '/^$/d' -e '/^[ ]*$/d' ${VM_LIST} > ${VM_LIST_TMP}
        while read LINE
        do
            VM_NAME=`echo $LINE | cut -f 1 -d ,`
            VM_NAME=`echo $VM_NAME`
            # 匹配？
            if [ `F_VM_SEARCH "${VM_NAME}" > /dev/null; echo $?` -ne 0 ]; then
                echo -e "\n峰哥说：虚拟机【${VM_NAME}】没找到，跳过！\n"
                continue
            fi
            #
            if [ "${QUIET}" = 'yes' ]; then
                virsh shutdown  ${VM_NAME}
            else
                echo "准备shutdown虚拟机【${VM_NAME}】"
                read  -t 30  -p "请确认，默认[n]，[y|n]：" ACK
                if [ "x${ACK}" = 'xy' ]; then
                    virsh shutdown  ${VM_NAME}
                else
                    echo "OK，跳过"
                fi
            fi
        done < ${VM_LIST_TMP}
        ;;
    select)
        echo  "虚拟机清单："
        echo "---------------------------------------------"
        awk '{printf "%c : %-40s %s %s\n", NR+96, $2,$3,$4}'  ${VM_LIST_ONLINE}
        echo "---------------------------------------------"
        echo "请选择你想操作的虚拟机！"
        read -p "请输入（可以联系输入多个，不能有空格，如：def）："  ANSWER
        echo "OK！"
        echo "你选择的是：${ANSWER}"
        read -p "按任意键继续......"
        VM_SELECT_LIST=$(echo ${ANSWER})
        VM_SELECT_NUM=$(echo ${#VM_SELECT_LIST})
        #
        for ((i=0;i<VM_SELECT_NUM;i++))
        do
            VM_SELECT_No=$(echo ${VM_SELECT_LIST:${i}:1})
            VM_NAME=$(awk '{printf "%c : %-40s %s%s\n", NR+96, $2,$3,$4}' ${VM_LIST_ONLINE} | awk '/'^${VM_SELECT_No}'/{print $3}')
            #
            if [ "${QUIET}" = 'yes' ]; then
                virsh shutdown  ${VM_NAME}
            else
                echo "准备shutdown虚拟机【${VM_NAME}】"
                read  -t 30  -p "请确认，默认[n]，[y|n]：" ACK
                if [ "x${ACK}" = 'xy' ]; then
                    virsh shutdown  ${VM_NAME}
                else
                    echo "OK，跳过"
                fi
            fi
        done
        ;;
    *)
        echo  "参数错误，你私自修改脚本了"
        exit 1
        ;;
esac


