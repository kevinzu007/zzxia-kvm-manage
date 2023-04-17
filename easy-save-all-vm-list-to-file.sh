#!/bin/bash


VM_LIST='./vm-all.list'
> ${VM_LIST}


virsh list --all | grep  -E '^ ([0-9]+|-)' | awk '{print $2}' | tee -a ${VM_LIST}

echo "已写入文件【${VM_LIST}】"


