# zzxia-kvm-manage

中文名：猪猪侠之KVM虚拟化管理

**如果有使用上的问题或其他，可以加wx：`zzxia_ggbond` 解决。加好友时请注明你来自哪个平台！**


[toc]


## 1 介绍

批量克隆、修改、删除、启动、自动启动、关闭KVM虚拟机。适合小企业使用。

### 1.1 功能：

1. 克隆虚拟机：通过编辑my_vm.list文件定义虚拟机信息，然后运行vm-clone.sh，选择克隆模板，然后按照my_vm.list清单克隆出想要的虚拟机
1. 修改虚拟机信息：【主机名、IP、IP子网掩码、网关、域名、DNS】，一般主要配合vm-clone.sh使用，也可以单独使用
1. 批量启动指定虚拟机；批量启动清单中的虚拟机；批量启动选择的虚拟机
1. 批量设置自动启动指定虚拟机；批量设置自动启动清单中的虚拟机；批量设置自动启动选择的虚拟机
1. 批量关闭指定虚拟机；批量关闭清单中的虚拟机；批量关闭选择的虚拟机
1. 批量删除指定虚拟机；批量删除清单中的虚拟机；批量删除选择的虚拟机

### 1.2 喜欢她，就满足她：

1. 【Star】她，让她看到你是爱她的；
2. 【Watching】她，时刻感知她的动态；
2. 【Fork】她，为她增加新功能，修Bug，让她更加卡哇伊；
3. 【Issue】她，告诉她有哪些小脾气，她会改的，手动小绵羊；
4. 【打赏】她，为她买jk；
<img src="https://gitee.com/zhf_sy/pic-bed/raw/master/dao.png" alt="打赏" style="zoom:40%;" />


## 2 软件架构

Linux shell


## 3 安装教程

克隆到KVM服务器上即可


## 4 使用说明

请使用-h|--help参数运行sh脚本即可看到使用帮助
除了kvm，你还需要安装guestfs，在centos7上运行`yum install -y  libguestfs-tools`


### 4.1 环境变量文件`kvm.env`

基于`kvm.env.sample`创建环境变量文件`kvm.env`，根据你的环境修改相关环境变量，这个非常重要，否则你可能运行出错

```bash
$ cat kvm.env.sample
#!/bin/bash

# 静默方式
export QUIET='no'     #--- yes|no

# KVM环境参数
export KVM_XML_PATH='/etc/libvirt/qemu'                 #-- KVM虚拟XML配置文件路径（CENTOS下XML的默认路径，如果是UBUNTU，请修改）

# 模板虚拟机参数
/dev/sda1】
export VM_NIC_CONF_FILE='/etc/sysconfig/network-scripts/ifcfg-eth0'   #-- 模板虚拟机CentOS系统内的网卡配置文件

# 新虚拟机默认参数，特殊值可以在【my_vm.list】中指定
export VM_DEFAULT_DNS='192.168.11.3,192.168.11.4'      #-- 默认DNS，最多两个DNS服务器，中间用【,】分隔，不要有空格
export VM_DEFAULT_DOMAIN='zjlh.lan'                    #-- 默认域名
export VM_DEFAULT_DISK_IMG_PATH='/var/lib/libvirt/images'   #-- 虚拟机磁盘文件默认路径
```

### 4.2 虚拟机列表文件`my_vm.list`

基于`my_vm.list.sample`创建虚拟机列表文件`my_vm.list`（默认，文件名可以是其他名称），根据自己的需要定制虚拟机信息，以逗号分隔，用#注释掉不需要的行：

```text
$ cat  my_vm.list.sample
### 虚拟机克隆清单
###.
###   2【名称：NAME】= [自定义]
###     既是虚拟机名称，也是虚拟机主机名
###..
###   3【CPU：CPU】= [自定义数量]
###..
###   4【内存：MEM】= [自定义数量]
###     单位是GB
###..
###   5【网卡：NIC】= [自定义]
###.    KVM网卡名称
###..
###   6【IP地址：IP】= [自定义]
###.    IP地址
###..
###   7【IP掩码：IP_MASK】= [自定义]
###.    IP地址掩码，例如：24、16、8、12
###..
###   8【IP网关：IP_GATEWAY】= [自定义]
###.    IP网关
###..
###   9【DNS：DNS】= < 自定义1 <,自定义2> >
###.    可以定义0~2个，例如：1.1.1.1, 2.2.2.2，或者8.8.8.8
###.
###  10【域名：DOMAIN】= <自定义>
###.    虚拟机的域名
###.
###  11【磁盘IMG路径：IMG_PATH】= <自定义>
###.    虚拟机KVM磁盘文件存放路径，例如：/disk2/images
###.
###  12【备注：NOTE】= [ 自定义 ]
###     说明信息
###.
###
###     暂时不需要的行用'#'注释掉
###
###
#| NAME                   | CPU  | MEM  | NIC  | IP             | IP_MASK | IP_GATEWAY   | DNS                        | DOMAIN   | IMG_PATH                    | NOTE               |
#| **名称**               | CPU  | 内存 | 网卡 | **IP地址**     | IP掩码  | **IP网关**   | **DNS**                    | **域名** | **磁盘IMG路径**             | **备注**           |
#| ---------------------- | ---- | ---- | ---- | -------------- | ------- | ------------ | -------------------------- | -------- | --------------------------- |                    |
| v-192-168-11-190-deploy | 1    | 2    | br1  | 192.168.11.190 | 24      | 192.168.11.1 |                            |          |                             |                    |
| v-192-168-11-191-mast   | 4    | 8    | br1  | 192.168.11.191 | 24      | 192.168.11.1 |                            |          |                             |                    |
| v-192-168-11-192-node   | 4    | 8    | br1  | 192.168.11.192 | 24      | 192.168.11.1 | 8.8.8.8                    | zj.lan   | /var/lib/libvirt/images22   |                    |
| v-192-168-11-193-node   | 4    | 8    | br1  | 192.168.11.193 | 24      | 192.168.11.1 | 1.1.1.1, 2.2.2.2           | hb.lan   |                             |                    |
| v-192-168-11-194-etcd   | 2    | 4    | br1  | 192.168.11.194 | 24      | 192.168.11.1 |                            |          |                             |                    |
#| v-192-168-11-195-etcd   | 2    | 4    | br1  | 192.168.11.195 | 24      | 192.168.11.1 |                            |          |                             |                    |
#| v-192-168-11-196-etcd   | 2    | 4    | br1  | 192.168.11.196 | 24      | 192.168.11.1 |                            |          |                             |                    |
| v-192-168-11-197-repo   | 2    | 4    | br1  | 192.168.11.197 | 24      | 192.168.11.1 |                            |          | /disk2/images               |                    |
```


### 4.3 克隆

**克隆前的建议：**
- 建议先制作好一个较为完美的模板虚拟机，然后在克隆时选择使用他
- 查看KVM环境变量文件`kvm.env`，看是否与你的实际情况相同，否则请修改它

```bash
$ ./vm-clone.sh --help

    用途：KVM上虚拟机克隆，并修改相关信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    依赖：
        ./vm-img-modify.sh
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-clone.sh  [-h|--help]
        ./vm-clone.sh  <-f|--file {清单文件}>  < -q|--quiet  [-t|--template {虚拟机模板}] >
        ./vm-clone.sh  <-f|--file {清单文件}>  <-t|--template {虚拟机模板}>
    参数说明：
        $0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -f|--file      虚拟机清单文件，默认为【./my_vm.list】，请基于【my_vm.list.sample】创建
        -q|--quiet     静默方式
        -t|--templat   指定虚拟机模板
    示例:
        #
        ./vm-clone.sh  -h
        # 一般
        ./vm-clone.sh                       #--- 默认虚拟机清单文件【./my_vm.list】，非静默方式，手动选择模板
        ./vm-clone.sh  -t v-centos-1        #--- 默认虚拟机清单文件【./my_vm.list】，非静默方式，基于模板【v-centos-1】创建
        # 指定vm清单文件
        ./vm-clone.sh  -f xxx.list                      #--- 使用虚拟机清单文件【xxx.list】，非静默方式，手动选择模
        ./vm-clone.sh  -f xxx.list  -t v-centos-1       #--- 使用虚拟机清单文件【xxx.list】，非静默方式，基于模板【v-centos-1】创建
        # 静默方式
        ./vm-clone.sh  -q  -t v-centos-1                #--- 默认虚拟机清单文件【./my_vm.list】，静默方式，基于模板【v-centos-1】创建
        ./vm-clone.sh  -q  -t v-centos-1  -f xxx.list   #--- 使用虚拟机清单文件【xxx.list】，静默方式，基于模板【v-centos-1】创建
```


### 4.4 修改vm信息

```bash
$ ./vm-img-modify.sh 

    用途：修改KVM虚拟机主机名及网卡信息（主机名、IP、IP子网掩码、网关、域名、DNS）
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-img-modify.sh  [-h|--help]
        ./vm-img-modify.sh  <-q|--quiet>  [ {VM_NAME}  {NEW_IP}  {NEW_IP_MASK}  {NEW_GATEWAY} ]  <{NEW_DOMAIN}>  <{NEW_DNS1}<,{NEW_DNS2}>>
    参数说明：
        $0   : 代表脚本本身
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
        ./vm-img-modify.sh  -h        #--- 帮助
        # 一般
        ./vm-img-modify.sh  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3,192.168.11.4
        ./vm-img-modify.sh  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3
        ./vm-img-modify.sh  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1
        # 静默方式
        ./vm-img-modify.sh  -q  v-192-168-1-3-nexxxx  192.168.1.3  24  192.168.11.1  zjlh.lan  192.168.11.3,192.168.11.4
```

### 4.5 启动（或自动启动）虚拟机

```bash
$ ./vm-start.sh -h

    用途：启动虚拟机；设置虚拟机自动启动
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-start.sh  [-h|--help]
        ./vm-start.sh  [-l|--list]
        ./vm-start.sh  [ <-s|--start>  <-a|--autostart> ]  [ [-f|--file {清单文件}] | [-S|--select] | [-A|--ARG {虚拟机1} {虚拟机2} ... {虚拟机n}] ]
    参数说明：
        $0   : 代表脚本本身
        []   : 代表是必选项
        <>   : 代表是可选项
        |    : 代表左右选其一
        {}   : 代表参数值，请替换为具体参数值
        %    : 代表通配符，非精确值，可以被包含
        #
        -h|--help      此帮助
        -l|--list      列出KVM上的虚拟机
        -s|--start     启动虚拟机
        -a|--autostart 开启自动启动虚拟机
        -f|--file      从文件选择虚拟机（默认），默认文件为【./my_vm.list】，请基于【my_vm.list.sample】创建
        -S|--select    从KVM中选择虚拟机
        -A|--ARG       从参数获取虚拟机
    示例:
        #
        ./vm-start.sh  -h                   #--- 帮助
        ./vm-start.sh  -l                   #--- 列出KVM上的虚拟机
        # 一般（默认从默认文件）
        ./vm-start.sh  -s                   #--- 启动默认虚拟机清单文件【./my_vm.list】中的虚拟机
        ./vm-start.sh  -s  -a               #--- 启动默认虚拟机清单文件【./my_vm.list】中的虚拟机，并设置为自动启动
        ./vm-start.sh  -a                   #--- 自动启动默认虚拟机清单文件【./my_vm.list】中的虚拟机
        # 从指定文件
        ./vm-start.sh  -s  -f xxx.list      #--- 启动虚拟机清单文件【xxx.list】中的虚拟机
        ./vm-start.sh  -a  -f xxx.list      #--- 自动启动虚拟机清单文件【xxx.list】中的虚拟机
        # 我选择
        ./vm-start.sh  -s  -S               #--- 启动我选择的虚拟机
        ./vm-start.sh  -a  -S               #--- 自动启动我选择的虚拟机
        # 指定虚拟机
        ./vm-start.sh  -s  -A  vm1 vm2      #--- 启动虚拟机【vm1、vm2】
        ./vm-start.sh  -a  -A  vm1 vm2      #--- 自动启动虚拟机【vm1、vm2】
```

### 4.6 关闭虚拟机

```bash
$ ./vm-shutdown.sh -h

    用途：shutdown虚拟机
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-shutdown.sh  [-h|--help]
        ./vm-shutdown.sh  [-l|--list]
        ./vm-shutdown.sh  <-q|--quiet>  [ [-f|--file {清单文件}] | [-S|--select] | [-A|--ARG {虚拟机1} {虚拟机2} ... {虚拟机n}] ]
    参数说明：
        $0   : 代表脚本本身
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
        ./vm-shutdown.sh  -h               #--- 帮助
        ./vm-shutdown.sh  -l               #--- 列出KVM上的虚拟机
        # 一般（默认从默认文件）
        ./vm-shutdown.sh                   #--- shutdown默认虚拟机清单文件【./my_vm.list】中的虚拟机
        # 从指定文件
        ./vm-shutdown.sh  -f xxx.list      #--- shutdown虚拟机清单文件【xxx.list】中的虚拟机
        # 我选择
        ./vm-shutdown.sh  -S               #--- shutdown我选择的虚拟机
        # 指定虚拟机
        ./vm-shutdown.sh  -A  vm1 vm2      #--- shutdown虚拟机【vm1、vm2】
        # 静默方式
        ./vm-shutdown.sh  -q               #--- shutdown默认虚拟机清单文件【./my_vm.list】中的虚拟机，用静默方式
        ./vm-shutdown.sh  -q  -f xxx.list  #--- shutdown虚拟机清单文件【xxx.list】中的虚拟机，用静默方式
        ./vm-shutdown.sh  -q  -S           #--- shutdown我选择的虚拟机，用静默方式
        ./vm-shutdown.sh  -q  -A  vm1 vm2  #--- shutdown虚拟机【vm1、vm2】，用静默方式
```

### 4.7 删除虚拟机

```bash
$ ./vm-rm.sh -h

    用途：删除虚拟机
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-rm.sh  [-h|--help]
        ./vm-rm.sh  [-l|--list]
        ./vm-rm.sh  <-q|--quiet>  [ [-f|--file {清单文件}] | [-S|--select] | [-A|--ARG {虚拟机1} {虚拟机2} ... {虚拟机n}] ]
    参数说明：
        $0   : 代表脚本本身
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
        ./vm-rm.sh  -h               #--- 帮助
        ./vm-rm.sh  -l               #--- 列出KVM上的虚拟机
        # 一般（默认从默认文件）
        ./vm-rm.sh                   #--- 删除默认虚拟机清单文件【./my_vm.list】中的虚拟机
        # 从指定文件
        ./vm-rm.sh  -f xxx.list      #--- 删除虚拟机清单文件【xxx.list】中的虚拟机
        # 我选择
        ./vm-rm.sh  -S               #--- 删除我选择的虚拟机
        # 指定虚拟机
        ./vm-rm.sh  -A  vm1 vm2      #--- 删除虚拟机【vm1、vm2】
        # 静默方式
        ./vm-rm.sh  -q               #--- 删除默认虚拟机清单文件【./my_vm.list】中的虚拟机，用静默方式
        ./vm-rm.sh  -q  -f xxx.list  #--- 删除虚拟机清单文件【xxx.list】中的虚拟机，用静默方式
        ./vm-rm.sh  -q  -S           #--- 删除我选择的虚拟机，用静默方式
        ./vm-rm.sh  -q  -A  vm1 vm2  #--- 删除虚拟机【vm1、vm2】，用静默方式
```

### 4.8 列出已有虚拟机

```bash
$ ./vm-list.sh -h

    用途：列出KVM上的虚拟机
    依赖：
    注意：本脚本在centos 7上测试通过
    用法：
        ./vm-list.sh  <-h|--help>
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
        ./vm-list.sh  -h                   #--- 帮助
        ./vm-list.sh                       #--- 列出KVM上的虚拟机
```

### 4.8 简单管理虚拟机命令

看名字就知道他的用途了

```bash
./easy-save-all-online-vm-list-to-file.sh
./easy-save-all-vm-list-to-file.sh
./easy-start-spec-vm-list.sh
./easy-shutdown-all-online-vm.sh
./easy-shutdown-spec-vm-list.sh
./easy-force-shutdown-spec-vm-list.sh
```


## 5 参与贡献

1.  Fork 本仓库
2.  新建 Feat_xxx 分支
3.  提交代码
4.  新建 Pull Request


## 特技

1.  使用 Readme\_XXX.md 来支持不同的语言，例如 Readme\_en.md, Readme\_zh.md
2.  Gitee 官方博客 [blog.gitee.com](https://blog.gitee.com)
3.  你可以 [https://gitee.com/explore](https://gitee.com/explore) 这个地址来了解 Gitee 上的优秀开源项目
4.  [GVP](https://gitee.com/gvp) 全称是 Gitee 最有价值开源项目，是综合评定出的优秀开源项目
5.  Gitee 官方提供的使用手册 [https://gitee.com/help](https://gitee.com/help)
6.  Gitee 封面人物是一档用来展示 Gitee 会员风采的栏目 [https://gitee.com/gitee-stars/](https://gitee.com/gitee-stars/)

