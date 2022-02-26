# free cache



## 整体流程

### 初始化操作

1. 设置初始化`freecache`中键值对的内存大小，最少`512 * 1024` (512kiB)

2. 设置一个`timer`对象

3. 初始化`segmentCount`个`segments`对象

   - `segmentCount`默认值为256
      - 该值必须为2的倍数
      - 该值与 `segmentAndOpVal`绑定
      - `segmentAndOpVal` = `segmentCount-1`

   - 初始化时需要传入参数
     - `bufsize` 缓存大小
       - `size/segmentCount`
     - `segID` 编号
     - `timer`  时间接口实现
       - 可以做一定的优化，比如我们不需要非常精确的时间，那我们可以自己做一个`Timer`的实现，
       - 比如我们只需要一个小时同步一次，我们可以自己写一个`goroutine`每小时去更新，然后该`Timer`的实现就只需要将一个该变量返回，减少了系统调用。



### get



### set

1. 使用`hashFunc` 计算出一个`hashCode`

2. 通过 `hashVal & segmentAndOpVal` 获取到`segID`

   - `segmentAndOpVal` 当前值可以理解为是一个掩码。值为 255
   - 当你拿任意数 `&255`时，只会得到 255以下的值

3. 上锁 `cache.locks[segID].Lock()`

4. 调用该分区的`set`方法 `cache.segments[segID].set(key, value, hashVal, expireSeconds)`

   - `segment.set`

     1. 判断key 是否大于 65535，大于则返回错误

     2. 获取最大的`key+value`的长度

        - `maxKeyValLen := len(seg.rb.data)/4 - ENTRY_HDR_SIZE`
          - 每个`segement`的数据 / 4 - 24

     3. 判断是否超出长度

     4. 记录相关过期时间。

     5. 获取`slotID` 并根据得到的`slotID`获取对应部分的`[]entryPtr`

        - 算法如下

          - 获取 `slotID`

            ```go
            slotID := uint8(hashVal >> 8)
            ```

          - 获取`entryPtr`

            ```go
            slotOff := int32(slotId) * seg.slotCap // slot 位置的偏移量
            return seg.slotsData[slotOff : slotOff+seg.slotLens[slotId] : slotOff+seg.slotCap] // slot 偏移量中的该区间数据
            // [offset: offset+该slot长度: 下一个slot的起始点]
            // 第三个部分为切割后该slice的容量
            ```

            - `slotCap` 等于一个`slot`的最大容量

     6. `lookup` 获取`hash16` 并根据得到的 `hash16 `去 `slot ` 中获取的 `[]entryPtr` 比对。

        1. 二分查找插入点。

        2. 判断插入`key`是否与插入的点相同

           ```go
           match = int(ptr.keyLen) == len(key) && seg.rb.EqualAt(key, ptr.offset+ENTRY_HDR_SIZE)
           // 先比对长度，长度符合则取读取 data部分，比对详细的key
           ```

     7. 初始化头信息 `entryHdr`

        -  此处会出现内存分配（有待考究）

          ```go
          var hdrBuf [ENTRY_HDR_SIZE]byte
          hdr := (*entryHdr)(unsafe.Pointer(&hdrBuf[0]))
          ```

     8. 根据上面的`lookup`，我们会得到一个结果，是否匹配上，与相应的idx

        - 匹配上了

          1. 读取他的`entryHdr`元素

          2. 更新`entryHdr`相关元素

             ```go
             hdr.slotId = slotId
             hdr.hash16 = hash16
             hdr.keyLen = uint16(len(key))
             originAccessTime := hdr.accessTime
             hdr.accessTime = now
             hdr.expireAt = expireAt
             hdr.valLen = uint32(len(value))
             ```

          3. 比对 `ValCap` 和 `ValLen` `hdr.valCap > hdr.ValLen` 

             - true 则直接写入数据并结束方法
             - false 则删除该`entryPtr`，同时成倍增加`ValCap`，直到能存下`ValLen`。

        - 没匹配上

          1. 初始化头操作

             ```go
             hdr.slotId = slotId // slot id 号
             hdr.hash16 = hash16 // hash 值记录
             hdr.keyLen = uint16(len(key)) // key长度
             hdr.accessTime = now // 访问时间
             hdr.expireAt = expireAt // 过期时间
             hdr.valLen = uint32(len(value)) // value长度
             hdr.valCap = uint32(len(value)) // value cap
             if hdr.valCap == 0 { // avoid infinite loop when increasing capacity.
                 hdr.valCap = 1
             }
             ```
        
     9. 记录键值对的长度

     10. 判断slot是否需要进行修改（较为复杂）

         - 主要是当前可用空间小于当前 key value 所需要的空间时触发。
           - 此处很重要，可以用来学习内存管理。
           - 对部分`kv`进行回收
             - 回收最少使用的
             - 已经过期的等状态。
             - 每循环5个key强制删除第五个`kv`
         - 此处主要思想就是给新插入的`kv`腾格子
           - 其实现方式类似与 gc 的 `coping`
           - 将当前`seg`下的所有`kv`遍历，判断是否出现回收条件，没有则将其重新写入`data`，同时改变`entryPtr`的`offset`
         - 最终结果就是`ringBuf`的`index`是可以直接写入的位置。

     11. 插入值`entryHdr`

     12. 插入key

     13. 插入value

     14. 由于value 可能预分配了 Cap，所以此处还要再调整指针，给cap预留足够的空间。

     15. 减少可分配空间值 `segment.vaccumlen`

5. 解锁



## 整体对象描述

### `Cache`对象

- freecache 的实现
- 处理对外的调用

- 内部结构体如下
  - `segments` 当前对象主要是对`key value`键值对的一个切割，分开治理。
    - 主要是为了减少锁的粒度
    - 在某些特定情况下，可以并行更新数据。
  - locks
    - 锁，每个`segment`都有相应的锁

```golang
// Cache is a freecache instance.
type Cache struct {
	locks    [segmentCount]sync.Mutex
	segments [segmentCount]segment
}
```

### `segment`对象

- 管理键值的地方
- 不是线程安全的
- 一个`segment`存放了256个`slot`

```golang
// a segment contains 256 slots, a slot is an array of entry pointers ordered by hash16 value
// the entry can be looked up by hash value of the key.
type segment struct {
	rb            RingBuf // ring buffer that stores data
	segId         int
	_             uint32 // 填充
	missCount     int64 // 未命中数
	hitCount      int64 // 命中数
	entryCount    int64 // 键值对数量
	totalCount    int64      // number of entries in ring buffer, including deleted entries. // 总键值对数量，包括删除的
	totalTime     int64      // used to calculate least recent used entry. // 用于计算最后使用的 键值对
    timer         Timer      // Timer giving current time // timer实现，主要是对于time.Now() 调用的优化，可能暂时没有很好的库。
	totalEvacuate int64      // used for debug 
	totalExpired  int64      // used for debug
	overwrites    int64      // used for debug
	touched       int64      // used for debug
	vacuumLen     int64      // up to vacuumLen, new data can be written without overwriting old data.  // 这个算是当前segment的剩余长度
	slotLens      [256]int32 // The actual length for every slot.
	slotCap       int32      // max number of entry pointers a slot can hold.
	slotsData     []entryPtr // shared by all 256 slots
}

```

-----

### `RingBuf`对象

- 数据的存储点。

```go
	begin int64 // beginning offset of the data stream.
	end   int64 // ending offset of the data stream. // 写入之后值++
	data  []byte // 具体数据
	index int //range from '0' to 'len(rb.data)-1' // 当前写入下标
}
```

- 对于此对象，我们需要把他想象成一个环。
  - 正常的 key 会是顺序的， 0:512, 512:1024
  - 不正常的环会是这样的 (此处假定`slot`最大容量为2048)
    - 1736:200，也就是 1736:2048 与 0:200

-----

### `entryPtr` 对象

- 键值对 基本信息
  - 偏移位置
  - hash16 值
  - key长度
- 用于记录当前键值在`ringBuf`中的位置
- 每次进来，先使用`hash16`进行对比，如果成功，继续使用`KeyLen`对比，如果还是成功，则当成一个键值对处理。

```golang
// entry pointer struct points to an entry in ring buffer
type entryPtr struct {
	offset   int64  // entry offset in ring buffer //偏移量
	hash16   uint16 // entries are ordered by hash16 in a slot.// hash 值
	keyLen   uint16 // used to compare a key // key 长度
	reserved uint32 // 保留的？
}
```

-----

### `entryHdr`对象

- 键值对 头信息

```go
// entry header struct in ring buffer, followed by key and value.
type entryHdr struct {
	accessTime uint32 // 访问时间
	expireAt   uint32 // 过期时间
	keyLen     uint16 // key 长度
	hash16     uint16 // hash16 值
	valLen     uint32 // value长度
	valCap     uint32 // value 容量
	deleted    bool // 是否删除
	slotId     uint8 // slot id
	reserved   uint16
}
```

-----

## 关键方法

### `segment.evacuate`

当前方法主要用于调整`index`写入指针，保证后续写入不会覆盖原有数据

原理如下

- 将`ringBuf`当成环
- 遍历`kv`键值对，根据该键值对状态，进行删除或重新写入，对index进行调整
- 最终会留出一片空间用于存放新的数据

流程如下

1. 首先，他会比对剩余空间 seg.vacuumLen 是否足够存下 key value 值

2. 存不下则进入循环

   1. 获取一个偏移量 `seg.rb.End() + seg.vacuumLen - seg.rb.Size()`
      - end  vacuumlen 会根据循环进行变化
        - End 是在当元素删除优先级较低时增加（是否过期，最近使用访问算法）
        - vacuumlen 会根据访问到的删除优先级高的key进行增加。（连续循环5次还没碰到可删除的key，将会强行删除当前key）
   2. 根据偏移获取`entryHdr`，根据其中状态向下走
      - 状态
        - 访问状态
        - 是否为第五个`key`（为了防止死循环，每碰到5会强删）
        - 是否已删除
        - 是否过期
      - 出现了以上状态
        1. 删除该`entryPtr`，将`entryHdr.deleted`标记为`true`
        2. `vaccumLen`加上该`kv`大小。
      - 没出现状态
        1. 将该`kv`重新写入，修改`entryPtr`的指针。

3. 当循环结束，我们的`index`的位置将可以直接写入值。

   

## 优化、可学习点

- segment 的管理
- LRU 相关算法
- 位运算操作
  - `hashVal & 255`
  - `mid > 1`
- 为什么不把`ringBuffer`提升到`freeCache`层？
  - 因为会对内部`Entry`做一定的移位操作
  - `freeCache`层不好管理
- 简单的拆分算法
  - cache -> segment
    - 使用 &   &255 得到相关的segment
  - segment -> slot
    - 使用 uint8强转，
    - 使用数据对齐的思想，从多个`slot`区域中的`[]entryPtr`，找到特定`slot`区域的`[]entryPtr`
  - slot -> hash16
    - 使用二分查找。
    - 有序插入。





## 建议优化点、问题思考



- segment 与 lock 绑定在相同的一个结构体中
  - 利用缓存行的机制



