## 整体流程

![zap](zap.png)

### 初始化日志

- 使用配置文件覆盖的方式进行build。（grpc类似，一种golang的创建模式。）
- 这个地方主要记住一个，`WriterSyncer`，`Encoder`
  - 主要内容通过`zapcore.NewCore`传入，本文最重要对象`Core`。（看源码时会经常碰到他）
- 可以 New 多个 core

### 调用写入

1. 外部写入日志操作 `logger.Write("hihi",...)`
2. 内部生成`Entry`，当前打印的头信息
3. 从`sync.Pool`获取`CheckEntry`，同时将`core`添加到`CheckEntry`中
   - 每打印一次日志，都会生成一个`CheckEntry`对象，对应zerolog中的`Event`
4. 由于上面可能添加了多颗核心，所以此处循环调用`zap.Core.Write`方法。
   - `Core`为初始化初始的核心。
   - 主要提供写、编码功能
5. `zap.Core.Write`内部通过配置的解码器进行编码
   - 所有传入字段都会变成 `zapcore.Field`

   - 原生提供了两个，（json、console）
   - json编码操作
     1. 克隆`jsonEncoder`对象（避免数据竞争。）
        1. 从`sync.Pool`中获取对象结构体
        2. 同时将配置导入对象。
        3. 从bufferpool 获取一个buf 对象
     2. 手动拼接 json ，不使用反射处理。（fastjson、quicktemplate）
        1. 添加日志Level到buf
           - `{"level":"info"`}
        2. 添加时间字段到buf（好像要配置）
        3. 添加所有传入字段到buf
           - 通过编码器将传入的`[]Field`进行编码
     3. 返回buf
6. 获取编码后的buf
7. 写入buf操作
   - 此操作，根据初始化的`core`中的`WriterSync`变量执行不同的策略。
   - 该策略可通过Hook重写，也可以通过自己新创建`zapcore.NewCore`使用。
   - 也可通过自己封装实现。
     - 默认是走输出流 `/dev/stdout`
8. 将buf放回`bufferpool`中
9. 完成本次操作

## 整体对象描述

`Logger` 对象

- 初始化后的结果
- 保存部分配置信息以及`Core`对象，在每次打印日志时，生成`CheckEntry`对象

```go
type Logger struct {
	core zapcore.Core // 核心部分，主要处理编码、写入文件操作

	development bool // 开发者模式
	addCaller   bool // 打印文件路径
	onFatal     zapcore.CheckWriteAction // default is WriteThenFatal // 当fatal后的调用

	name        string
	errorOutput zapcore.WriteSyncer

	addStack zapcore.LevelEnabler

	callerSkip int

	clock zapcore.Clock
}
```

`Core`对象

- 核心对象
- 处理
  - 编码
  - 文件写入

```go
type Core interface {
	LevelEnabler

	// With adds structured context to the Core.
	With([]Field) Core // 字段附带值
	// Check determines whether the supplied Entry should be logged (using the
	// embedded LevelEnabler and possibly some extra logic). If the entry
	// should be logged, the Core adds itself to the CheckedEntry and returns
	// the result.
	//
	// Callers must use Check before calling Write.
	Check(Entry, *CheckedEntry) *CheckedEntry // 
	// Write serializes the Entry and any Fields supplied at the log site and
	// writes them to their destination.
	//
	// If called, Write should always log the Entry and Fields; it should not
	// replicate the logic of Check.
	Write(Entry, []Field) error // 写入操作
	// Sync flushes buffered logs (if any).
	Sync() error // 同步操作
}
```

`Entry`对象

- 主要用于存放日志名称和部分基础信息，此处不处理字段信息。
- 在每次打印时生成
- 打印时附带的消息

```go
type Entry struct {
	Level      Level // 日志级别
	Time       time.Time // 时间
	LoggerName string // 日志名称
	Message    string // 信息
	Caller     EntryCaller // 日志路径
	Stack      string // 栈信息
}
```

`CheckedEntry`对象

- 每次打日志都会生成，可以说是打日志时的上下文
- 对应zerolog中的`Event`

```go
type CheckedEntry struct {
	Entry // 日志基础信息
	ErrorOutput WriteSyncer
	dirty       bool // best-effort detection of pool misuse
	should      CheckWriteAction //
	cores       []Core // 编码、写核心
}
```

`Field`对象

- 打印时附带的字段

```go
type Field struct {
	Key       string // 
	Type      FieldType // 类型 1数组, 2对象, 3二进制, 4bool
	Integer   int64
	String    string
	Interface interface{}
}
```

`Buffer`对象

- 每次打印日志都会生成
- 此对象内部包装了字节数组，用于存储最终打印值。
- 该对象通过`enc.EncodeEntry`返回。

```go
type Buffer struct {
	bs   []byte
	pool Pool
}
```

`jsonEncoder`对象

- 序列化对象
- 用于将`Field`对象最终序列化成二进制，写入文件。

```go
type jsonEncoder struct {
	*EncoderConfig
	buf            *buffer.Buffer // 缓冲buffer，该部分buffer通过
	spaced         bool // include spaces after colons and commas
	openNamespaces int

	// for encoding generic values by reflection
	reflectBuf *buffer.Buffer
	reflectEnc ReflectedEncoder
}
```



## 优化、可学习点

- json编码时不使用反射。

- 设计模式
  - 初始化操作（grpc的创建方式，毛剑讲过）

  - 日志编码设计（策略模式，可用json，可用console）

  - 写入操作接口化。（此处代理模式+策略模式）

    - 可以通过自行调用`zapcore.NewCore`实现写入指定路径文件。

    - 可以通过内部自带`BufferedWriteSyncer`实现缓冲写入。

    - 两者结合，内部写入自己指定的文件，外部通过`BufferedWriteSyncer`做个缓冲减少IO

    - ```go
      f := os.Open("./error.log")
      zapcore.NewCore(...,zapcore.BufferedWriteSyncer{WS: f},...)
      ```

    - 如果自己实现Buffered。可以使用`zapcore.Lock(f)`将其保证多线程化。

- buffer 使用方式

  - 内部封装了多个操作，用以添加各种类型
    - string
    - bool
    - time
    - byte
    - uint
    - int
    - float

- 并发写时，如何保证顺序性？

  - 底层 os.File 实现 内部自己上锁，单次传入值是完整的则可保证有序性。（不会出现将单行日志拆成多行）
  
- Clock 时钟

### zap中的Writer对象

zap中封装了部分的Writer对象。该逻辑使用代理模式，对外仅暴露 `type WriterSync interface`

- BufferedWriteSyncer
- multiWriteSyncer
- lockedWriteSyncer

#### BufferedWriteSyncer

其作用是在写入文件时添加一层缓冲，该缓冲减少了在非4K块时的写入，减少了IO次数。

同时内部定时自动刷新，减少丢日志的几率。（由于做了缓冲，肯定会出现丢日志的状况，此时为减少丢日志的数量，内部定时同步。默认30s一次）

同时带了一定的问题，由于我们增加了一个内存buffered，此时会碰到数据竞争（多线程写入）。所以，该方法在本地加了一个锁，用于避免数据竞争。

#### multiWriteSyncer

当你在同一颗core中，想声明了多个写入流，可以使用该方法包装一下，该方法只是用于简化代码

#### lockedWriteSyncer

该操作紧紧是给写入操作加了一把锁，也是用于简化代码的操作

外部可通过 `zapcore.Lock(WriterSyncer)`使用



### 并发写时保证顺序

无主要保护手段，默认根据初始化的Core进行实现。底层os.File是线程安全的。

#### 底层系统 os.File

首先，我看的这个是根据 `os.File` 的实现（`os.Stdout`）。

os.Stdout是一个`os.File`对象，其文件为`/dev/stdout` ，这是linux下的默认输出文件。

每个进程都有以下几个流

- Stdin `/dev/stdin`
- Stdout `/dev/stdout`
- Stderr `/dev/stderr`

经过zap一系列的字段解析以及buf申请。最终会调用到`out.Write`方法，该方法导向 `os.File `的`Write`

跟进源码，我们发现

调用os.File的写方法会调用 `f.pfd.write(b, off)`，其中的`write`方法将会对该`fd`文件上锁，将buf写入完整后才会进行解锁。此处就保证了输出的完整性以及顺序性。

其内部会做一次拆分，在windows下单次最大读写被标记为4GB（主要原因为 windows 下的api 使用uint32来传递文件大小。）

> [windows 下最大独写4GB 原因](https://github.com/golang/go/issues/26923)



### bufio.io

这个是标准库中提供的一个缓冲Io。里面的`Write`方法有一个特性。

特性如下

- 当写出数据大于可用`Bufferd`，同时`Buffered == 0` 

- 此时`Write`方法为了避免多次复制内存，将直接调用原生方法，将数据写入本地。

- ```go
  if b.Buffered() == 0 {
      // Large write, empty buffer.
      // Write directly from p to avoid copy.
      n, b.err = b.wr.Write(p)
  } else {
      n = copy(b.buf[b.n:], p)
      b.n += n
      b.Flush()
  }
  ```