[github](https://github.com/yitter/IdGenerator)

#snowflake
看文档，说上面解决了雪花的时间回溯问题。
这个问题呢，源自于雪花实现的漏洞，雪花ID实现为：
将int的64位进行拆分，分别分给
- 41bit 时间戳
- 10bit workID
- 12bit 自增序列
自增序列为每一秒重置为0。
可以看到，其实现是重度依赖时间戳相关。

将在以下情况中，出现问题
1. 当前机器时间为 2022-11-11 11:11:11
2. 当运维同事使用`ntpdate`更新服务器时间，可能会导致时间回拨，比如变成 2022-11-11 11:11:10
3. 那根据其逻辑，每一秒或毫秒重置时间戳，将会导致其有两个相同的时间戳，并且都从0开始递增。

那根据这个原理，我们看一看当前库

### IdGenerate
其号称能解决时间回拨问题。
> ✔ 支持时间回拨处理。比如服务器时间回拨1秒，本算法能自动适应生成临界时间的唯一ID。

咱们在上面已经知道了为什么会出现时间回拨问题，那么我们可以根据其代码看一看到底是怎么调整的。

其支持回退的结构体实现为
```go
// SnowWorkerM1 .
type SnowWorkerM1 struct {
	BaseTime          int64  // 基础时间
	WorkerId          uint16 // 机器码
	WorkerIdBitLength byte   // 机器码位长
	SeqBitLength      byte   // 自增序列数位长
	MaxSeqNumber      uint32 // 最大序列数（含）
	MinSeqNumber      uint32 // 最小序列数（含）
	TopOverCostCount  uint32 // 最大漂移次数
	_TimestampShift   byte
	_CurrentSeqNumber uint32

	_LastTimeTick           int64
	_TurnBackTimeTick       int64
	_TurnBackIndex          byte
	_IsOverCost             bool
	_OverCostCountInOneTerm uint32
	// _GenCountInOneTerm      uint32
	// _TermIndex              uint32
	sync.Mutex
}
```
获取ID操作
```go
// NextId .
func (m1 *SnowWorkerM1) NextId() int64 {
	m1.Lock()
	defer m1.Unlock()
	if m1._IsOverCost {
		return m1.NextOverCostId()
	} else {
		return m1.NextNormalId()
	}
}
```
处理时间回拨部分应该与`_TurnBackTimeTick` 有关，其调用部分在 normal()中
```go
// NextNormalID .
func (m1 *SnowWorkerM1) NextNormalId() int64 {
	currentTimeTick := m1.GetCurrentTimeTick()
	if currentTimeTick < m1._LastTimeTick {
		if m1._TurnBackTimeTick < 1 {
			m1._TurnBackTimeTick = m1._LastTimeTick - 1
			m1._TurnBackIndex++
			// 每毫秒序列数的前5位是预留位，0用于手工新值，1-4是时间回拨次序
			// 支持4次回拨次序（避免回拨重叠导致ID重复），可无限次回拨（次序循环使用）。
			if m1._TurnBackIndex > 4 {
				m1._TurnBackIndex = 1
			}
			m1.BeginTurnBackAction(m1._TurnBackTimeTick)
		}

		// time.Sleep(time.Duration(1) * time.Millisecond)
		return m1.CalcTurnBackId(m1._TurnBackTimeTick)
	}

	// 时间追平时，_TurnBackTimeTick清零
	if m1._TurnBackTimeTick > 0 {
		m1.EndTurnBackAction(m1._TurnBackTimeTick)
		m1._TurnBackTimeTick = 0
	}

	if currentTimeTick > m1._LastTimeTick {
		m1._LastTimeTick = currentTimeTick
		m1._CurrentSeqNumber = m1.MinSeqNumber
		return m1.CalcId(m1._LastTimeTick)
	}

	if m1._CurrentSeqNumber > m1.MaxSeqNumber {
		m1.BeginOverCostAction(currentTimeTick)
		// m1._TermIndex++
		m1._LastTimeTick++
		m1._CurrentSeqNumber = m1.MinSeqNumber
		m1._IsOverCost = true
		m1._OverCostCountInOneTerm = 1
		// m1._GenCountInOneTerm = 1

		return m1.CalcId(m1._LastTimeTick)
	}

	return m1.CalcId(m1._LastTimeTick)
}
```
- currentTimeTick 为机器的当前时间
- `m1._LastTimeTick` 为上次的时间
- `m1._TurnBackIndex` 为回拨时间的次数
	- 每次回拨叠加，当超过4时，重置回1
- `m1._TurnBackTimeTick` 
	- 第一次时间回拨，将初始化为`_LastTimeTick-1`
	- 这个操作可以理解为，往回1ms的时间，并且将其回拨下标添加进去，抛弃下标递增。当回拨频率过高，可能会出现重复
	- 如果时间一直没跟上，将一直递减（可能递减到负值）。届时也将出现重复，当然此情况较为特殊，要求在当前时间回到`m1._LastTimeTick`之前发生。
		- 假设请求恒定，在出现较大时间偏移时，触发的可能性更大。

上面变量将会出现以下问题
- 回拨次数够多，超过4，并且每次回拨相间隔时间较短，由于是`m1._turnBackTimeTick`递减，将会导致 `m1._TurnBackIndex`与 `m1._TurnBackTimeTick 重复。
- 当机器发生重启时的`ntpdate`将会无法处理。

#### 回拨频率过高
假设生成为  
- 42bit 时间 `000111111111111111111111111111111111111111`
- 8bit 工作id `00000001`
- 2bit 轮播时间 `00`
- 12bit 下标`0000000000001`

第一次回拨
`_TurnBackTimeTick` : `000111111111111111111111111111111111111110`
`_WorkID` : `00000001` 
`_TurnBackIndex`: `01`
`_CurrentSeqNumber`: `0000000000000`

追平
`_LastTimeTick` : `000111111111111111111111111111111111111111`
`_WorkID` : `00000001` 
`_TurnBackIndex`: `01`
`_CurrentSeqNumber`: `0000000000002`

第二次回拨
`_LastTimeTick` : `000111111111111111111111111111111111111110`
`_WorkID` : `00000001` 
`_TurnBackIndex`: `10`
`_CurrentSeqNumber`: `0000000000000`

追平
`_LastTimeTick` : `000111111111111111111111111111111111111111`
`_WorkID` : `00000001` 
`_TurnBackIndex`: `10`
`_CurrentSeqNumber`: `0000000000003`

第三次回拨
`_LastTimeTick` : `000111111111111111111111111111111111111110`
`_WorkID` : `00000001` 
`_TurnBackIndex`: `11`
`_CurrentSeqNumber`: `0000000000000`

追平
`_LastTimeTick` : `000111111111111111111111111111111111111111`
`_WorkID` : `00000001` 
`_TurnBackIndex`: `11`
`_CurrentSeqNumber`: `0000000000004`

第四次回拨
`_LastTimeTick` : `000111111111111111111111111111111111111110`
`_WorkID` : `00000001` 
`_TurnBackIndex`: `01`
`_CurrentSeqNumber`: `0000000000000`

这里就直接出现重复了

