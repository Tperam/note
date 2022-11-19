[github地址](https://github.com/segmentio/kafka-go)

## 简介

Kafka-Go是一个go的Kafka客户端。

Kafka对于自己与其他几个库的比较
- [sarama](https://github.com/Shopify/sarama)，认为其不好用，API过于底层，文档过于简陋，并且不支持go特有Context。因是通过指针来传递值，导致有大量的内存分配使其gc压力过大。
- [confluent-kafka-go](https://github.com/confluentinc/confluent-kafka-go) 是以cgo为基础实现的kafka客户端，依赖了c的库。虽然他的文档比sarama要完善，但还是不支持go特有的context。
- [goka](https://github.com/lovoo/goka) 是go最新的Kafka客户端，它专注于特定的使用模式。它提供了将 Kafka 用作服务之间的消息传递总线而不是有序的事件日志的抽象，但这不是我们在 Segment 的 Kafka 的典型用例。该包依赖于sarama与Kafka进行交互。

#### kafka 版本
`kafka-go` 当前测试在 0.10.1.0 ~ 2.7.1。当前版本将兼容以前版本，最新的Kafka API可能没有被实现。

## API操作

### 创建连接
创建一个链接
```go
// to produce messages
topic := "my-topic"
partition := 0

conn, err := kafka.DialLeader(context.Background(), "tcp", "localhost:9092", topic, partition)
if err != nil {
    log.Fatal("failed to dial leader:", err)
}
...
if err := conn.Close(); err != nil {
    log.Fatal("failed to close writer:", err)
}
```

#### 创建Topics
在默认情况下，`auto.create.topics.enable='true'`。如果值为真，topics将会在创建连接时自动创建
```go
// to create topics when auto.create.topics.enable='true'
conn, err := kafka.DialLeader(context.Background(), "tcp", "localhost:9092", "my-topic", 0)
if err != nil {
    panic(err.Error())
}
```
如果值为假，则需要显式创建
```go
topic := "my-topic"

conn, err := kafka.Dial("tcp", "localhost:9092")
if err != nil {
    panic(err.Error())
}
defer conn.Close()

controller, err := conn.Controller()
if err != nil {
    panic(err.Error())
}
var controllerConn *kafka.Conn
controllerConn, err = kafka.Dial("tcp", net.JoinHostPort(controller.Host, strconv.Itoa(controller.Port)))
if err != nil {
    panic(err.Error())
}
defer controllerConn.Close()

topicConfigs := []kafka.TopicConfig{
    {
        Topic:             topic,
        NumPartitions:     1,
        ReplicationFactor: 1,
    },
}

err = controllerConn.CreateTopics(topicConfigs...)
if err != nil {
    panic(err.Error())
}
```

#### 通过非Leader链接连接到Leader
```go
// to connect to the kafka leader via an existing non-leader connection rather than using DialLeader
conn, err := kafka.Dial("tcp", "localhost:9092")
if err != nil {
    panic(err.Error())
}
defer conn.Close()
controller, err := conn.Controller()
if err != nil {
    panic(err.Error())
}
var connLeader *kafka.Conn
connLeader, err = kafka.Dial("tcp", net.JoinHostPort(controller.Host, strconv.Itoa(controller.Port)))
if err != nil {
    panic(err.Error())
}
defer connLeader.Close()
```

#### 列出所有Topics

```go
conn, err := kafka.Dial("tcp", "localhost:9092")
if err != nil {
    panic(err.Error())
}
defer conn.Close()

partitions, err := conn.ReadPartitions()
if err != nil {
    panic(err.Error())
}

m := map[string]struct{}{}

for _, p := range partitions {
    m[p.Topic] = struct{}{}
}
for k := range m {
    fmt.Println(k)
}
```


### Reader

Reader 是`kafka-go`中的另一个实现，目的是为了更简单的实现单topic-partition的经典案例。Reader自动处理了重连和offset管理，对外的API通过`context`支持异步关闭和超时。
注意：在Reader中，当程序退出时，调用`Close()`非常重要。Kafka服务需要优雅的关闭连接，去暂停继续发送数据到以链接客户端。下面提供的案例中，在shell中使用`ctrl-c` （或`docker stop` 与`kubernetes restart`）将不调用`Close()`。这将导致在相同的Topic中创建链接时有延迟（进程起来或容器运行）。在关闭程序时，请使用`sginal.Notify`处理关闭Reader。
```go
// make a new reader that consumes from topic-A, partition 0, at offset 42
r := kafka.NewReader(kafka.ReaderConfig{
    Brokers:   []string{"localhost:9092","localhost:9093", "localhost:9094"},
    Topic:     "topic-A",
    Partition: 0,
    MinBytes:  10e3, // 10KB
    MaxBytes:  10e6, // 10MB
})
r.SetOffset(42)

for {
    m, err := r.ReadMessage(context.Background())
    if err != nil {
        break
    }
    fmt.Printf("message at offset %d: %s = %s\n", m.Offset, string(m.Key), string(m.Value))
}

if err := r.Close(); err != nil {
    log.Fatal("failed to close reader:", err)
}
```


### 消费组