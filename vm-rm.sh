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
#QUIET_DELETE_IMG='yes'


F_HELP()
{
    echo "
    用途：删除指定名称的kvm虚拟机
    注意：本脚本在centos 7上测试通过
    用法：
        $0  [-h|--help]
        $0  [{VM_NAME1}]  {VM_NAME2} ... {VM_NAMEn}
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
        $0  虚拟机1
        $0  虚拟机1  虚拟机2
    "
}



RM_VM ()
{
    echo "------------------------------"
    echo "删除虚拟机：$VM_NAME ......"

    # vm ? exist
    virsh list --all | grep -q "${VM_NAME}"
    ERR1=$?
    if [ $ERR1 != 0 ]; then
        echo "${VM_NAME} NOT exist !"
        return 2
    fi

    # vm name ? match
    VM_SEARCH=$(virsh list --all | grep "${VM_NAME}" | awk '{print $2}')
    if [ "${VM_NAME}" != "${VM_SEARCH}" ]; then
        echo "${VM_NAME} : vmname NOT match !"
        return 3
    fi

    # force shutdown
    ## ?running
    virsh list | grep "${VM_NAME}"
    RUNNING=$?
    if [ $RUNNING = 0 ]; then
        virsh destroy "${VM_NAME}"
    fi

    # rm img
    N=$( virsh  dumpxml  --domain "${VM_NAME}"  | grep  "<disk type='file' device='disk'>" | wc -l )
    for ((i=1;i<=N;i++));
    do
        IMG_FILE=$( virsh  dumpxml  --domain "${VM_NAME}"  | grep -A2  "<disk type='file' device='disk'>" | sed -n '3p' | awk -F "'" '{print $2}' )
        #
        if [ "${QUIET_DELETE_IMG}" = "yes"  -a  -n "${IMG_FILE}" ]; then
            rm  -f "${IMG_FILE}"
            echo 'OK，已删除'
        elif [ "${QUIET_DELETE_IMG}" != "yes"  -a  -n "${IMG_FILE}" ]; then
            read -t 30 -p "重要提示：需要删除虚拟机镜像文件【${IMG_FILE}】，默认[no]，(yes|no)：" AK
            if [ "x${AK}" = 'xyes' ]; then
                rm  -f "${IMG_FILE}"
                echo 'OK，已删除'
            else
                echo -e "\n超时，跳过\n"
            fi
        fi
    done

    # undefine VM ,this will delete xml
    virsh undefine "${VM_NAME}"
}



#
case "$1" in
    -h|--help)
        F_HELP
        exit
        ;;
esac
#
if [ $# -eq 0 ]; then
    F_HELP
    exit 1
fi

#
ARG_NUM=$#
for ((i=1;i<=ARG_NUM;i++))
do
    VM_NAME=$1
    RM_VM
    echo '------------------------------'
    shift
done


