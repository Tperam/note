#kafka学习笔记

## 概念
[文档](https://kafka.apache.org/documentation/)
[基础课程](https://ke.qq.com/user/index/index.html#/plan/cid=474340&tid=100568033&term_id=100568033)
[msb周老师源码课](https://ke.qq.com/course/3581774#term_id=103724319)

Kafka 是一种高吞吐量的分布式发布订阅系统，也就是一个消息队列，属于中间件概念。

其用途极多：
- 提供消息的订阅与发布
- 系统间解耦
- 异步通信
- 削峰填谷
- 流处理
等功能。


### 基础介绍

Kafka 是一种分布式的解决方案，其多数情况下为集群部署，依赖zookeeper作为分布式协调工具。

其有概念
- Topic
	- partition
- Record
- Broker

#### Topic
Topic 就是一个主题，可以理解为一个标签。这个标签是用于描述与区分一组消息（Record）与另一组消息的不同。也可以理解为是将消息归类。
在Kafka中，我们通常是通过Topic的方式去管理消息。

#### Partition
Partition 就是一个个基于Topic拆分的分区，根据设置的分区数决定有几个分区

#### Record
Record 就是一个消息，可以类比为http的请求。它就是一个具体的数据体，其由 `Key`，`value`，`timestamp` 组成。

#### Broker
Broker 就是Kafka服务端。
Kafka通常以集群的方式存在，对于单个服务节点的命名为Broker。

一般Broker里面有多个Topic，每个Topic可能有多个分区，Broker直接管理与处理属于自己的Partition。除了属于自己的Partition以外，还可能存在其他Broker的Partition的副本，用于确保服务的高可用。
![[Pasted image 20221111223724.png]]



#### zookeeper 部分
#zookeeper
Kafka 在低版本中是依赖于Zookeeper做分布式协调的，其主要用于监控Kafka集群中的Leader与存储Topic的部分元数据。


#### 总结

Kafka集群以Topic形式负责分类集群中的Record。每一个Record属于一个Topic。每个Topic底层都会对应一组分区的日志，用于持久化Topic中的Record。
同时，在kafka集群中，Topic的每一个日志分区都一定会有1个Broker担当该分区的Leader，其他Broker担当该分区的Follower。Leader负责分区数据的读写操作，Follower负责同步该分区的数据。这样如果分区的Leader宕机，该分区的其他Follower会选举出新的Leader继续负责该分区的数据读写。
其中集群中的Leader的监控，与Topic的部分元数据是存储在Zookeeper中的。


### 日志与分区
Kafka中所有消息是通过Topic为单位进行管理，每个Kafka中的topic通常会有多个订阅者，负责订阅发送到该Topic中的数据。Kafka负责管理集群中每个Topic的一组日志分区数据。

生产者将数据发布到相应的Topic。负责选择将哪个记录发送到Topic中的哪个Parition（分区）。例如，可以使用`round-robin`方式完成此操作，而这种仅是为了平衡负载。也可以语义分区功能（例如基于记录中的Key）进行操作

每组日志分区是一个有序不可变的日志序列，分区中的每一个Record都被分配了唯一的序列编号，称为offset，Kafka集群会持久化所有发布到Topic中的Record信息，该Record的持久化时间是通过配置文件指定的，默认是168小时。
`log.retention.hours=168`

Kafka底层会定期的检查日志文件，然后将过期的数据从log中移除，由于Kafka使用硬盘存储日志文件，因此使用Kafka长时间缓存一些日志文件是不存在问题的 。

#### 先进先出
在Kafka中，如果我们想保证我们的某一类数据是先进先出（例如同一个用户的某一类操作），则我们需要按顺序的将其存放入同一个Partition当中，可以选择将Topic的分区数设为1，也可以使用UserID作为Key进行取余，导入到相同的Partition中。
如果存放到不同的Partition当中，那么将无法保证其Record被取出的顺序性。

Kafka只能保证同一个Partition的内部顺序。

#### offset
在Parition中，每条Record都有一个唯一标识，那就是offset（偏移量），他表示了数据在我们Topic中的先后顺序

offset越小，说明进入Partition的时间越早。


### 生产者与消费者

在消费者消费Topic中数据的时候，每个消费者会维护本次消费对应分区的偏移量，消费者会在消费完一个批次的数据之后，会将本次消费的偏移量提交给Kafka集群，因此对于每个消费者而言，可以随意的控制该消费者的偏移量。因此在Kafka中，消费者可以从一个Topic分区中的任意位置读取队列数据，由于每个消费者控制了自己的消费偏移量，因此多个消费者之间彼此互相独立。

![[Pasted image 20221111235147.png]]
消费者每次提交的偏移量，就是在Kafka中下一次读取的起始位置。

Kafka中对Topic实现日志分区有以下目的：
- 首先，他们允许日志扩展到超出单个服务器所能容纳的大小。每个单独分区都必须适合托管他的服务器，但是一个Topic可能有很多分区，因此它可以处理任意数量的数据。
- 其次，每个服务充当其某些分区的Leader，也可能充当其他分区的Follwer，因此集群中的负载得到了很好的平衡。

 
#### 消费者 Consumer Group

消费者使用Consumer Group名称标记自己，并且发布到Topic的每条记录都会传递到每个订阅Consumer Group 中的一个消费者实例。如果所有Consumer实例都具有相同的Consumer Group，那么Topic中的记录会在该ConsumerGroup中的Consumer实例进行均分消费；如果所有的Consumer实例具有不同的Consumer Group，则每条记录将广播到所有Consumer Group进程。

更常见的是，我们发现Topic具有少量的Consumer Group，每个Consumer Group可以理解为一个“逻辑订阅者”。每个ConsumerGroup 均有许多Consumer实例组成，以实现可伸缩性和容错能力。这无非就是发布-订阅模型，其中订阅者是消费者的集群而不是单个进程。这种消费方式Kafka会将Topic按照分区的方式均分给一个Consumer Group下的实例，如果Consumer Group 下有新的成员接入，则新介入的Consumer实例回去接管Consumer Group内其他消费者负责的某些分区。同样，如果一下Consumer Group下有其他的Consumer实例宕机，则由该Consumer Group下其他实例接管。

由于Kafka的Topic的分区策略，因此Kafka仅提供分区中记录的有序性，也就意味着相同的Topic的不同分区记录之间无顺序。因为针对于绝大多数的大数据应用和使用场景，使用分区内部有序或者使用Key进行分区策略已经足够满足绝大多数应用场景。但是，如果您需要记录全局有序，则可以通过只有一个分区的Topic来实现，尽管这将意味着每个ConsumerGroup只能有一个Consumer进程。


#### 消费者与分区关系
![[Pasted image 20221112192531.png]]
每一个分区，至多只有一个消费者进行消费，如果在同一个Consumer Group中，有超出分区数量的消费者，则该消费者暂时将会被空闲。当该Consumer Group中有占有分区的消费者离线，其分区将会被Consumer Group进行重新分配。如果有空闲消费者，则优先将未被占有的分区分配给空闲消费者。如果没有空闲消费者，则将剩下分区进行平均分配。



### 顺序写入&ZeroCopy

#### 顺序写入

#mmap #MemoryMappedFiles
Kafka 的特性之一就是高吞吐率，但是Kafka的消息是保存或缓存在磁盘上的，一般认为在磁盘上读写数据是会降低性能的。但是Kafka即使是普通的服务器，Kafka也可以轻松支持每秒百万级的写入请求，超过了大部分的消息中间件，这种特性也使得Kafka在日志处理等海量数据场景广泛应用。Kafka会把收到的消息都写入到硬盘中，防止丢失数据，为了优化写入速度Kafka采用了两个技术：顺序写入和MMFile。

因为硬盘是机械结构，每次读写都会先寻址，后写入，其中寻址是一个“机械动作”，它是最耗时的。所以硬盘最讨厌随机I/O，最喜欢顺序I/O。为了提高读写硬盘的速度，Kafka就是使用顺序I/O。这样省去了大量的内存开销以及节省了IO寻址的时间。但是单纯的使用顺序写入，Kafka的写入性能也不可能和内存进行对比，英雌Kafka的数据并不是实时的写入磁盘中。

Kafka充分利用了现代操作系统分页存储来利用内存提高I/O效率。 Memory Mapped Files（后面简称mmap）也称 为内存映射文件，在64位操作系统中一般可以表示20G的数据映射，它的工作原理是直接利用操作系统的Page实现文件到物理内存的直接映射。完成MMap映射后，用户对内存的所有操作会被操作系统自动的刷星到磁盘上，极大地降低了IO使用率。

![[Pasted image 20221113213429.png]]

#### zero copy
#zerocopy
Kafka 服务器在相应客户端读取时，底层使用ZeroCopy技术，直接将数据从内核空间写入磁盘，无需拷贝到用户空间。

其实现为，让内核直接将一个流（本地IO/网络IO）的数据，写入到另一个流（本地IO/网络IO）中，避免将数据读取到用户态的内存拷贝。

##### 传统IO操作
1. 用户进程调用`read`等系统调用，向操作系统发出IO请求，请求读取数据到自己的内存缓冲区中。自己进入阻塞状态。
2. 操作系统收到请求后，进一步将IO请求发送磁盘。
3. 磁盘驱动器收到内核的IO请求，把数据从磁盘读取到驱动器的缓冲中。此时不占用CPU。当驱动器的缓冲区被杜曼后，向内和发起中断信号，告知自己缓冲区已满。
4. 内核收到中断，使用CPU时间切片，将磁盘驱动器的缓存中的数据拷贝到内核缓冲区中。
5. 如果内核缓冲区的数据小于用户申请的读的数据，重复步骤3跟步骤4，直到内核缓冲区的数据足够多位置。
6. 将数据从内核缓冲区拷贝到用户缓冲区，同时从系统调用中返回。完成任务
![[Pasted image 20221113220717.png]]

##### DMA
#DMA
DMA是现代服务器所拥有（主板支持）
其减少了在读取数据时与CPU的交互（其额外交互交由DMA执行）
![[Pasted image 20221113220447.png]]

##### 常规IO
![[Pasted image 20221113220604.png]]

##### zero copy
#zerocopy 
其不通过用户态空间，减少了数据的传递与交互。提高了性能。
![[Pasted image 20221113220825.png]]




##  安装

### 前期准备

由于学习视频较老，使用的是centos 6.10作为系统镜像，第一次学习不换环境，跟着流程走。
当前为了避免麻烦，使用docker作为虚拟机。
[centos 6 源问题](http://blog.demon.ren/700.html)

采用配置（以下配置皆从官方找到
- [kafka_2.11-2.2.0.tgz](https://archive.apache.org/dist/kafka/2.2.0/kafka_2.11-2.2.0.tgz)
- [zookeeper-3.4.6.tar.gz](https://archive.apache.org/dist/zookeeper/zookeeper-3.4.6/zookeeper-3.4.6.tar.gz)
- [jdk-8u202-linux-64.rpm](https://download.oracle.com/otn/java/jdk/8u202-b08/1961070e4c9b4e26a04e7f5a083f551e/jdk-8u202-linux-x64.rpm) （需要登陆

#### 安装
**java安装**
```shell
rpm -ivh jdk-*.rpm
```
配置环境变量
```shell
echo "JAVA_HOME=/usr/java/latest" ~/.bashrc
echo "PATH=$PATH:$JAVA_HOME/bin" ~/.bashrc
echo "CLASSPATH=." ~/.bashrc
echo "export JAVA_HOME" ~/.bashrc
echo "export PATH" ~/.bashrc
echo "export CLASSPATH" ~/.bashrc
source ~/.bashrc
```
**配置主机名**
```shell
vim /etc/sysconfig/network
```
```shell
NETWORKING=yes
HOSTNAME=localhost.localdomain
```
**配置IP**
```shell
vim /etc/hosts
```
**关闭防火墙**
```shell
service iptables stop
chkconfig iptables off
```
**安装zookeeper**
```shell
tar -xzvf zookeeper-3.4.6.tar.gz -C /usr/
```
进入配置目录
```shell
cd /usr/zookeeper-3.4.6/conf/
```
复制配置（默认以zoo.cfg文件启动
可编辑修改zoo.cfg配置。（此处只搭建环境不多涉及。
```shell
cp zoo_sample.cfg zoo.cfg
```
启动zookeeper
```shell
/usr/zookeeper-3.4.6/bin/zkServer.sh start
```
可通过jps查看zookeeper启动信息
```shell
# jps
448 QuorumPeerMain
477 Jps
```
也可以通过 zookeeper提供的脚本查看
```shell
/usr/zookeeper-3.4.6/bin/zkServer.sh status
```

**安装Kafka**
```shell
tar -zxvf kafka_2.11-2.2.0.tgz -C /usr/
```
 其解压后的bin目录下就是启动kafka的一些脚本
```shell
ls /usr/kafka_2.11-2.2.0/bin
```
```shell
[root@9ce9835eceda kafka_2.11-2.2.0]# ls /usr/kafka_2.11-2.2.0/bin
connect-distributed.sh               kafka-reassign-partitions.sh
connect-standalone.sh                kafka-replica-verification.sh
kafka-acls.sh                        kafka-run-class.sh
kafka-broker-api-versions.sh         kafka-server-start.sh
kafka-configs.sh                     kafka-server-stop.sh
kafka-console-consumer.sh            kafka-streams-application-reset.sh
kafka-console-producer.sh            kafka-topics.sh
kafka-consumer-groups.sh             kafka-verifiable-consumer.sh
kafka-consumer-perf-test.sh          kafka-verifiable-producer.sh
kafka-delegation-tokens.sh           trogdor.sh
kafka-delete-records.sh              windows
kafka-dump-log.sh                    zookeeper-security-migration.sh
kafka-log-dirs.sh                    zookeeper-server-start.sh
kafka-mirror-maker.sh                zookeeper-server-stop.sh
kafka-preferred-replica-election.sh  zookeeper-shell.sh
kafka-producer-perf-test.sh
```
安装完成，我们开始单机配置


### 单机配置
配置文件主要存放在`/usr/kafka_2.11-2.2.0/config`下。
其主要包含kafka的一些参数。如果我们要配置一个kafka服务，则需要配置`server.properties`

简单配置以下内容：
`server.properties`
```
broker.id=0  # kafka节点的唯一标识
listeners=PLAINTEXT://kafka_test:9092  # kafka的链接地址，kafka_test为之前配置的主机id
log.dirs=/tmp/kafka-logs  # 实际上此为broker节点存储数据的位置
zookeeper.connect=kafka_test:2181  # zookeeper的链接参数
```

启动kafka
```
/usr/kafka_2.11-2.2.0/bin/kafka-server-start.sh -daemon config/server.properties
```
此时输入jps将会看到
```shell
[root@9ce9835eceda kafka_2.11-2.2.0]# jps
448 QuorumPeerMain
836 Kafka
921 Jps
```

### 集群配置


### bash 管理操作


### Topic管理



