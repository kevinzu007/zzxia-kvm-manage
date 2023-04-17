#!/bin/bash

if [[ $# -ne 1 ]]; then
    echo "请指定要关闭的vm列表文件！"
    exit
fi



while read LINE
do
    # 跳过以#开头的行或空行
    [[ "$LINE" =~ ^# ]] || [[ "$LINE" =~ ^[\ ]*$ ]] && continue
    virsh  shutdown  $LINE
done < $1



