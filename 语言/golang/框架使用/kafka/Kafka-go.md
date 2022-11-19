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

### 创建连接（底层API）
创建一个链接（底层API）
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


#### 消费组
Kafka-go 同样支持Kafka消费组，包括broker的offsets管理。启动consumer groups，仅需要在ReaderConfig中指定GroupID。
ReadMessage自动提交offset
```go
// make a new reader that consumes from topic-A
r := kafka.NewReader(kafka.ReaderConfig{
    Brokers:   []string{"localhost:9092", "localhost:9093", "localhost:9094"},
    GroupID:   "consumer-group-id",
    Topic:     "topic-A",
    MinBytes:  10e3, // 10KB
    MaxBytes:  10e6, // 10MB
})

for {
    m, err := r.ReadMessage(context.Background())
    if err != nil {
        break
    }
    fmt.Printf("message at topic/partition/offset %v/%v/%v: %s = %s\n", m.Topic, m.Partition, m.Offset, string(m.Key), string(m.Value))
}

if err := r.Close(); err != nil {
    log.Fatal("failed to close reader:", err)
}
```
当使用消费组时，有许多限制：
- `(*Reader*).SetOffset`  将报错
- `(*Reader).Offset` 返回-1
- `(*Reader).Lag` 返回 -1
- `(*Reader).ReadLag`  返回错误
- `(*Reader).Stats`  返回-1的分区

#### 显式提交
kafka-go 提供显示提交，仅需将`ReadMessage`替换成`FetchMessage`同时在执行结束后执行`CommitMessages`。
```go
ctx := context.Background()
for {
    m, err := r.FetchMessage(ctx)
    if err != nil {
        break
    }
    fmt.Printf("message at topic/partition/offset %v/%v/%v: %s = %s\n", m.Topic, m.Partition, m.Offset, string(m.Key), string(m.Value))
    if err := r.CommitMessages(ctx, m); err != nil {
        log.Fatal("failed to commit messages:", err)
    }
}
```
在消费者组中提交消息时，给定Topic/partition的偏移量最高的消息确定该分区的已提交偏移量的值。 例如，如果通过调用 FetchMessage 检索单个分区的偏移量 1、2 和 3 处的消息，则使用消息偏移量 3 调用 CommitMessages 也会导致提交该分区的偏移量 1 和 2 处的消息。

#### 管理提交
默认情况下，`CommitMessages` 将会同步提交offsets到Kafka。为了提升性能，你可以通过设定`ReaderConfig`的`CommitInterval`，来定时提交offsets到Kafka。
```go
// make a new reader that consumes from topic-A
r := kafka.NewReader(kafka.ReaderConfig{
    Brokers:        []string{"localhost:9092", "localhost:9093", "localhost:9094"},
    GroupID:        "consumer-group-id",
    Topic:          "topic-A",
    MinBytes:       10e3, // 10KB
    MaxBytes:       10e6, // 10MB
    CommitInterval: time.Second, // flushes commits to Kafka every second
})
```

### Writer
用于生产数据到Kafka，程序可以用底层API（`Conn`），但包同样提供封装好的API（`Writer`），其在大多数情况下更加好用），它提供了额外的特性：
- 当出现错误时，自动重试/重连。
- 配置分布式的消息到可用分区。
- 同步或非同步的写入Kafka。
- 可使用`context`异步关闭。
- 在优雅关闭的情况下，将缓冲数据写出。
- 如果没有Topic，则在推送消息前创建。这个行为在`v0.4.30`后实现。
```go
// make a writer that produces to topic-A, using the least-bytes distribution
w := &kafka.Writer{
	Addr:     kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
	Topic:   "topic-A",
	Balancer: &kafka.LeastBytes{},
}

err := w.WriteMessages(context.Background(),
	kafka.Message{
		Key:   []byte("Key-A"),
		Value: []byte("Hello World!"),
	},
	kafka.Message{
		Key:   []byte("Key-B"),
		Value: []byte("One!"),
	},
	kafka.Message{
		Key:   []byte("Key-C"),
		Value: []byte("Two!"),
	},
)
if err != nil {
    log.Fatal("failed to write messages:", err)
}

if err := w.Close(); err != nil {
    log.Fatal("failed to close writer:", err)
}
```

#### 发送消息前创建Topic
```go
// Make a writer that publishes messages to topic-A.
// The topic will be created if it is missing.
w := &Writer{
    Addr:                   kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
    Topic:                  "topic-A",
    AllowAutoTopicCreation: true,
}

messages := []kafka.Message{
    {
        Key:   []byte("Key-A"),
        Value: []byte("Hello World!"),
    },
    {
        Key:   []byte("Key-B"),
        Value: []byte("One!"),
    },
    {
        Key:   []byte("Key-C"),
        Value: []byte("Two!"),
    },
}

var err error
const retries = 3
for i := 0; i < retries; i++ {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    // attempt to create topic prior to publishing the message
    err = w.WriteMessages(ctx, messages...)
    if errors.Is(err, LeaderNotAvailable) || errors.Is(err, context.DeadlineExceeded) {
        time.Sleep(time.Millisecond * 250)
        continue
    }

    if err != nil {
        log.Fatalf("unexpected error %v", err)
    }
}

if err := w.Close(); err != nil {
    log.Fatal("failed to close writer:", err)
}
```

#### 写入多个Topic
通常`WriterConfig.Topic`是用于初始化`single-topic`写入。通过排除该特定配置，您可以通过设置 `Message.Topic` 在每条消息的基础上定义主题。
```go
w := &kafka.Writer{
	Addr:     kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
    // NOTE: When Topic is not defined here, each Message must define it instead.
	Balancer: &kafka.LeastBytes{},
}

err := w.WriteMessages(context.Background(),
    // NOTE: Each Message has Topic defined, otherwise an error is returned.
	kafka.Message{
        Topic: "topic-A",
		Key:   []byte("Key-A"),
		Value: []byte("Hello World!"),
	},
	kafka.Message{
        Topic: "topic-B",
		Key:   []byte("Key-B"),
		Value: []byte("One!"),
	},
	kafka.Message{
        Topic: "topic-C",
		Key:   []byte("Key-C"),
		Value: []byte("Two!"),
	},
)
if err != nil {
    log.Fatal("failed to write messages:", err)
}

if err := w.Close(); err != nil {
    log.Fatal("failed to close writer:", err)
}
```
**注意**：这2个模式互相包含，如果你设置`Writer.Topic`，你不能在`Writer`中显式定义`Message.Topic`。反之同理，如果你没有在`Writer`中定义topic，也没有再`Message`中定义，则`Writer`将会报错。


### 兼容其他客户端
#### Sarama
如果你从Sarama中切换过来，并且想要相同的消息分区算法，你可以用`kafka.Hash`或`kafka.ReferenceHash`负载均衡器
-   `kafka.Hash` = `sarama.NewHashPartitioner`
-   `kafka.ReferenceHash` = `sarama.NewReferenceHashPartitioner`
`kafka.Hash`和`kafka.RefernceHash`负载均衡器将会路由消息到与Sarama相同的分区
```go
w := &kafka.Writer{
	Addr:     kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
	Topic:    "topic-A",
	Balancer: &kafka.Hash{},
}
```

#### librdkafka 与 confluent-kafka-go
使用`kafka.CRC32Balancer`负载均衡器，获得与librdkafka默认的`consistent_random`分区策略。
```go
w := &kafka.Writer{
	Addr:     kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
	Topic:    "topic-A",
	Balancer: kafka.CRC32Balancer{},
}
```

#### java
使用`kafka.Murmur2Balancer`负载均衡器得到与典型的Java客户端默认分区的相同行为。
**注意**：Java class 允许你直接指定分区，但这里不允许。
```go
w := &kafka.Writer{
	Addr:     kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
	Topic:    "topic-A",
	Balancer: kafka.Murmur2Balancer{},
}
```
### 压缩
压缩可在`Writer`中设置`Compression`字段
```go
w := &kafka.Writer{
	Addr:        kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
	Topic:       "topic-A",
	Compression: kafka.Snappy,
}
```
Reader 将通过检查消息属性来确定消费的消息是否被压缩。但是，必须导入所有预期编解码器的包，以便正确加载它们。
**注意**：在 0.4 之前的版本程序必须导入压缩包才能安装解码器并支持从 kafka 读取压缩消息。现在情况已不再如此，压缩包的导入现在是空操作。

### TLS
对于基本的 Conn 类型或在 Reader/Writer 配置中，您可以为 TLS 支持指定一个拨号器选项。 如果 TLS 字段为 nil，则不会与 TLS 连接。 注意：在未在 Conn/Reader/Writer 上配置 TLS 的情况下连接到启用了 TLS 的 Kafka 集群可能会出现不透明的 io.ErrUnexpectedEOF 错误。


#### 链接
```go
dialer := &kafka.Dialer{
    Timeout:   10 * time.Second,
    DualStack: true,
    TLS:       &tls.Config{...tls config...},
}

conn, err := dialer.DialContext(ctx, "tcp", "localhost:9093")
```
#### Reader
```go
dialer := &kafka.Dialer{
    Timeout:   10 * time.Second,
    DualStack: true,
    TLS:       &tls.Config{...tls config...},
}

r := kafka.NewReader(kafka.ReaderConfig{
    Brokers:        []string{"localhost:9092", "localhost:9093", "localhost:9094"},
    GroupID:        "consumer-group-id",
    Topic:          "topic-A",
    Dialer:         dialer,
})
```
#### Writer
直接创建
```go
w := kafka.Writer{
    Addr: kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"), 
    Topic:   "topic-A",
    Balancer: &kafka.Hash{},
    Transport: &kafka.Transport{
        TLS: &tls.Config{},
      },
    }
```
使用`kafka.NewWriter`
```go
dialer := &kafka.Dialer{
    Timeout:   10 * time.Second,
    DualStack: true,
    TLS:       &tls.Config{...tls config...},
}

w := kafka.NewWriter(kafka.WriterConfig{
	Brokers: []string{"localhost:9092", "localhost:9093", "localhost:9094"},
	Topic:   "topic-A",
	Balancer: &kafka.Hash{},
	Dialer:   dialer,
})
```
**注意**：`kafka.NewWriter`和`kafka.WriterConfig`将会在未来的版本中移除。

### SASL 支持
你可以指定`Dialer`选项用于SASL认证。`Dialer`能用于直接打开`Conn`（底层API），也可以通过配置传递给`Reader`或`Writer`。如果`SASLMechanism`字段为`nil`，他将不会使用SASL认证。

#### SASL 认证类型
##### Plain
```go
mechanism := plain.Mechanism{
    Username: "username",
    Password: "password",
}
```
##### SCRAM
```go
mechanism, err := scram.Mechanism(scram.SHA512, "username", "password")
if err != nil {
    panic(err)
}
```

#### 连接
```go
mechanism, err := scram.Mechanism(scram.SHA512, "username", "password")
if err != nil {
    panic(err)
}

dialer := &kafka.Dialer{
    Timeout:       10 * time.Second,
    DualStack:     true,
    SASLMechanism: mechanism,
}

conn, err := dialer.DialContext(ctx, "tcp", "localhost:9093")
```
#### Reader
```go
mechanism, err := scram.Mechanism(scram.SHA512, "username", "password")
if err != nil {
    panic(err)
}

dialer := &kafka.Dialer{
    Timeout:       10 * time.Second,
    DualStack:     true,
    SASLMechanism: mechanism,
}

r := kafka.NewReader(kafka.ReaderConfig{
    Brokers:        []string{"localhost:9092","localhost:9093", "localhost:9094"},
    GroupID:        "consumer-group-id",
    Topic:          "topic-A",
    Dialer:         dialer,
})
```
#### Writer
```go
mechanism, err := scram.Mechanism(scram.SHA512, "username", "password")
if err != nil {
    panic(err)
}

// Transports are responsible for managing connection pools and other resources,
// it's generally best to create a few of these and share them across your
// application.
sharedTransport := &kafka.Transport{
    SASL: mechanism,
}

w := kafka.Writer{
	Addr:      kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
	Topic:     "topic-A",
	Balancer:  &kafka.Hash{},
	Transport: sharedTransport,
}
```
#### 客户端
```go
mechanism, err := scram.Mechanism(scram.SHA512, "username", "password")
if err != nil {
    panic(err)
}

// Transports are responsible for managing connection pools and other resources,
// it's generally best to create a few of these and share them across your
// application.
sharedTransport := &kafka.Transport{
    SASL: mechanism,
}

client := &kafka.Client{
    Addr:      kafka.TCP("localhost:9092", "localhost:9093", "localhost:9094"),
    Timeout:   10 * time.Second,
    Transport: sharedTransport,
}
```
### 读取一个时间范围内的所有消息
```go
startTime := time.Now().Add(-time.Hour)
endTime := time.Now()
batchSize := int(10e6) // 10MB

r := kafka.NewReader(kafka.ReaderConfig{
    Brokers:   []string{"localhost:9092", "localhost:9093", "localhost:9094"},
    Topic:     "my-topic1",
    Partition: 0,
    MinBytes:  batchSize,
    MaxBytes:  batchSize,
})

r.SetOffsetAt(context.Background(), startTime)

for {
    m, err := r.ReadMessage(context.Background())

    if err != nil {
        break
    }
    if m.Time.After(endTime) {
        break
    }
    // TODO: process message
    fmt.Printf("message at offset %d: %s = %s\n", m.Offset, string(m.Key), string(m.Value))
}

if err := r.Close(); err != nil {
    log.Fatal("failed to close reader:", err)
}
```

### 日志
为了了解Reader/Writer类型的操作，可在创建时配置logger。

#### Reader
```go
func logf(msg string, a ...interface{}) {
	fmt.Printf(msg, a...)
	fmt.Println()
}

r := kafka.NewReader(kafka.ReaderConfig{
	Brokers:     []string{"localhost:9092", "localhost:9093", "localhost:9094"},
	Topic:       "my-topic1",
	Partition:   0,
	Logger:      kafka.LoggerFunc(logf),
	ErrorLogger: kafka.LoggerFunc(logf),
})
```
#### Writer
```go
func logf(msg string, a ...interface{}) {
	fmt.Printf(msg, a...)
	fmt.Println()
}

w := &kafka.Writer{
	Addr:        kafka.TCP("localhost:9092"),
	Topic:       "topic",
	Logger:      kafka.LoggerFunc(logf),
	ErrorLogger: kafka.LoggerFunc(logf),
}
```


### 测试
后续 Kafka 版本中的细微行为变化导致一些历史测试中断，如果您针对 Kafka 2.3.1 或更高版本运行，导出 `KAFKA_SKIP_NETTEST=1` 环境变量将跳过这些测试。
在本地通过docker运行Kafka
```go
docker-compose up -d 
```
运行测试
```shell
KAFKA_VERSION=2.3.1 \
  KAFKA_SKIP_NETTEST=1 \
  go test -race ./...
```
