  

## 安装显卡驱动

  

1. 更新源

```shell    
sudo apt update
sudo apt upgrade -y
```

2. 启动 "Software & Updates"
3. 选择 TAB "Additional Drivers"
4. 选取相应的版本号（NVDIA driver metapackage from nvidia-driver-525）
5. "Apply Changes"
6. 等待完成后重启
7. 重启后命令行输入 `nvidia-smi`

  

## 挂载盘

  

### 格式化盘

```shell

sudo apt install -y exfatprogs

disk=/dev/sdb
parted -s ${disk} mklabel gpt
parted -a optimal ${disk} mkpart primary '0%' '100%'
parted ${disk} set 1 msftdata on

sleep 0.5

mkfs.exfat ${disk}1

uuid=`lsblk -no uuid ${disk}`
echo $uuid

mkdir /data0
chmod 755 data0

mount -o umask=0000 UUID=${uuid} /data0
```

  
### 配置开机挂载盘

配置 rc.local 服务，`/etc/systemd/system/rc-local.service`

```shell
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local ExecStart
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
```

写开机自启脚本
```shell
#!/bin/bash

mount -o umask=0000 UUID=${uuid} /data0

```