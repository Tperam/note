# buffio. Reader



结构体如下:

```go
type Reader struct {
	buf          []byte
	rd           io.Reader // reader provided by the client
	r, w         int       // buf read and write positions
	err          error
	lastByte     int // last byte read for UnreadByte; -1 means invalid
	lastRuneSize int // size of last rune read for UnreadRune; -1 means invalid
}
```



此库提供了几个非常非常好用的方法

偷窥，不会影响指针

```go
func (b *Reader) Peek(n int) ([]byte, error) {}
```

指针跳跃，会将 r 变量偏移到 n个字节后

```go
func (b *Reader) Discard(n int) (discarded int, err error) {}
```

获取当时 已经写入的值，与读取的值

```go
func (b *Reader) Buffered() int { return b.w - b.r }
```





#### 场景

当前，我们在等待http请求，该http请求总大小为 250B

但一个完整的http请求分批发送。

第一次发送了 25 个B，第二次发送了100个B，第三次放松了125个B



如果我们没有Peek，大致代码如下：

```go
// 读取一个http请求
func(){
    // 此时在 r 中有一个 4096的byte
    r := bufio.NewReaderSize(readio,4096)
    // 外部一个用于接收的Byte
    httpRequest := make([]byte,0,4096)
    flag := false
    for !flag {
        // 有多少数据就读多少数据
        a,_ := r.Read(nil)
        flag = parseHTTP( a )
        httpRequest := append(a)
    }
}
```

以上代码有几个问题

- 多分配了一个 httpRequest



换成如下代码:

```go
// 读取一个http请求
func(){
    // 此时在 r 中有一个 4096的byte
    r := bufio.NewReaderSize(readio,4096)
    // 当前 a 没有分配内存，使用的是 bufio.Reader 中 buf 的内存
    // a 只是分配了一个指针，指向该片区域
    var a []byte
    flag := false
    for !flag {
        // 此时，有多少数据就读多少数据
        a,_ = r.Peek(r.Buffered())
        flag = parseHTTP( a )
    }
    r.Discard(len(a))
}
```



#### bufio.Reader 思路

其主要思路为

- 使用相同的一片空间，对其一直进行读取、写入操作
- 对外返回的值，也为该片内存的某块区域。
- 被标记为 r

读取出来的数据我们写入 buf 中。

此时分别有， r, w int 两个变量， 



r 介绍

- r = read poisition，读位置
- r 代表读取的位置，buf[:r] 部分代表已经读取的位置，可以被覆盖，可以被回收了。
- 未读部分： buf[ r:w ]
  - 已经写入的总值 - 已经读取的总值。



w介绍

- w = write position，写位置
- w 代表写的位置, buf[:w]代表我们已经写入了这写数据， 
- 未写入部分 buf[w:]
  - 后续我们可以将其进行重置。
    1. 假设现在 buf = 4096，已经写入 4000，已经读取3950。
    2. 现在进来一个 请求，大小为500 
    3. 当前肯定无法写入，因为 buf的大小为 4096，我们已经写了4000
    4. 但我们可以对已经读取 3950 字节进行回收。
    5. copy(buf,buf[r:w])
    6. 此时将会变成
    7. b[r:w] = b[0:50]
    8. 我们继续向下添加值
    9. copy(buf[50:],[]byte("输入进来的值") )

