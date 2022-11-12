# MySQL

## Mysql 集群方案

-----

### Replication

读写分离，百度一搜，全是解决方案。这里主要介绍一款工具

- MHA

#### MHA

是一个类似redis sentinel的工具，用来监控主节点，判断主节点是否存活。

当主节点死亡，将会通过一定方式选定一个从节点，将其变成主节点，同时将其他子节点指向当前节点，并且将当前主节点的IP绑定成VIP

-----

### PXC

#### 介绍

- PXC 是基于 Galera 的面向 OLTP 的多主同步复制插件
- PXC 主要用于解决 MySQL 集群中数据同步强一致性问题
- PXC是 MySQL 集群方案中公认的优选方案之一

#### 特性

- 同步复制，事务在所有集群节点要么同时提交，要么不提交
- 多主复制，可以在任意一个节点写入
- 数据同步的强一致性，所有节点数据保持一致

**尽可能的控制PXC集群的规模**

- PXC集群节点越多，数据同步的速度就越慢

![image-20210208165846429](image-20210208165846429.png)

#### 配置

**PXC依赖的端口**

| 端口 | 描述                    |
| ---- | ----------------------- |
| 3306 | MySQL服务端口           |
| 4444 | 请求全量同步（SST）端口 |
| 4567 | 数据库节点之间通信端口  |
| 4568 | 请求增量同步（IST）端口 |

**配置文件**

在 Perconal 数据库配置文件中

`配置文件在 /etc/percona-xtradb-cluster.conf.d 目录下`

- `mysqld.cnf` mysql 的常用配置文件
- `wsrep.cnf`  pxc 集群信息

**`mysqld` 文件**

- `server-id` 服务id 不能和其他集群节点相同

**`wsrep.cnf` 文件**

| 参数名                     | 参数解析                                 |
| -------------------------- | ---------------------------------------- |
| `server-id`                | PXC集群中MySQL实例的唯一ID               |
| `wsrep_provider`           |                                          |
| `wsrep_cluster_name`       | PXC集群的名称                            |
| `wsrep_cluster_address`    | PXC集群的IP                              |
| `wsrep_node_name`          | 当前节点的名称                           |
| `wsrep_node_address`       | 当前节点的IP                             |
| `wsrep_sst_method`         | 同步方法（mysqldump、rsync、xtrabackup） |
| `wsrep_sst_auth`           | 同步使用的账户                           |
| `pxc_strict_mode`          | 同步模式（强一致性...）                  |
| `binlog_format`            | 基于ROW复制                              |
| `default_storage_engine`   | 默认引擎                                 |
| `innodb_autoinc_lock_mode` | 逐渐自增长                               |



#### PXC节点状态图

![image-20210208162448761](image-20210208162448761.png)

- Open 节点启动成功
- PRIMARY 节点成功加入
- JOINER 节点同步数据
- JOINED 节点加入成功
- SYNCED 节点开始提供服务
- DONER 当有其他节点与当前节点进行全量同步
  - 引发流量控制
  - 客户端不可用



#### PXC集群状态图

![image-20210208163401277](image-20210208163401277.png)

- PRIMARY 全可用
- NON_PRIMARY 过半可用
- DISCONNECTED 过半不可用，禁止链接（防止脑裂）

>**脑裂**：在一定情况下分化出多主
>
>比如你将多个服务存放在*A区*与*B区*，并且*A区*与*B区*服务数量相同，当*A区*与*B区*的链路发生故障，如果当前选主成功，则会导致出现脑裂。*A区*与*B区*对外都提供服务，可能会导致信息不统一

#### mysql 集群状态

在mysql中利用语句进行查询

```mysql
SHOW STATUS LIKE "关键参数";
```

关键参数

| 关键参数                    | 参数介绍                                       |
| --------------------------- | ---------------------------------------------- |
| `wsrep_cluster_conf_id`     |                                                |
| `wsrep_cluster_size`        | 集群节点总数                                   |
|                             |                                                |
| `wsrep_local_state_comment` | 节点状态                                       |
| `wsrep_cluster_status`      | 集群状态（PRIMARY、NON_PRIMARY、Disconnected） |
| `wsrep_connected`           | 节点是否链接到集群                             |
| `wsrep_ready`               | 集群是否正常工作                               |
| `wsrep_cluster_size`        | 节点数量                                       |
| `wsrep_desync_count`        | 延时节点数量                                   |
| `wsrep_incoming_addresses`  | 集群节点IP地址                                 |
|                             |                                                |
| `wsrep_cert_deps_distance`  | 事务执行并发数                                 |
| `wsrep_apply_oooe`          | 接收队列中事务占比                             |
| `wsrep_apply_window`        | 接收队列中事务平均数量                         |
| `wsrep_commit_oooe`         | 发送队列中事务占比                             |
| `wsrep_commit_window`       | 发送队列中事务平均数量                         |
|                             |                                                |
|                             |                                                |

-----

#### 原理

##### pxc同步方式

通过 binlog 日志，进行数据的同步。

binlog 有三种模式

- `Row` 整条数据同步，体积最大
- `Statment`  sql 语句，体积偏小
- `Mixed` 两种结合

PXC集群只支持使用 Row 模式

##### pxc写入原理

当 pxc 集群中的节点进行写入操作时

- `节点A`先在本地写入，不写入日志中，通知其他节点进行写入，等待其他节点相应
- `其他节点`接收到操作，开始执行，同样不写入日志中
- `其他节点`将写入结果返回给`节点A`（不论成功与否）
- 当有**过半数量**的节点成功执行，告知其他节点写入成功

<img src="MySQL PXC.assets/image-20210228205848866.png" alt="image-20210228205848866" style="zoom:25%;" />

##### pxc 锁冲突

- 当pxc集群中，多个节点对一张有主键自增的表进行

<img src="MySQL PXC.assets/image-20210228211310081.png" alt="image-20210228211310081" style="zoom:25%;" />

-----

## Mysql 集群中间件

### 负载均衡

- Haproxy
- MySQL-Proxy

提供了请求转发，降低了单节点的负载

-----

### 数据切分

- [MyCat](####MyCat)
- [Atlas](####Atlas)
- [OneProxy](####OneProxy)
- [ProxySQL](####ProxySQL)

增加了容量，降低了单节点的负载。限制了一些查询功能 

常见的优化方式如下

- 将数据按访问量进行拆分，拆分成冷数据与热数据
  - 淘宝只显示3个月内的订单。

-----

#### MyCat

##### 开源免费

- 基于阿里巴巴的Corba中间件，部署在3000台服务器上，每天执行50亿次请求
- 基于Java语言，跨平台

##### 功能全面

- 分片算法丰富
  - 主键求模切分
  - 枚举值切分
  - 时间段切分
- 读写分离
- 全局主键
- 分布式事务

##### 资源丰富

- 《MyCat权威指南》
- 《分布式数据库架构及企业实践——基于MyCat中间件》

##### 普及率高

- 电信领域、电商领域
- 国内普及率最高的MySQL中间件

-----

#### Atlas

##### 开源免费

- 基于MySQL Proxy
- 主要用于360产品，每天承载几十亿次请求

##### 功能有限

- 读写分离
- 少量数据切分算法
- 不支持全局主键、分布式事务

##### 资料较少

- 开源项目文档
- 无技术社区、无出版物

##### 普及率较低

- 可供参考案例不多

-----

#### OneProxy

##### 商业软件

- 分为免费版和企业版
- C语言的内核，性能较好

##### 功能有限

- 读写分离
- 具有少量的数据切分算法
- 不支持全局主键、分布式事务

##### 资料较少

- 官网不提供使用文档
- 无技术社区、无出版物

##### 普及率低

- 仅在中小企业的内部系统使用过

-----

#### ProxySQL

- 性能出众、Percona 推荐
- 支持读写分离 数据切分 (类似 Atlas )
- 开源免费、资料较多

-----

