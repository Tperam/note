# GC

GC 全称Garbage Collection，就是用来回收已经不需要使用的变量，使得内存可已被重复使用。GC的对象是堆内存，栈内存使用完之后直接弹出了，不需要进行回收。

> [聊聊JVM和Golang的GC](https://zhuanlan.zhihu.com/p/357289119)
>
> [golang gc 主讲写入、删除屏障](https://golang.design/under-the-hood/zh-cn/part2runtime/ch08gc/barrier/)
>
> [golang gc 简单易懂版](https://zhuanlan.zhihu.com/p/334999060)

查找垃圾的方式：

1. 计数引用
2. 根搜索（根可达）

回收垃圾的方式：

1. 标记回收（三色标记）
2. 复制回收
3. 标记压缩

JAVA中垃圾回收

1. CMS 标记清除
2. serial 单线程
3. Parallel 多线程清除
4. ParaNew 新版本多线程清除
5. G1
6. ZGC



## 查找垃圾的方式

### 计数引用

计数引用就是根据当前对象被引用的次数进行计数。

当该对象被引用时，计数+1，当该对象引用被解除时，计数-1。每次只需要将引用为0的对象给回收即可。

### 根搜索

根搜索的原理，从方法栈帧开始遍历，找出哪些变量被引用，被引用的则为正在使用的，不可回收，而剩下没被引用的则为垃圾，可以回收。

### JAVA中的垃圾回收：

#### CMS

> [剖析cms原理](https://zhuanlan.zhihu.com/p/54286173)

标记清除，分为多个阶段。

1. 初始化标记
2. 并发标记
3. 重新标记
4. 并发清除
5. 并发重置

##### 初始化标记

暂停应用程序线程，遍历**GC ROOTS直接可达的对象**并将其压入**标记栈(mark-stack)。标记完之后恢复应用程序线程。**

##### 并发标记

这个阶段虚拟机会分出若干线程(GC 线程)去进行并发标记。标记哪些对象呢，标记那些**GC ROOTS最终可达的对象**。具体做法是推出**标记栈**里面的对象，然后递归标记其**直接引用的子对象**，同样的对子对象进行标记。

在本流程中，可能会出现新增对象、删除对象、变更对象等操作。这些操作会直接或间接的导致漏标。

##### 重新标记

由于有漏标的概念，CMS采用一种 写屏障+增量更新方式。主要原理为将出现变动的元素完全重新扫描。

##### 并发清除

清除相关的垃圾

#### G1



### 概念

#### 漏标

漏标是指在标记过程中，所产生的新对象、与老对象的指针改变。

例如：

栈上只有ABC三个变量，开辟的是一个连续的空间， A在第一位，B在第二位，C在第三位，此时A指向`堆D`，C指向`堆E`。
在这时GC开始了标记，并且已对A扫描完毕，开始扫描B的时候，代码中做了如下操作

```java
Person tmp = a;
a = c;
c = tmp;
```
当B扫描完之后，开始扫描C的时候，C指向`堆D`，A指向`堆E`，但由于GC并不知道原先的具体情况，所以再次对`堆D`进行标记。当C被扫描完毕后结束标记流程，开始清除流程。

这时就会导致`堆E`被漏标。

## go GC

### 概念

Go的GC主要是对指针进行遍历扫描操作。

它的逻辑思维就是先对堆栈进行扫描，扫描什么呢，扫描的就是指针。当你出现指针时，gc就会对其进行处理，向内继续进行扫描。

> [因为指针而导致GC压力的测试用例](https://syslog.ravelin.com/further-dangers-of-large-heaps-in-go-7a267b57d487)

看了以上案例，我们需要尽量减少指针程序中的指针，来减轻GC的负担。



GO的GC其实非常简单，从大体上看，我们可以理解为分为两个阶段

1. 标记阶段
2. 清理阶段

### 标记阶段

而标记阶段，因为可能出现的问题不同，而分为了两个阶段

1. 标记阶段
2. STW扫描阶段

#### 标记阶段

可以说是并发标记阶段，主要操作就是对于堆栈上的指针进行扫描，将其全部遍历一轮并对其标记。在此时程序还可以正常运行，程序正常运行就会出现变量新增，旧变量修改，变量交换等赋值类操作。

那再这时，Go为了避免漏标、错标等问题，Go使用了写屏障技术。该技术就是当你在扫描标记阶段时，当你变量发生赋值操作，将会记录到某片空间，表示当前变量不参与本轮清理，参与下轮清理。

#### STW标记阶段

由于为了处理漏标、错标等问题，Go使用了写屏障技术，但可能有大量的变量出现赋值操作，就会导致每轮GC的收益都很低。在这时，就有了混合写屏障技术，该技术就是会根据一定条件，去决定是否重新遍历部分赋值的变量（考虑遍历成本），并且为了避免再次产生大量的赋值操作。该阶段将会暂停整个程序，并对符合条件的变量进行重新的遍历。

### 清理阶段

清理阶段就是根据上面STW标记阶段的结果，进行快速的内存清理释放等。
