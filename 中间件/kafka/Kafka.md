#kafka学习笔记

## 介绍
[文档](https://kafka.apache.org/documentation/)
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



### 顺序写入




### 安装



### 单机配置


### 集群配置


### Topic管理



