#!/bin/bash


read -p '关闭所有运行中的虚拟机，请确认（y|n）:'  ACK
if [[ ${ACK} != 'y' ]]; then
    echo 'OK，已退出！'
    exit
fi


for i in $(virsh list | grep  -E '^ [0-9]+' | awk '{print $1}'); do
    virsh  shutdown  $i
done



