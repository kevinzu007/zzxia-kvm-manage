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


F_HELP()
{
    echo "
    用途：删除指定名称的kvm虚拟机
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  <-q|--quiet>  [{VM_NAME1}]  {VM_NAME2} ... {VM_NAMEn}
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
        $0  虚拟机1
        $0  虚拟机1  虚拟机2
        # 静默
        $0  -q  虚拟机1  虚拟机2
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



# 用法：RM_VM  虚拟机名
RM_VM ()
{
    F_VM_NAME=$1
    echo "------------------------------"
    echo "删除虚拟机：$F_VM_NAME ......"

    # force shutdown
    if [ "`F_VM_SEARCH $F_VM_NAME`" = 'running' ]; then
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
                echo -e "\n超时，跳过\n"
            fi
        fi
    done
    # undefine VM ,this will delete xml
    virsh undefine "${F_VM_NAME}"
}


# 参数检查
TEMP=`getopt -o hq  -l help,quiet -- "$@"`
if [ $? != 0 ]; then
    echo "参数不合法，退出"
    F_HELP
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
            QUIET='yes'
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done


#
if [ $# -eq 0 ]; then
    echo -e "\n峰哥说：请提供需要删除的虚拟机\n"
    exit 2
fi


# 现有vm
VM_LIST_ONLINE="/tmp/${SH_NAME}-vm.list.online"
virsh list --all | sed  '1,2d;s/[ ]*//;/^$/d'  > ${VM_LIST_ONLINE}


ARG_NUM=$#
for ((i=1;i<=ARG_NUM;i++))
do
    VM_NAME=$1
    shift
    #
    if [ `F_VM_SEARCH "${VM_NAME}" > /dev/null; echo $?` -ne 0 ]; then
        echo -e "\n峰哥说：虚拟机【${VM_NAME}】没找到，跳过！\n"
    else
        RM_VM  ${VM_NAME}
        echo '------------------------------'
    fi
done


