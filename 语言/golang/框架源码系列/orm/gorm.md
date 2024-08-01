# gorm



go 主流的的orm框架。

文档：[https://gorm.io](https://gorm.io/)

源码：https://github.com/go-gorm/gorm

由于公司内部db的封装问题，不便于处理 transaction，因此想通过gorm来学习他事务的设计，以及文档中描述的"Nested Transactions"（嵌套事务）。



由于有使用经历，因此会找几个关键方法去看

- gorm.Open && mysql.Open(dsn)
  - 创建 gorm.DB，其中支持多种数据库结构，我们目标为MySQL
- Transaction
  - 嵌套事务
- Where
  - 其中in实现



其封装实现如下：





#### 



#### Transaction / Begin

此时我们认为db为使用gorm.Open初始化的db。

其db.clone默认为1。



[Begin](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/finisher_api.go#L662-L688)做了如下操作：

```go
db.getInstance().Session(&Session{Context: db.Statement.Context, NewDB: db.clone == 1})
```

其中getInstance在`db.clone==1`的情况下，将创建一个新的gorm.DB。

```go
tx := &DB{Config: db.Config, Error: db.Error}

if db.clone == 1 {
    // clone with new statement
    tx.Statement = &Statement{
        DB:        tx,
        ConnPool:  db.Statement.ConnPool,
        Context:   db.Statement.Context,
        Clauses:   map[string]clause.Clause{}, 
        Vars:      make([]interface{}, 0, 8),
        SkipHooks: db.Statement.SkipHooks,
    }
    if db.Config.PropagateUnscoped {
        tx.Statement.Unscoped = db.Statement.Unscoped
    }
} 
...
return tx
```

调用Session方法时 NewDB参数为 1（`db.clone == 1`）

Session方法在这里什么都没做，就是根据传入的config进行了一轮配置，将clone置为1。

初始化一个Tx之后，对`tx.Statement.ConnPool`具体实现的类型的额外支持进行判断（判断是否支持TxBeginner，还是支持ConnPoolBeginner，若都不支持则报错。）

```go
switch beginner := tx.Statement.ConnPool.(type) {
	case TxBeginner:
		tx.Statement.ConnPool, err = beginner.BeginTx(tx.Statement.Context, opt)
	case ConnPoolBeginner:
		tx.Statement.ConnPool, err = beginner.BeginTx(tx.Statement.Context, opt)
	default:
		err = ErrInvalidTransaction
}
```

[ConnPool](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L33-L39)定义了以下接口

```go
type ConnPool interface {
	PrepareContext(ctx context.Context, query string) (*sql.Stmt, error)
	ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...interface{}) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...interface{}) *sql.Row
}
```

用以判断其具体实现是否实现了下述任一接口。

[TxBeginner](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L47-L50)

```go
type TxBeginner interface {
	BeginTx(ctx context.Context, opts *sql.TxOptions) (*sql.Tx, error)
}
```

[ConnPoolBeginner](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L52-L55)

```go
type ConnPoolBeginner interface {
	BeginTx(ctx context.Context, opts *sql.TxOptions) (ConnPool, error)
}
```

若是支持则直接调用并存入对应 tx.Statement.ConnPool

如此，我们可以通过猜测得到图：

![gorm.drawio](E:\note\语言\golang\框架源码系列\orm\gorm.assets\gorm.drawio.png)



接下来我们验证猜测，找出BeginnTx是谁实现的，且是如何实现的（此处跳回 gorm.Open）



#### gorm.DB

其外层调用如下：

```go
dsn := "gorm:gorm@tcp(localhost:9910)/gorm?loc=Asia%2FHongKong" // invalid loc
_, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
```

看其内部与Statement.ConnPool相关代码，猜测下述代码有对其进行初始化以及实现。

```go
err = config.Dialector.Initialize(db)
```

其`Dialector`，是`mysql.Open`生成，因此我们查看该内容。

[Dialector.Initialize](https://github.com/go-gorm/mysql/blob/c829f6e3d7f916190f9ab96fc75ffdd89188bd39/mysql.go#L110-L191)

其具体实现为这句：

```go
db.ConnPool, err = sql.Open(dialector.DriverName, dialector.DSN)
```

因此，得出结论，第二轮的时候是 sql.Tx，其没有实现`TxBeginner` / `ConnPoolBeginner` 因此会产生报错。



接下来可以考虑看下 Transaction的具体实现，其对此描述为支持 Nested Transaction（嵌套事务）。



#### Where 

了解 Where 实现，能让我们更好的封装底层。