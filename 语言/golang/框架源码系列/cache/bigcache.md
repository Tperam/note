## 流程

### set操作

1. BigCache 根据hash定位到shards
2. `cacheShard.set()`
   1. `cacheShard.lock.Lock(0)`上锁
   2. 判断是否曾经设置过`key`
      - 设置过则删除。
   3. `Peek()` 还没看懂
   4. 包装`Entry` （约等于`freecache.EntryHdr`）
      1. 8byte 时间
      2. 8byte hash
      3. 2byte keyLength
      4. key
      5. entry
   5. 循环
      1. 存放到`entries`中
         1. 获取所需的`Entry`大小
            - 这里将会根据`Entry`大小而增加不同的字节
            - <127  增加1个字节
              - *1<<7-1*
            - < 16382 增加2个字节
              - *1<<14-2*
            - < 2097149 增加3个字节
              - 1<<21 -3*
            - < 268435452 增加4个字节
              - *1<<28 -4*
            - 默认：占用5个字节
         2. 判断
            - 可以从尾部插入？
            - 可以从头部插入？
              - 调整插入指针
            - 内存是否不够？
              - return err
            - 重新分配内存。
              - 调整插入指针
         3. 往`q.tail`插入数据
         4. 将需要的长度（这里为`Entry`大小+`header`长度）写入`headerEntrySize`中
         5. 将`headerEntrySize`动态复制到存放数据的地方
         6. 将`data`复制到存放数据的地方
      2. 保存到`hashmap`中，`hashmap[hashkey] -> array[keyIndex]`
      3. 如果没有存下，则代表容量不够，删除老Key
         1. 定位方式使用

-----



## 对象

### `BigCache`对象

- 门面设计模式
- shards为主要存储对象
- 其他参数为辅助对象。
- 处理第一次分割

```go
type BigCache struct {
	shards     []*cacheShard
	lifeWindow uint64
	clock      clock
	hash       Hasher
	config     Config
	shardMask  uint64
	close      chan struct{}
}
```

-----

### `cacheShard`对象

- 内部操作加锁。
- 用来管理`kv`的结构体

```go
type cacheShard struct {
	hashmap     map[uint64]uint32 // 标记数据位置
	entries     queue.BytesQueue // 存放数据位置
	lock        sync.RWMutex // 读写锁
	entryBuffer []byte // 缓存
	onRemove    onRemoveCallback 

	isVerbose    bool
	statsEnabled bool
	logger       Logger
	clock        clock
	lifeWindow   uint64

	hashmapStats map[uint64]uint32
	stats        Stats
}
```

-----

### `BytesQueue`对象

- 用来存放`kv`的结构体

```go
type BytesQueue struct {
	full         bool
	array        []byte // 具体数据
	capacity     int
	maxCapacity  int
	head         int
	tail         int
	count        int
	rightMargin  int
	headerBuffer []byte // 缓冲数据
	verbose      bool
}
```

-----

## 整体描述

- 功能没有`freecache`齐全，代码阅读难度也不高
- 淘汰策略遵循先进先出。



## 学习

- binary包。用于填写该Entry长度。

  - PutUvarint

    ```go
    func PutUvarint(buf []byte, x uint64) int {
    	i := 0
    	for x >= 0x80 {
    		buf[i] = byte(x) | 0x80
    		x >>= 7
    		i++
    	}
    	buf[i] = byte(x)
    	return i + 1
    }
    ```

  - Uvarint

    ```go
    func Uvarint(buf []byte) (uint64, int) {
    	var x uint64
    	var s uint
    	for i, b := range buf {
    		if b < 0x80 {
    			if i >= MaxVarintLen64 || i == MaxVarintLen64-1 && b > 1 {
    				return 0, -(i + 1) // overflow
    			}
    			return x | uint64(b)<<s, i + 1
    		}
    		x |= uint64(b&0x7f) << s
    		s += 7
    	}
    	return 0, 0
    }
    ```

  - 这两个方法很神奇

  - 一个存放时，只按照`1<<7-1`来存放数据，还有一位用来标识是否有进位，进位时`1<<8`被填充标记。

  - 一个取出时，判断该`byte`是否大于`1<<8`，大于则代表需要继续向下读。

