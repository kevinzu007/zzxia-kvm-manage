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
#LOG_HOME=
#KVM_DEFAULT_SSH_HOST=
#KVM_DEFAULT_SSH_PORT=
#KVM_DEFAULT_SSH_USER=
#KVM_DEFAULT_XML_PATH=
#VM_DEFAULT_CLONE_TEMPLATE=
#VM_DEFAULT_DISK_IMG_PATH=

# 本地env
QUIET='NO'     #-- 静默方式
VM_LIST="${SH_PATH}/my_vm.list"
#VM_LIST_APPEND_1="${SH_PATH}/my_vm.list.append.1"
#
VM_LIST_TMP="${LOG_HOME}/${SH_NAME}-my_vm.list.tmp"
#VM_LIST_APPEND_1_TMP="${LOG_HOME}/${SH_NAME}-my_vm.list.append.1.tmp"
VM_LIST_EXISTED="${LOG_HOME}/${SH_NAME}-vm-list.existed"
#
VM_MODIFY_SH="${SH_PATH}/vm-modify.sh"
FORMAT_TABLE_SH="${SH_PATH}/format_table.sh"



F_HELP()
{
    echo "
    用途：KVM上克隆虚拟机，并修改相关信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    依赖：
        ${SH_PATH}/kvm.env
        ${VM_LIST}
        ${FORMAT_TABLE_SH}
        ${VM_MODIFY_SH}
    注意：
        * 名称正则表达式完全匹配，会自动在正则表达式的头尾加上【^ $】，请规避
        * 输入命令时，参数顺序不分先后
    用法：
        $0  [-h|--help]
        $0  <-q|--quiet>  <{VM1}  {VM2} ... {VMn}> ... {VM名称正则表达式完全匹配}>
    参数说明：
        \$0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help            此帮助
        -q|--quiet           静默方式
    示例:
        $0  -h             #--- 帮助
        $0                                        #-- 对所有虚拟机进行操作
        $0  v-192-168-1-3-a  v-192-168-1-44-bb    #-- 对正则完全匹配【^v-192-168-1-3-a$】及【^v-192-168-1-44-bb$】的虚拟机进行操作
        $0  v-192-168-1-3-a  v-172.*              #-- 对正则完全匹配【^v-192-168-1-3-a$】及【^v-172.*$】的虚拟机进行操作
        $0  -q  v-192-168-1-3-a                   #-- 用静默方式，对正则完全匹配【^v-192-168-1-3-a$】的虚拟机进行操作
    "
}



# 用法：F_SEARCH_EXISTED_VM  {虚拟机名}
F_SEARCH_EXISTED_VM ()
{
    FS_VM_NAME=$1
    GET_IT='NO'
    while read -r LINE
    do
        F_VM_NAME=$(echo "$LINE" | awk '{print $2}')
        F_VM_STATUS=$(echo "$LINE" | awk '{print $3}')
        if [ "x${FS_VM_NAME}" = "x${F_VM_NAME}" ]; then
            GET_IT='YES'
            break
        fi
    done < "${VM_LIST_EXISTED}"
    #
    if [ "${GET_IT}" = 'YES' ]; then
        echo -e "${F_VM_STATUS}"
        return 0
    else
        return 1
    fi
}



# 生成sed
F_GEN_SED ()
{
    cat << EOF
#!/bin/bash
#
# 网卡
sed -i  s/"<source bridge=.*$"/"<source bridge='${VM_NIC}'\/>"/g  "${KVM_XML_PATH}/${VM_XML}"
#
# On CentOS7 BUG修复，参考：https://bugs.centos.org/view.php?id=10402
sed -i  s/"domain-${CLONE_TEMPLATE}"/"domain-${VM_NAME}"/  "${KVM_XML_PATH}/${VM_XML}"
EOF
}




# 参数检查
TEMP=$(getopt -o hq  -l help,quiet -- "$@")
if [ $? != 0 ]; then
    echo -e "\n猪猪侠警告：参数不合法，请查看帮助【$0 --help】\n"
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
            QUIET='YES'
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



# 建立base目录
[ -d "${LOG_HOME}" ] || mkdir -p  "${LOG_HOME}"


# 待搜索的服务清单
:> "${VM_LIST_TMP}"
# 参数个数为
if [[ $# -eq 0 ]]; then
    cp  "${VM_LIST}"  "${VM_LIST_TMP}"
    sed -i -e '/^#/d' -e '/^$/d' -e '/^[ ]*$/d' "${VM_LIST_TMP}"
else
    for i in "$@"
    do
        #
        GET_IT='N'
        while read -r LINE
        do
            # 跳过以#开头的行或空行
            [[ "$LINE" =~ ^# ]] || [[ "$LINE" =~ ^[\ ]*$ ]] && continue
            #
            VM_NAME=$(echo "$LINE" | awk -F '|' '{print $2}' | xargs)
            if [[ ${VM_NAME} =~ ^$i$ ]]; then
                echo "$LINE" >> "${VM_LIST_TMP}"
                GET_IT='YES'
                #break    #-- 匹配1次
            fi
        done < "${VM_LIST}"
        #
        if [[ $GET_IT != 'YES' ]]; then
            echo -e "\n猪猪侠警告：虚拟机【${i}】不在列表【${VM_LIST}】中，请检查！\n"
            exit 51
        fi
    done
fi
# 加表头
sed -i  "1i#| **名称** | CPU  | 内存 | 网卡 |  **物理宿主机** | **克隆模板** | **磁盘IMG路径** | **备注** |"  "${VM_LIST_TMP}"
# 屏显
echo -e "${ECHO_NORMAL}############################# 开始 Clone #############################${ECHO_CLOSE}"   #-- 80 ( 80##  70++  60## )
echo -e "\n【${SH_NAME}】待Clone虚拟机清单："
${FORMAT_TABLE_SH}  --delimeter '|'  --file "${VM_LIST_TMP}"


# 交互
if [[ ${QUIET} == NO ]]; then
    echo "以上信息正确吗？如果正确，请输入 "'y'""
    read -r -p "请输入："  ANSWER
    #
    if [[ ! ${ANSWER} == y ]]; then
        echo "小子，好好检查吧！"
        exit 4
    fi
fi


# go
while read -r LINE
do
    # 跳过以#开头的行或空行
    [[ "$LINE" =~ ^# ]] || [[ "$LINE" =~ ^[\ ]*$ ]] && continue
    # 2
    VM_NAME=$(echo "$LINE" | cut -f 2 -d '|' | xargs)
    VM_IMG="${VM_NAME}.img"
    VM_XML="${VM_NAME}.xml"
    # 3
    VM_CPU=$(echo "$LINE" | cut -f 3 -d '|' | xargs)
    # 4
    VM_MEM=$(echo "$LINE" | cut -f 4 -d '|' | xargs)
    # 5
    VM_NIC=$(echo "$LINE" | cut -f 5 -d '|' | xargs)
    # 6
    KVM_HOST=$(echo "$LINE" | cut -f 6 -d '|' | xargs)
    #KVM_HOST=${KVM_HOST// /}
    # 初始化变量
    KVM_SSH_USER=""
    KVM_SSH_HOST=""
    KVM_SSH_PORT=""
    # 使用模式匹配提取用户、主机和端口
    if [[ -n "$KVM_HOST" ]]; then
        if [[ $KVM_HOST =~ ^([^@]+)@([^:]+)(:([0-9]+))?$ ]]; then
            KVM_SSH_USER="${BASH_REMATCH[1]}"  # 提取用户
            KVM_SSH_HOST="${BASH_REMATCH[2]}"  # 提取主机
            KVM_SSH_PORT="${BASH_REMATCH[4]}"  # 提取端口
        elif [[ $KVM_HOST =~ ^([^:]+)(:([0-9]+))?$ ]]; then
            KVM_SSH_HOST="${BASH_REMATCH[1]}"  # 提取主机
            KVM_SSH_PORT="${BASH_REMATCH[3]}"  # 提取端口
        fi
    fi
    # 如果某个值为空，使用默认值
    KVM_SSH_USER="${KVM_SSH_USER:-$KVM_DEFAULT_SSH_USER}"
    KVM_SSH_HOST="${KVM_SSH_HOST:-$KVM_DEFAULT_SSH_HOST}"
    KVM_SSH_PORT="${KVM_SSH_PORT:-$KVM_DEFAULT_SSH_PORT}"
    # 7
    VM_CLONE_TEMPLATE=$(echo "$LINE" | cut -f 7 -d '|' | xargs)
    VM_CLONE_TEMPLATE=${VM_CLONE_TEMPLATE:-${VM_DEFAULT_CLONE_TEMPLATE}}
    # 8
    VM_DISK_IMG_PATH=$(echo "$LINE" | cut -f 8 -d '|' | xargs)
    VM_DISK_IMG_PATH=${VM_DISK_IMG_PATH:-${VM_DEFAULT_DISK_IMG_PATH}}
    # 9
    VM_NOTE=$(echo "$LINE" | cut -f 9 -d '|' | xargs)
    # x
    KVM_XML_PATH=${KVM_DEFAULT_XML_PATH}
    #
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"    #-- 70 ( 80##  70++  60## )
    echo "宿主机： ${KVM_SSH_HOST}"
    echo "克隆模板： ${VM_CLONE_TEMPLATE}"
    echo "新虚拟机名称：${VM_NAME}"
    echo "新虚拟机CPU(核)： ${VM_CPU}"
    echo "新虚拟机内存(GiB)：${VM_MEM}"
    echo "新虚拟机网卡：${VM_NIC}"
    echo "备注：${VM_NOTE}"
    echo 
    KVM_LIBVIRT_URL="qemu+ssh://${KVM_SSH_USER}@${KVM_SSH_HOST}:${KVM_SSH_PORT}/system"
    #
    :> "${VM_LIST_EXISTED}"
    if ! virsh --connect "${KVM_LIBVIRT_URL}" list --all > "${VM_LIST_EXISTED}"; then
        echo -e "\n\033[31m猪猪侠警告：连接KVM宿主机失败，请检查以下问题：\033[0m"
        echo -e "1. libvirt服务是否运行？(systemctl status libvirtd)"
        echo -e "2. 连接URL是否正确？(当前尝试连接: ${KVM_LIBVIRT_URL})"
        echo -e "3. 是否有访问权限？(检查用户是否在libvirt组)\n"
        exit 1
    fi
    #
    # 删除无用行
    sed -i '1,2d;s/[ ]*//;/^$/d'  "${VM_LIST_EXISTED}"
    #
    # 是否重名
    #
    if [[ $(F_SEARCH_EXISTED_VM  "${VM_NAME}" > /dev/null 2>&1; echo $?) -eq 0 ]]; then
        echo -e "\n猪猪侠警告：虚拟机【${VM_NAME}】已存在，跳过\n"
        continue
    fi
    #
    # 模板是否则正常
    #
    VM_STATUS=$(F_SEARCH_EXISTED_VM  "${VM_CLONE_TEMPLATE}")
    if [[ -z ${VM_STATUS} ]]; then
        echo -e "\n猪猪侠警告：克隆模板【${VM_CLONE_TEMPLATE}】不存在存在，退出\n"
        exit 1
    elif [[ ${VM_STATUS} =~ 'running'|'运行' ]]; then
        echo -e "\n猪猪侠警告：克隆模板【${VM_CLONE_TEMPLATE}】在运行中，请先停止，退出\n"
        exit 1
    fi
    #
    # clone
    echo "开始 virt-clone ......"
    #
    VM_CLONE_LOG_FILE="${LOG_HOME}/${SH_NAME}-clone.log--${VM_NAME}"
    :> "${VM_CLONE_LOG_FILE}"
    time virt-clone  --connect "${KVM_LIBVIRT_URL}"  \
        -o "${VM_CLONE_TEMPLATE}"  \
        -n "${VM_NAME}"  \
        -f "${VM_DISK_IMG_PATH}/${VM_IMG}"  | tee "${VM_CLONE_LOG_FILE}" 2>&1
    #
    if grep -i -q 'ERROR' "${VM_CLONE_LOG_FILE}"; then
        echo -e "\n猪猪侠警告：【${VM_NAME}】clone 出错，请检查！\n"
        exit 1
    fi
    #
    # CPU、MEM
    virsh setmaxmem ${VM_NAME} ${VM_MEM}G  --config     #-- 以GiB 为单位，设置最大内存
    virsh setmem    ${VM_NAME} ${VM_MEM}G  --config     #-- 设置启动内存
    virsh setvcpus  ${VM_NAME} ${VM_CPU}   --config --maximum  #-- 设置最大cpu
    virsh setvcpus  ${VM_NAME} ${VM_CPU}   --current    #-- 设置启动数量
    #
    # 修改xml for 网卡及其他
    F_GEN_SED_SH="/tmp/${SH_NAME}-xml-sed.sh"
    F_GEN_SED > "${F_GEN_SED_SH}"
    scp  -P "${KVM_SSH_PORT}"  "${F_GEN_SED_SH}"  "${KVM_SSH_USER}"@"${KVM_SSH_HOST}":"${F_GEN_SED_SH}"
    #
    #重新define虚拟机
    ssh  -p "${KVM_SSH_PORT}"  "${KVM_SSH_USER}"@"${KVM_SSH_HOST}"  < /dev/null  "bash ${F_GEN_SED_SH}  &&  virsh define ${KVM_XML_PATH}/${VM_XML}"
    #
    # vm Modify
    echo "开始 vm-modify.sh ......"
    bash  "${VM_MODIFY_SH}"  --quiet  "${VM_NAME}"
    #
done < "${VM_LIST_TMP}"



