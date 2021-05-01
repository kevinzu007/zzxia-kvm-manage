# kvm-manage

#### 介绍
对KVM虚拟机的批量克隆与修改
*** 你若喜欢，请为她完成几个小心愿：***
1. 点亮【Star】，让她看到你是爱她的；
2. Fork她，为她增加新功能，修Bug，让她更有内涵；
3. 提Issue，告诉我她有哪些小脾气；
4. 打赏她，为她买jk；

#### 软件架构
Linux shell

#### 安装教程
克隆到KVM服务器上即可

#### 使用说明
请使用-h|--help参数运行sh脚本即可看到使用帮助
##### list.csv
根据需要定制虚拟机信息，以逗号分隔，用#注释掉不需要的行
```
$ cat list.csv 
# VM_NAME,CPU(个),MEM(GB),NET名, IP1,IP_MASK1,GATEWAY1 ,DOMAIN,DNS1 DNS2
#################################################################################################
# test
v-192-168-11-190-deploy,1,2,br1,192.168.11.190,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
v-192-168-11-191-mast,4,8,br1,192.168.11.191,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
v-192-168-11-192-node,4,8,br1,192.168.11.192,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
v-192-168-11-193-node,4,8,br1,192.168.11.193,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
v-192-168-11-194-etcd,2,4,br1,192.168.11.194,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
#v-192-168-11-195-etcd,2,4,br1,192.168.11.195,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
#v-192-168-11-196-etcd,2,4,br1,192.168.11.196,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
v-192-168-11-197-repo,2,4,br1,192.168.11.197,24,192.168.11.1,zjlh.lan,192.168.11.3 192.168.11.4
```
##### 克隆
```
$ ./vm-clone.sh --help

    用途：KVM上虚拟机克隆，并修改相关信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    注意：本脚本在centos 7上测试通过，需要vm-img-modify.sh配合
    用法：
        ./vm-clone.sh  [-h|--help]
        ./vm-clone.sh  [-f|--file]
    参数说明：
        $0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -f|--file      虚拟机清单文件
            文件格式如下（字段之间用【,】分隔）：
            #VM_NAME,CPU(个),MEM(GB),NET名, IP1,IP_MASK1,GATEWAY1 ,DOMAIN,DNS1 DNS2
            v-192-168-1-2-nextcloud,2,4,br1, 192.168.1.2,24,192.168.11.1, zjlh.lan,192.168.11.3 192.168.11.4
            v-192-168-1-3-nexxxx,2,4,br1, 192.168.1.3,24,192.168.11.1, zjlh.lan,192.168.11.3
    示例:
        #
        ./vm-clone.sh  -f vm.list
```
##### 修改vm信息
```
$ ./vm-img-modify.sh 

    用途：KVM虚拟机信息修改（主机名、IP、IP子网掩码、网关、域名、DNS）
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-img-modify.sh  [-h|--help]
        ./vm-img-modify.sh  [{VM_NAME}  {NEW_IP}  {NEW_IP_MASK}  {NEW_GATEWAY}]  {NEW_DOMAIN}  <{NEW_DNS1}>  <{NEW_DNS2}>
    参数说明：
        $0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
    示例:
        #
        ./vm-img-modify.sh  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3  192.168.11.4
        ./vm-img-modify.sh  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1
```
##### 删除虚拟机
```
$ ./vm-rm.sh 

    用途：删除指定名称的kvm虚拟机
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-rm.sh  [-h|--help]
        ./vm-rm.sh  [{VM_NAME1}]  {VM_NAME2} ... {VM_NAMEn}
    参数说明：
        $0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
    示例:
        #
        ./vm-rm.sh  虚拟机1
        ./vm-rm.sh  虚拟机1  虚拟机2
```
##### 从列表中选择要删除的虚拟机
```
$ ./vm-rm-list.sh
```

#### 参与贡献

1.  Fork 本仓库
2.  新建 Feat_xxx 分支
3.  提交代码
4.  新建 Pull Request


#### 特技

1.  使用 Readme\_XXX.md 来支持不同的语言，例如 Readme\_en.md, Readme\_zh.md
2.  Gitee 官方博客 [blog.gitee.com](https://blog.gitee.com)
3.  你可以 [https://gitee.com/explore](https://gitee.com/explore) 这个地址来了解 Gitee 上的优秀开源项目
4.  [GVP](https://gitee.com/gvp) 全称是 Gitee 最有价值开源项目，是综合评定出的优秀开源项目
5.  Gitee 官方提供的使用手册 [https://gitee.com/help](https://gitee.com/help)
6.  Gitee 封面人物是一档用来展示 Gitee 会员风采的栏目 [https://gitee.com/gitee-stars/](https://gitee.com/gitee-stars/)

