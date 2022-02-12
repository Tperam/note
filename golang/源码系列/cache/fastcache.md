## 流程

### 初始化操作

其内部算法如下

将设置的字节+桶（`bucketesCount = 512`）的数量-1，然后除以桶数

```go
uint64((maxBytes + bucketsCount - 1) / bucketsCount)
```

对每个桶进行初始化

初始化桶时，计算桶大小（`chunkSize = 65535`，64k）

```go
(maxBytes + chunkSize - 1) / chunkSize
```

同时初始化 映射表，用于记录大小。



### set 操作

BigCache 根据hash定位到shards

验证`key`和`value`长度，是否超过 `1 << 16`

制作`kvLenBuf`

```go
// 栈上分配，用于记录 key 和 value长度
var kvLenBuf [4]byte
kvLenBuf[0] = byte(uint16(len(k)) >> 8)
kvLenBuf[1] = byte(len(k))
kvLenBuf[2] = byte(uint16(len(v)) >> 8)
kvLenBuf[3] = byte(len(v))
```

如果 `kv + 4byte`长度大于桶大小（65535）， 则退出

上锁

```go
b.mu.Lock()
```

初始化一些参数

```go
idx := b.idx // 当前键值下标
idxNew := idx + kvLen // 新的键值总长
chunkIdx := idx / chunkSize // 原来idx的分区
chunkIdxNew := idxNew / chunkSize // 新 idx 的分区
```

判断是否需要使用新的区块

```go
if chunkIdxNew > chunkIdx {
    // 判断是否超出范围
    if chunkIdxNew >= uint64(len(b.chunks)) {
        // 置为0，从头开始
        idx = 0
        idxNew = kvLen
        chunkIdx = 0
        // 代数+1
        b.gen++
        if b.gen&((1<<genSizeBits)-1) == 0 {
            b.gen++
        }
    } else {
        // 使用新的区块
        idx = chunkIdxNew * chunkSize
        idxNew = idx + kvLen
        chunkIdx = chunkIdxNew
    }
    // 新区快置空
    b.chunks[chunkIdx] = b.chunks[chunkIdx][:0]
}
```

获取相应的chunk（65535 byte）

```go
chunk := b.chunks[chunkIdx]
if chunk == nil {
    chunk = getChunk()
    chunk = chunk[:0]
}
```

写入

```go
chunk = append(chunk, kvLenBuf[:]...)
chunk = append(chunk, k...)
chunk = append(chunk, v...)
```

重新赋值`chunks`

```go
b.chunks[chunkIdx] = chunk
```

记录hash值

[24个bit存储迭代数，后40用于存放相应的`idx`（一般是够的，只要你单个`bucket`存放值小于`1<<40-1`）]

```go
b.m[h] = idx | (b.gen << bucketSizeBits)
```

更新 idx 位置。

```go
b.idx = idxNew
```



### get 操作

-----

计算hash值

获取到相应区间

```GO
idx := h % bucketsCount
```

调用相应`bucket`的`Get`方法

初始化部分参数，同时上读锁

```go
found := false
b.mu.RLock()
v := b.m[h]
bGen := b.gen & ((1 << genSizeBits) - 1)
```

判断参数是否存在

```go
if v > 0 {...}
```

如果存在，则进入内部处理

```go
gen := v >> bucketSizeBits // 获取v的代数
idx := v & ((1 << bucketSizeBits) - 1) // 具体的idx
// 如果 （当前代与kv的代相同，并且idx<b.idx） || （当前代与kv只差了一代，并且idx > b.idx） || （kv代是最大代，并且当前代为1，并且idx >= b.idx）
if gen == bGen && idx < b.idx || gen+1 == bGen && idx >= b.idx || gen == maxGen && bGen == 1 && idx >= b.idx {
    // 计算出具体的 chunk 位置
    chunkIdx := idx / chunkSize
    // 判断是否超出
    if chunkIdx >= uint64(len(b.chunks)) {
        // Corrupted data during the load from file. Just skip it.
        atomic.AddUint64(&b.corruptions, 1)
        goto end
    }
    // 获取相应的chunk
    chunk := b.chunks[chunkIdx]
    idx %= chunkSize
    if idx+4 >= chunkSize {
        // Corrupted data during the load from file. Just skip it.
        atomic.AddUint64(&b.corruptions, 1)
        goto end
    }
    // 读取 kv 长度头
    kvLenBuf := chunk[idx : idx+4]
    keyLen := (uint64(kvLenBuf[0]) << 8) | uint64(kvLenBuf[1])
    valLen := (uint64(kvLenBuf[2]) << 8) | uint64(kvLenBuf[3])
    idx += 4
    if idx+keyLen+valLen >= chunkSize {
        // Corrupted data during the load from file. Just skip it.
        atomic.AddUint64(&b.corruptions, 1)
        goto end
    }
    // 这里有优化，老快了
    if string(k) == string(chunk[idx:idx+keyLen]) {
        idx += keyLen
        if returnDst {
            // 又一个细节，dst 是从外面传入的，这代表着只要它的容量足够我们append，这里就不会产生分配，这个叫做append style
            dst = append(dst, chunk[idx:idx+valLen]...)
        }
        found = true
    } else {
        atomic.AddUint64(&b.collisions, 1)
    }
}
```



## 对象

### Cachce对象

- 线程安全的
- 相对于`map[string][]byte`来说，它的压力更小
- 使用创建，或从文件读取(`LoadFromFIle*`)

```go
type Cache struct {
	buckets [bucketsCount]bucket // bucketsCount 为常量，为512

	bigStats BigStats
}
```

-----

### bucket对象

```go
type bucket struct {
	mu sync.RWMutex

	// chunks is a ring buffer with encoded (k, v) pairs.
	// It consists of 64KB chunks.
	chunks [][]byte

	// m maps hash(k) to idx of (k, v) pair in chunks.
	m map[uint64]uint64

	// idx points to chunks for writing the next (k, v) pair.
	idx uint64

	// gen is the generation of chunks.
	gen uint64

	getCalls    uint64
	setCalls    uint64
	misses      uint64
	collisions  uint64
	corruptions uint64
}
```



-----

## 整体描述

相比于`freecache`，阅读难度最低，整体代码特别简单，功能也不多，具体底层依赖`map[uint64]uint64`。

不使用官方`map[string][]byte`的原因是他会产生较多的指针（`string`产生指针，`[]byte`产生指针）。在官方`map`中，如果你的`key`或`value`的类型是指针，或者附带指针类型，那么GC将会对其进行扫描，如果条目过多，就会导致扫描速度极低，GC压力过大，导致GC时间长，导致程序吞吐降低，延迟增加。

这里通过创建底层表`chunks [][]byte`，与映射表`map[uint64]uint64`，来避免大量指针的产生。其主要思想是认为在开发中`kv`不会非常大，我们把他们同一规划到一个底层表中`chunks [][]byte` 让一个`chunk`装载尽可能多的`kv`，达到减少`gc`扫描的目的。





## 学习

- 建立`bm`本地变量，减少循环中重复的解引用。编译器有优化在此处，但是底层数组不会收缩

  ```go
  bm := b.m
  for k := range bm {
      delete(bm, k)
  }
  ```

- byte与byte对比，编译器优化，使此处不会产生分配。

  ```go
  if string(k) == string(chunk[idx:idx+keyLen]) {}
  ```

- 方法定义， append style

  ```go
  func (b *bucket) Get(dst, k []byte, h uint64, returnDst bool) ([]byte, bool) {}
  ```

  这样的好处是能做最大优化，可以让外部用`sync.Pool`缓存池，减少对于`dst`的内存分配。
