# MySQL 备份

## 简介

MySQL 数据库有两种备份方式，一种是冷备份，一种是热备份

- 冷备份
- 热备份

-----

### 冷热备份

#### 冷备份

冷备份是需要数据库暂停服务，停机对数据进行备份。

- 无法对外提供服务
- 只能使用全量备份

#### 热备份

热备份是数据库可以对外提供服务，并同时备份数据。

- 无法保证备份时间点。
  - 除非全局上读锁
    - 全局上锁期间不能写入数据。
- 第一次需要全量备份
- 之后可以使用增量备份

#### **以上内容都可通过联机备份解决**

- 冷备份
  - 切断集群，让数据库进行备份，备份后再上线。
- 热备份
  - 保持集群，切断与其他节点的同步，对外提供读服务

-----

## 操作方式

**备份建议：每月进行一次全量备份，每日进行增量备份**

### 冷备份

#### 数据备份

直接暂停MySQL服务，利用Linux tar 命令压缩后即可

1. 将MySQL服务暂停
2. 对MySQL文件目录进行压缩备份
   - 如果MySQL有表分区，也需要将表分区一同压缩打包。
3. `tar -cvf mysql.tar /var/lib/mysql`
4. 备份结束后，开启MySQL服务

#### 数据还原

如果有表分区，那么还原节点也需要与备份节点相同

1. 将MySQL服务暂停
2. 将本地数据目录替换成备份数据目录
3. 删除本地原文件
   - `rm -rf /var/lib/mysql`
4. 解压
   - `tar -xvf mysql.tar`
5. 将`mysql`数据目录移动到 `/var/lib/mysql`目录下

### 热备份

有两种常见方式

- LVM 
- XtraBackup

#### LVM

LVM的原理是通过Linux的LVM卷轴快照进行备份，第一次全量备份，后面是增量备份

- 需要自己去给数据库加锁
- 需要自己创建LVM卷轴

#### XtraBackup

XtraBackup 是专门用于热备份MySQL的工具

- 热备份的过程中加读锁，数据可读，但不可写
- XtraBackup 备份过程中不会打断正在执行的事务
- XtraBackup 能够基于压缩等功能节约磁盘空间和流量

-----

## XtraBackup

### 原理

#### 备份原理

- XtraBackup 是一种物理备份工具，通过协议连接到MySQL服务端，然后读取并复制底层的文件，完成物理备份。

<img src="MySQL 备份.assets/image-20210305192220733.png" alt="image-20210305192220733" style="zoom: 25%;" />

#### 在备份时不同的效果

- InnoDB 引擎是带有事务机制的，会明确记录什么时间点写入了什么操作。所以在XtraBackup操作中即使有写入操作，也可以根据事务日志判断出，哪些是新写入的数据，哪些是老数据。
- MyISAM 没有事务机制，也就没有事务日志，所以无法判断哪些是老数据，哪些是新数据，所以我们只能给它加读锁才行。

#### 不同的备份方式

- 对InnoDB引擎支持全量备份和增量备份
- 对MyISAM 引擎支持全量备份

#### XtraBackup 增量备份原理

MySQL 数据是以row的方式存在，row又存在于page中，page存在于extend中

<img src="MySQL 备份.assets/image-20210305193711164.png" alt="image-20210305193711164" style="zoom: 25%;" />

MySQL会为每一个page分配一个LSN号码，LSN是一个全局递增的号码，每次对page中的记录进行修改时，都会产生新的LSN号码

<img src="MySQL 备份.assets/image-20210305193742841.png" alt="image-20210305193742841" style="zoom:25%;" />

XtraBackup 会对LSN进行记录，当需要进行备份时，XtraBackup 会去对比LSN号码，当MySQL中的page的LSN发生了改变，XtraBackup将会对其进行备份保存。

<img src="MySQL 备份.assets/image-20210305193755873.png" alt="image-20210305193755873" style="zoom:25%;" />

-----

### 操作方式

| 命令           | 描述                         |
| -------------- | ---------------------------- |
| `xbcrypt`      | 用于加密或解密备份的数据     |
| `xbstream`     | 用于压缩或解压xbstream文件   |
| `xtrabackup`   | 备份InnoDB数据表             |
| `innobackupex` | 是上面三种命令的perl脚本封装 |
|                |                              |

#### 备份命令

##### 全量热备份

```SHELL
innobackupex --defaults-file=/etc/my.cnf --host=192.168.99.151 --user=admin --pasword=Abc_123456 --port=3306 /home/backup
```

```SHELL
innobackupex --defaults-file=/etc/my.cnf --host=192.168.99.151 --user=admin --pasword=Abc_123456 --port=3306 --no-timestamp --stream=xbstream -> /home/backup.xbstream
```

| 参数                    | 描述                                       |
| ----------------------- | ------------------------------------------ |
| `--defaults-file`       | 默认配置文件                               |
| `--host`                | MySQL地址                                  |
| `--user`                | 数据库链接用户                             |
| `--password`            | 数据库密码                                 |
| `--port`                | 数据库端口                                 |
|                         |                                            |
| `--no-timestamp`        | 直接存放到指定的文件路径，不生成时间戳文件 |
| `--steam=xbstream`      | 开启流式压缩                               |
|                         |                                            |
| `--encrypt`             | 用于加密的算法：AES128、AES192、AES256     |
| `--encrypt-threads`     | 执行加密的线程数                           |
| `--encrypt-chunk-size`  | 加密线程的缓存大小                         |
| `--encrypt-key`         | 密钥字符(24个字符)                         |
| `--encryption-key-file` | 密钥文件                                   |
|                         |                                            |
| `--compress`            | 压缩 InnoDB 数据文件                       |
| `--compress-threads`    | 执行压缩的线程数                           |
| `--compress-chunk-size` | 压缩线程的缓存                             |
| `--include`             | 需要备份的数据表的正则表达式               |
| `--galera-info`         | 备份PXC节点状态文件                        |
|                         |                                            |
| /home/backup            | 备份文件存放路径                           |

##### Linux系统定时执行任务

Linux中通过crontab命令，可以在固定的间隔时间执行指定的系统指令或shell脚本

**每天凌晨一点执行 /home/example/test.sh 脚本**

```SHELL
0 1 * * * /home/example/test.sh
```

| 分钟 | 小时 | 日期 | 月份 | 星期 | [年份] |
| ---- | ---- | ---- | ---- | ---- | ------ |
| 0    | 1    | *    | *    | *    | []     |

<img src="MySQL 备份.assets/image-20210307171624567.png" alt="image-20210307171624567" style="zoom:25%;" />



##### 增量热备份

- 增量热备份需要保证数据**不被压缩不被加密**。
  - 如果做了流失压缩，或者内容加密，都必须将其转换成普通全热量备份
- 增量热备份可以使用流失压缩或者内容加密

**增量热备份**

```SHELL
innobackupex --defaults-file=/etc/my.cnf --host=192.168.99.151 --user=admin --pasword=Abc_123456 --port=3306 --incremental-basedir=/home/backup --incremental /home/backup/increment
```

| 参数                    | 描述             |
| ----------------------- | ---------------- |
| `--incremental-basedir` | 全量热备份的目录 |
| `--incremental`         | 增量热备份       |

-----

#### 还原

还原只能通过关闭数据库，暂停其服务才能进行还原操作。

##### 全量冷还原

1. 关闭MySQL，清空数据目录，包括表分区的目录
2. 回滚没有提交的事务，同步已经提交的事务到数据文件

```SHELL
innobackupex --apply-log /home/backup
```



##### 流式还原备份

1. 关闭MySQL，清空数据目录，包括表分区的目录

2. 回滚没有提交的事务，同步已经提交的事务到数据文件

3. 开始还原

   ```shell
   innobackupex --defaults-file=/etc/my.cnf --copy-back /home/backup.xbstream
   ```

4. 启动MySQL

##### 流式还原压缩备份

1. 创建临时目录

2. 解压缩备份文件，并且将解压的内容存放到了 /home/temp 目录下

   ```SHELL
   innobackupex --decompress --decrypt=AES256 --encrypt-key=GCHFLrDFVx6UAsRb88uLVbAVWbK+Yzfs /home/temp
   ```

3. 从 /home/temp 目录下还原备份

   ```SHELL
   innobackupex --copy-back --defaults-file=/etc/my.cnf /home/temp
   ```

4. 启动MySQL

##### 增量备份还原方式

<img src="MySQL 备份.assets/image-20210308180003471.png" alt="image-20210308180003471" style="zoom:25%;" />

1. 处理全量热备份的日志

2. 处理增量备份1的日志

3. 处理全量热备份事务日志

   ```SHELL
   innobackupex --apply-log --redo-only /home/backup/全量热备份
   ```

4. 处理增量热备份1事务日志

   ```SHELL
   innobackupex --apply-log --redo-only /home/backup/全量热备份 --incremental-dir=/home/backup/increment/增量热备份1
   ```

5. 处理增量热备份2事务日志

   ```SHELL
   innobackupex --apply-log /home/backup/全量热备份 --incremental-dir=/home/backup/increment/增量热备份2
   ```

6. 关闭 MySQL 服务，并且删除数据目录与数据分片

7. 开始执行冷还原

   ```shell
   innobackupex --defaults-file/etc/my.cnf --copy-back /home/backup/全量热备份
   ```

8. 需要对数据目录以及数据分片设置用户组，给MySQL权限。

-----

## 误删除恢复

### 延时节点

#### 缺点

- 在延时阶段没有发现问题、解决问题，数据同步之后，将无法利用从节点实现误删除恢复

#### 处理

- 利用Replication 解决

- 从PXC集群中挑选一个节点，配置一个slave节点。

- 设置10分钟延迟。

  ```mysql
  CHANGE MASTER TO master_delay=600;
  ```

- 当数据库进行误删除，我们可以在10分钟内恢复数据。



**当误删除在没同步之前发生时，我们可以让slave跳过同步误删除操作的id号。**

- 我们通过binlog日志，从主节点中找到误删除的事务ID号。

  <img src="MySQL 备份.assets/image-20210308183047948.png" alt="image-20210308183047948" style="zoom: 25%;" />

- 暂停从节点与主节点的同步

- 从节点占用误删除操作的事务ID

  ```mysql
  SET gtid_next='xxxxxxxx'
  BEGIN;COMMIT;
  ```

- 恢复 gtid_next

  ```mysql
  SET gtid_next='automatic';
  ```

- 立即同步

  ```mysql
  CHANGE MASTER TO master_delay=0;
  ```

- 开启slave同步

**后续恢复方式**

- 停止PXC集群的业务操作，不要让业务系统读写数据库
- 导出从节点的数据，在主节点上创建临时库，导入数据
- 把主节点上的业务表重命名，然后把临时库的业务表迁移到业务库

-----

### 备份恢复

#### 缺点

- 数据不够新

-----

### binlog日志

日志闪回方案只利用当前节点恢复数据，简单易操作

1. 数据库需要开启binlog日志，并且都是Row格式
2. 禁止写入数据
3. 利用闪回工具解析binlog日志，解析成sql语句。找到误删除语句，清空表，执行sql语句

#### 工具

- binlog2sql