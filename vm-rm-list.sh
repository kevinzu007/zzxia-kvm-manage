#!/bin/bash
#############################################################################
# Create By: zhf_sy
# License: GNU GPLv3
# Test On: CentOS 7
#
# 用途：将kvm上的虚拟机列出来，选择需要删除的虚拟机，然后执行删除
# 用法：直接运行，无需参数
# 注意：需要vm-rm.sh配合
#############################################################################


echo  "虚拟机清单："
echo "---------------------------------------------"
virsh list --all > /tmp/vm.list
sed -i -e '1,2d' -e '/^$/d' -e '/^[ ]*$/d' /tmp/vm.list
awk '{printf "%c : %-40s %s %s\n", NR+96, $2,$3,$4}' /tmp/vm.list
echo "---------------------------------------------"
echo "请选择你想删除的虚拟机，如果模版机在“running”状态，删除前会强行关闭它！"
echo "删除后将不可恢复！！！"
read -p "请输入（可以联系输入多个，不能有空格，如：def）："  ANSWER

#awk '{printf "%c : %s\n", NR+96, $2}' /tmp/vm.list | sed -n "/^${ANSWER}/p"
#VM_NAME=$(awk '{printf "%c:%s\n", NR+96, $2}' /tmp/vm.list | awk -F ":"  "/^${ANSWER}/{print \$2}")

echo "OK！"
echo "你选择的是：${ANSWER}"
read -p "按任意键继续......"


VM_RM_LIST=$(echo ${ANSWER})
VM_RM_NUM=$(echo ${#VM_RM_LIST})

for ((i=0;i<VM_RM_NUM;i++))
do
    VM_RM_NO=$(echo ${VM_RM_LIST:${i}:1})
    VM_RM_NAME=$(awk '{printf "%c : %-40s %s%s\n", NR+96, $2,$3,$4}' /tmp/vm.list | awk '/'^${VM_RM_NO}'/{print $3}')
    if [ "${VM_RM_NAME}x" = "x" ]; then
        echo "no this VM, 你耍我吗！"
        continue
    fi
    ./vm-rm.sh ${VM_RM_NAME}
done



