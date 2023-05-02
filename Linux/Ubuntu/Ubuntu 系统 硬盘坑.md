
### 格式化成exfat后无法被Windows识别

解决方式参考：
> https://askubuntu.com/questions/706608/exfat-external-drive-not-recognized-on-windows
```shell
parted -s ${disk} mklabel gpt
parted -a optimal ${disk} mkpart primary '0%' '100%'
parted ${disk} set 1 msftdata on
sleep 1 # 分区后需要等待系统加载分区后，才可进行格式化
mkfs.exfat ${disk}1
```

根据文章描述，其出现问题的原因为：没有添加**msftdata**标签，并且没有进行分区对齐 `-a optimal`导致Windows系统无法读取，使用以上代码进行分区即可解决该问题。


### exfat 无法给盘赋权(chmod 无效)

参考文章：
> https://askubuntu.com/questions/1255907/20-04-chmod-not-working-on-exfat-mount

更改 `/etc/fstab`，相较于原先内容，额外增加 `umask=0000`， 作用为将文件权限设为777。
```shell
echo "UUID=${uuid}  ${datadir}  ${fstype}  defaults,umask=0000  0  0 " >>/etc/fstab
```

相关无效解法（可能对xfs有效）：
使用 `chatter -i /data0` 与 `chatter +i /data0` `lsattr /data0` 等。（exFat文件系统不支持此操作）




