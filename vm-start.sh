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
#. ${SH_PATH}/kvm.env

# 本地env
VM_LIST="${SH_PATH}/list.csv"



F_HELP()
{
    echo "
    用途：启动虚拟机；设置虚拟机自动启动
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  [ <-s|--start>  <-a|--autostart> ]  [ [-f|--file <{清单文件}>] | [-S|--select] | [{虚拟机1} {虚拟机2} ... {虚拟机n}] ]
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -s|--start     启动虚拟机
        -a|--autostart 开启自动启动虚拟机
        -f|--file      从文件选择虚拟机，默认为【./list.csv】
            文件格式如下（字段之间用【,】分隔）：
            #VM_NAME,CPU(个),MEM(GB),NET名, IP1,IP_MASK1,GATEWAY1 ,DOMAIN,DNS1 DNS2
            v-192-168-1-2-nextcloud,2,4,br1, 192.168.1.2,24,192.168.11.1, zjlh.lan,192.168.11.3 192.168.11.4
            v-192-168-1-3-nexxxx,2,4,br1, 192.168.1.3,24,192.168.11.1, zjlh.lan,192.168.11.3
        -S|--select    从KVM中选择虚拟机
    示例:
        #
        $0  -h
        # 一般（从文件）
        $0  -s                   #--- 启动默认虚拟机清单文件【./list.csv】中的虚拟机
        $0  -s  -a               #--- 启动默认虚拟机清单文件【./list.csv】中的虚拟机，并设置为自动启动
        $0  -a                   #--- 自动启动默认虚拟机清单文件【./list.csv】中的虚拟机
        # 从指定文件
        $0  -s  -f my_vm.list    #--- 启动虚拟机清单文件【my_vm.list】中的虚拟机
        $0  -a  -f my_vm.list    #--- 自动启动虚拟机清单文件【my_vm.list】中的虚拟机
        $0  -s  -f               #--- 启动默认虚拟机清单文件【./list.csv】中的虚拟机
        # 我选择
        $0  -s  -S               #--- 启动我选择的虚拟机
        $0  -a  -S               #--- 自动启动我选择的虚拟机
        # 指定虚拟机
        $0  -s  vm1 vm2          #--- 启动虚拟机【vm1、vm2】
        $0  -a  vm1 vm2          #--- 自动启动虚拟机【vm1、vm2】
    "
}


# 参数检查
TEMP=`getopt -o hsaf::S  -l help,start,autostart,file::select -- "$@"`
if [ $? != 0 ]; then
    echo "参数不合法，退出"
    F_HELP
    exit 1
fi
#
eval set -- "${TEMP}"


VM_START='no'
VM_AUTOSTART='no'
VM_LIST_FROM='arg'
while true
do
    case "$1" in
        -h|--help)
            F_HELP
            exit
            ;;
        -s|--start)
            VM_START='yes'
            shift
            ;;
        -a|--autostart)
            VM_AUTOSTART='yes'
            shift
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
            #
            if [ "${VM_START}" = 'yes' ]; then
                virsh start  ${VM_NAME}
            fi
            if [ "${VM_START}" = 'yes' ]; then
                virsh autostart  ${VM_NAME}
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
            #
            if [ "${VM_START}" = 'yes' ]; then
                virsh start  ${VM_NAME}
            fi
            if [ "${VM_START}" = 'yes' ]; then
                virsh autostart  ${VM_NAME}
            fi
        done < ${VM_LIST_TMP}
        ;;
    select)
        VM_LIST_ONLINE="/tmp/${SH_NAME}-vm.list"
        echo  "虚拟机清单："
        echo "---------------------------------------------"
        virsh list --all > ${VM_LIST_ONLINE}
        sed -i -e '1,2d' -e '/^$/d' -e '/^[ ]*$/d'  ${VM_LIST_ONLINE}
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
        for ((i=0;i<VM_RM_NUM;i++))
        do
            VM_SELECT_No=$(echo ${VM_SELECT_LIST:${i}:1})
            VM_NAME=$(awk '{printf "%c : %-40s %s%s\n", NR+96, $2,$3,$4}' ${VM_LIST_ONLINE} | awk '/'^${VM_SELECT_No}'/{print $3}')
            #
            if [ "${VM_START}" = 'yes' ]; then
                virsh start  ${VM_NAME}
            fi
            if [ "${VM_START}" = 'yes' ]; then
                virsh autostart  ${VM_NAME}
            fi
        done
        ;;
    *)
        echo  "参数错误，你私自修改脚本了"
        exit 1
        ;;
esac


