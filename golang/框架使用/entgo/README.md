当前为ent的学习笔记。


什么是ent？ent是什么？

是啥我也不知道，刚开坑，什么东西都不懂。根据了解，这是一款orm(数据库映射)库。

咦，那岂不是跟gorm一样吗？但看概念，好像更加复杂一点。这上面像是个图概念，有点，有边的概念。

为什么我会学习entgo？ 因为我看某tg群里，很多人吹这技术，说用entgo+gqlgen写业务代码，爽的不要不要的。

下面开始仔细研究是什么。

官网 [entgo.io](https://entgo.io/)
文档 [docs](https://entgo.io/docs/getting-started)

本教程以MySQL为基础（其他的我也不会

### 流程

根据官方文档介绍。当前使用流程为：

1. 初始化数据结构
	- 初始化一个图（MySQL表，在go中表现为结构体）
	- 给该结构体Field方法添加字段
	- 添加边（MySQL关联外键）
	- 调用`go generate ./ent` 将会直接生成该表的CRUD语句。
2. 创建客户端连接（Mysql）
	- `client, err := ent.Open("mysql", "<user>:<pass>@tcp(<host>:<port>)/<database>?parseTime=True")`
3. 在需要操作数据库的地方调用生成的内容

上面就是一个完整的调用逻辑

#### 初始化数据结构

TODO 初始化数据结构操作


