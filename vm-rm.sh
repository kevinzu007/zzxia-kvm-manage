#!/bin/bash
#############################################################################
# Create By: 猪猪侠
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
#QUIET=

# 本地env
VM_LIST="${SH_PATH}/my_vm.list"



F_HELP()
{
    echo "
    用途：删除虚拟机
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  [-l|--list]
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
        -l|--list      列出KVM上的虚拟机
        -f|--file      从文件选择虚拟机（默认），默认文件为【./my_vm.list】，请基于【my_vm.list.sample】创建
        -S|--select    从KVM中选择虚拟机
        -A|--ARG       从参数获取虚拟机
        -q|--quiet     静默方式
    示例:
        #
        $0  -h               #--- 帮助
        $0  -l               #--- 列出KVM上的虚拟机
        # 一般（默认从默认文件）
        $0                   #--- 删除默认虚拟机清单文件【./my_vm.list】中的虚拟机
        # 从指定文件
        $0  -f xxx.list      #--- 删除虚拟机清单文件【xxx.list】中的虚拟机
        # 我选择
        $0  -S               #--- 删除我选择的虚拟机
        # 指定虚拟机
        $0  -A  vm1 vm2      #--- 删除虚拟机【vm1、vm2】
        # 静默方式
        $0  -q               #--- 删除默认虚拟机清单文件【./my_vm.list】中的虚拟机，用静默方式
        $0  -q  -f xxx.list  #--- 删除虚拟机清单文件【xxx.list】中的虚拟机，用静默方式
        $0  -q  -S           #--- 删除我选择的虚拟机，用静默方式
        $0  -q  -A  vm1 vm2  #--- 删除虚拟机【vm1、vm2】，用静默方式
    "
}


# 用法：F_SEARCH_EXISTED_VM 虚拟机名
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


# 用法：F_RM_VM  虚拟机名
F_RM_VM ()
{
    F_VM_NAME=$1
    echo "------------------------------"
    echo "删除虚拟机：$F_VM_NAME ......"

    # force shutdown
    if [ "`F_SEARCH_EXISTED_VM $F_VM_NAME`" = 'running' ]; then
        virsh destroy "${F_VM_NAME}"
    fi

    # rm img
    N=$( virsh  dumpxml  --domain "${F_VM_NAME}"  | grep  "<disk type='file' device='disk'>" | wc -l )
    for ((j=1;j<=N;j++));
    do
        IMG_FILE=$( virsh  dumpxml  --domain "${F_VM_NAME}"  | grep -A2  "<disk type='file' device='disk'>" | sed -n '3p' | awk -F "'" '{print $2}' )
        #
        if [ "${QUIET}" = "yes"  -a  -n "${IMG_FILE}" ]; then
            rm  -f "${IMG_FILE}"
            echo 'OK，已删除'
        elif [ "${QUIET}" != "yes"  -a  -n "${IMG_FILE}" ]; then
            read -t 30 -p "重要提示：需要删除虚拟机镜像文件【${IMG_FILE}】，默认[no]，[yes|no]：" AK
            if [ "x${AK}" = 'xyes' ]; then
                rm  -f "${IMG_FILE}"
                echo 'OK，已删除'
            else
                echo -e "\nOK，跳过\n"
            fi
        fi
    done
    # undefine VM ,this will delete xml
    virsh undefine "${F_VM_NAME}"
}



# 参数检查
TEMP=$(getopt -o hlf:SAq  -l help,list,file:,select,ARG,quiet -- "$@") || {
    echo -e "\n猪猪侠警告：参数不合法，请查看帮助【$0 --help】\n"
    exit 1
}
#
eval set -- "${TEMP}" || {
    echo -e "\n猪猪侠警告：参数设置失败！\n" >&2
    exit 1
}


# 现有vm
VM_LIST_EXISTED="/tmp/${SH_NAME}-vm.list.online"
virsh list --all | sed  '1,2d;s/[ ]*//;/^$/d'  > ${VM_LIST_EXISTED}


VM_LIST_FROM='file'
while true
do
    case "$1" in
        -h|--help)
            F_HELP
            exit
            ;;
        -l|--list)
            echo  "KVM虚拟机清单："
            #echo "---------------------------------------------"
            #awk '{printf "%3s : %-40s %s %s\n", NR, $2,$3,$4}'  ${VM_LIST_EXISTED}
            #echo "---------------------------------------------"
            awk '{printf "%s,%s %s\n", $2,$3,$4}'  ${VM_LIST_EXISTED} > /tmp/vm.list
            ${SH_PATH}/format_table.sh  -d ','  -t 'NAME,STATUS'  -f /tmp/vm.list
            exit
            ;;
        -f|--file)
            VM_LIST_FROM='file'
            VM_LIST=$2
            shift 2
            if [ ! -f "${VM_LIST}" ]; then
                echo -e "\n猪猪侠警告：文件【${VM_LIST}】不存在，请检查！\n"
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
            echo -e "\n猪猪侠警告：未知参数，请查看帮助【$0 --help】\n"
            exit 1
            ;;
    esac
done


case "${VM_LIST_FROM}" in
    arg)
        ARG_NUM=$#
        if [ ${ARG_NUM} -eq 0 ]; then
            echo -e "\n猪猪侠警告：缺少参数，请查看帮助！\n"
            exit 2
        fi
        for ((i=1;i<=ARG_NUM;i++))
        do
            VM_NAME=$1
            shift
            # 匹配？
            if [ `F_SEARCH_EXISTED_VM "${VM_NAME}" > /dev/null; echo $?` -ne 0 ]; then
                echo -e "\n猪猪侠警告：虚拟机【${VM_NAME}】没找到，跳过！\n"
                continue
            fi
            #
            if [ "${QUIET}" = 'yes' ]; then
                F_RM_VM  ${VM_NAME}
            else
                echo "准备删除虚拟机【${VM_NAME}】"
                read  -t 30  -p "请确认，默认[n]，[y|n]：" ACK
                if [ "x${ACK}" = 'xy' ]; then
                    F_RM_VM  ${VM_NAME}
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
        while read -u 3 LINE
        do
            VM_NAME=`echo $LINE | cut -f 2 -d '|'`
            VM_NAME=`echo $VM_NAME`
            # 匹配？
            if [ `F_SEARCH_EXISTED_VM "${VM_NAME}" > /dev/null; echo $?` -ne 0 ]; then
                echo -e "\n猪猪侠警告：虚拟机【${VM_NAME}】没找到，跳过！\n"
                continue
            fi
            #
            if [ "${QUIET}" = 'yes' ]; then
                F_RM_VM  ${VM_NAME}
            else
                echo "准备删除虚拟机【${VM_NAME}】"
                read  -t 30  -p "请确认，默认[n]，[y|n]：" ACK
                if [ "x${ACK}" = 'xy' ]; then
                    F_RM_VM  ${VM_NAME}
                else
                    echo "OK，跳过"
                fi
            fi
        done 3< ${VM_LIST_TMP}
        ;;
    select)
        echo  "虚拟机清单："
        echo "---------------------------------------------"
        awk '{printf "%c : %-40s %s %s\n", NR+96, $2,$3,$4}'  ${VM_LIST_EXISTED}
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
            VM_NAME=$(awk '{printf "%c : %-40s %s%s\n", NR+96, $2,$3,$4}' ${VM_LIST_EXISTED} | awk '/'^${VM_SELECT_No}'/{print $3}')
            #
            if [ "${QUIET}" = 'yes' ]; then
                F_RM_VM  ${VM_NAME}
            else
                echo "准备删除虚拟机【${VM_NAME}】"
                read  -t 30  -p "请确认，默认[n]，[y|n]：" ACK
                if [ "x${ACK}" = 'xy' ]; then
                    F_RM_VM  ${VM_NAME}
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


