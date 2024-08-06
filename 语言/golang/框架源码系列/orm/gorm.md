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
- 以及Find、Scan等函数扫Array数据时，创建切片方式。（是直接创建并append，还是计算其具体容量。

其封装实现如下：

### 事务流程



#### Begin

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

![gorm.drawio](\gorm.assets\gorm.drawio.png)



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



当然，有Begin就有Rollback 与 Commit，我们来粗略看看对应实现（猜测与上层实现一致）

#### [Rollback](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/finisher_api.go#L700-L710)

```go
func (db *DB) Rollback() *DB {
	if committer, ok := db.Statement.ConnPool.(TxCommitter); ok && committer != nil {
		if !reflect.ValueOf(committer).IsNil() {
			db.AddError(committer.Rollback())
		}
	} else {
		db.AddError(ErrInvalidTransaction)
	}
	return db
}
```

#### [Commit](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/finisher_api.go#L690-L698)

```go
func (db *DB) Commit() *DB {
	if committer, ok := db.Statement.ConnPool.(TxCommitter); ok && committer != nil && !reflect.ValueOf(committer).IsNil() {
		db.AddError(committer.Commit())
	} else {
		db.AddError(ErrInvalidTransaction)
	}
	return db
}
```



上述两个方法实现了[TxCommitter](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L57-L61)

```go
// TxCommitter tx committer
type TxCommitter interface {
	Commit() error
	Rollback() error
}
```

没什么意思，sql.Tx就是这么实现的的。



#### [Transaction](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/finisher_api.go#L617-L659)

接下来可以考虑看下 Transaction的具体实现，其对此描述为支持 Nested Transaction（嵌套事务）。

我们可以看到，如果当前的commiter已经支持了commit等操作，那么此时将会开启

```go
// Transaction start a transaction as a block, return error will rollback, otherwise to commit. Transaction executes an
// arbitrary number of commands in fc within a transaction. On success the changes are committed; if an error occurs
// they are rolled back.
func (db *DB) Transaction(fc func(tx *DB) error, opts ...*sql.TxOptions) (err error) {
	panicked := true

	if committer, ok := db.Statement.ConnPool.(TxCommitter); ok && committer != nil {
		// nested transaction
		if !db.DisableNestedTransaction {
			err = db.SavePoint(fmt.Sprintf("sp%p", fc)).Error
			if err != nil {
				return
			}
			defer func() {
				// Make sure to rollback when panic, Block error or Commit error
				if panicked || err != nil {
					db.RollbackTo(fmt.Sprintf("sp%p", fc))
				}
			}()
		}
		err = fc(db.Session(&Session{NewDB: db.clone == 1}))
	} else {
		tx := db.Begin(opts...)
		if tx.Error != nil {
			return tx.Error
		}

		defer func() {
			// Make sure to rollback when panic, Block error or Commit error
			if panicked || err != nil {
				tx.Rollback()
			}
		}()

		if err = fc(tx); err == nil {
			panicked = false
			return tx.Commit().Error
		}
	}

	panicked = false
	return
}
```



#### 接口定义

猜测此文件是对外定义的，外部数据库兼容只需要实现上述方法，即可直接适配。

他的接口定义都放在了一个文件夹里，熟悉Mysql相关内容的我们是比较清楚的。

[interface文件](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L2)

定义了

- [Dialector](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L11-L21)
  - 具体的数据库连接
- [Plugin](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L23-L27)
- [ParamsFilter](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L29-L31)
- [ConnPool](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L34-L39)
  - 具体连接（gorm对其抽象理解为，能执行DML与QML
- [SavePointerDialectorInterface](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L41-L45)
  - SavePoint
- [TxBeginner](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L47-L50) 、 [ConnPoolBeginner](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L52-L55)
  - 事务支持
- [TxCommiter](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L57-L61)
  - 提交与rollback
- [Tx](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L63-L68)
  - sql.Tx接口定义
- [Valuer](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L70-L73)
- [GetDBConnector](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L75-L78)
- [Rows](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L80-L88)
  - 可能是sql.Row接口定义？
- [ErrorTranslator](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/interfaces.go#L90-L92)

-----

### 一条基础查询语句的执行流程

我们基于此语句往下看（最好直接Debug）

```go
DB.Table("xxx").Where("fake_name = ?", "fake_name").First(&xxx)
```

#### [Table](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/chainable_api.go#L60-L86)

```go
// Table specify the table you would like to run db operations
//
//	// Get a user
//	db.Table("users").Take(&result)
func (db *DB) Table(name string, args ...interface{}) (tx *DB) {
	tx = db.getInstance()
	if strings.Contains(name, " ") || strings.Contains(name, "`") || len(args) > 0 {
		tx.Statement.TableExpr = &clause.Expr{SQL: name, Vars: args}
		if results := tableRegexp.FindStringSubmatch(name); len(results) == 3 {
			if results[1] != "" {
				tx.Statement.Table = results[1]
			} else {
				tx.Statement.Table = results[2]
			}
		}
	} else if tables := strings.Split(name, "."); len(tables) == 2 {
		tx.Statement.TableExpr = &clause.Expr{SQL: tx.Statement.Quote(name)}
		tx.Statement.Table = tables[1]
	} else if name != "" {
		tx.Statement.TableExpr = &clause.Expr{SQL: tx.Statement.Quote(name)}
		tx.Statement.Table = name
	} else {
		tx.Statement.TableExpr = nil
		tx.Statement.Table = ""
	}
	return
}
```

其做了一些简单的对比引用以及处理，实际上，最终我们的输入将会落在 `else if name != "" {}` 中

其调用了[Quote](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L162-L167)函数，其中调用[QuoteTo](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L81-L160)函数做分流（支持处理多个数据类型，我们当前是String），因此其调用`stmt.DB.Dialector.QuoteTo(writer, v)`，将"xxx"传入，调用到了mysql的此方法[QuetoTo](https://github.com/go-gorm/mysql/blob/c829f6e3d7f916190f9ab96fc75ffdd89188bd39/mysql.go#L290-L336)，其具体实现就是将我们的表名打上(\`)。

最终将其存入`tx.Statement.TableExpr`中。

#### [Where](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/chainable_api.go#L195-L213)

了解 Where 实现，能让我们更好的封装底层。

```go
func (db *DB) Where(query interface{}, args ...interface{}) (tx *DB) {
	tx = db.getInstance()
	if conds := tx.Statement.BuildCondition(query, args...); len(conds) > 0 {
		tx.Statement.AddClause(clause.Where{Exprs: conds})
	}
	return
}
```

getInstance设计就是为了创建一个单独的链接，

由于他是链式调用，下一次还可能调用Where或其他函数，为了方便使用，因此大部分函数内都包含getInstance操作，且使用clone来判断是否需要新建一个连接。

在Mysql中，其每个查询都是单独的一个连接。

其中

#### [BuildCondition](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L284-L466)

他这个方法处理了多种类型的输入，但我们常用的还是string，因此本次只看string分支。

strings 也是对其进行了详细拆分，我们同通常会走分支1（带`?`的）

也就是创建了一个 []caluse.Expr

```go
func (stmt *Statement) BuildCondition(query interface{}, args ...interface{}) []clause.Expression {
	if s, ok := query.(string); ok {
		// if it is a number, then treats it as primary key
		if _, err := strconv.Atoi(s); err != nil {
			if s == "" && len(args) == 0 {
				return nil
			}

			if len(args) == 0 || (len(args) > 0 && strings.Contains(s, "?")) {
				// looks like a where condition
				return []clause.Expression{clause.Expr{SQL: s, Vars: args}}
			}

			if len(args) > 0 && strings.Contains(s, "@") {
				// looks like a named query
				return []clause.Expression{clause.NamedExpr{SQL: s, Vars: args}}
			}

			if strings.Contains(strings.TrimSpace(s), " ") {
				// looks like a where condition
				return []clause.Expression{clause.Expr{SQL: s, Vars: args}}
			}

			if len(args) == 1 {
				return []clause.Expression{clause.Eq{Column: s, Value: args[0]}}
			}
		}
	}
    ...
}
```



#### [clause.Expression](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/expression.go#L10-L13)

在上述代码中，我们看到了clause.Expression作为BuildCondition的返回值，这是一个接口，其内定义了一个Build方法，用于建造具体语句

```go
// Expression expression interface
type Expression interface {
	Build(builder Builder)
}
```

![expression](gorm.assets\expression.png)

当前我们使用了其Expr作为实现。



Builder的定义可以暂时跳过，将在最终执行时使用。

回到[Where](####Where)函数，其调用了[tx.Statement.AddClause](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L264-L275)，并将结果保存，若是曾经已有值，则合并。

```go
func (stmt *Statement) AddClause(v clause.Interface) {
	if optimizer, ok := v.(StatementModifier); ok {
		optimizer.ModifyStatement(stmt)
	} else {
		name := v.Name()
		c := stmt.Clauses[name]
		c.Name = name
		v.MergeClause(&c)
		stmt.Clauses[name] = c
	}
}
```

当前的参数 `v caluse.Interface` 是[clause.Where](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/where.go#L12-L15)，其`.Name() = "WHERE"`，因此，此步更新了`stmt.Clauses["Where"]`变量。

>  [stmt.Clauses](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L30) 定义为 `map[string]clause.Clause`

同时，调用[clause.Where](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/where.go#L12-L15)的[MergeClause](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/where.go#L91-L101)函数

```go
// MergeClause merge where clauses
func (where Where) MergeClause(clause *Clause) {
	if w, ok := clause.Expression.(Where); ok {
		exprs := make([]Expression, len(w.Exprs)+len(where.Exprs))
		copy(exprs, w.Exprs)
		copy(exprs[len(w.Exprs):], where.Exprs)
		where.Exprs = exprs
	}

	clause.Expression = where
}
```

此处做了if判断，用于防止原先为空的情况（第一次执行）

此处的表达实现应该是为了防止浪费内存（但因为每次增加Where语句都会有内存分配，可能会影响内存性能）

此时，Where方法结束。我们简单回顾一下：

![gorm_where](gorm.assets\gorm_where.png)

-----

接下来我们来看是如何执行上述条件的。

#### [First](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/finisher_api.go#L117-L130)

[First](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/finisher_api.go#L117-L130)函数会去做具体的执行操作，并且其相对于[Find](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/finisher_api.go#L161-L171)而言，会对primary key 进行排序后，取第一个返回值。

```go
func (db *DB) First(dest interface{}, conds ...interface{}) (tx *DB) {
	tx = db.Limit(1).Order(clause.OrderByColumn{
		Column: clause.Column{Table: clause.CurrentTable, Name: clause.PrimaryKey},
	})
	if len(conds) > 0 {
		if exprs := tx.Statement.BuildCondition(conds[0], conds[1:]...); len(exprs) > 0 {
			tx.Statement.AddClause(clause.Where{Exprs: exprs})
		}
	}
	tx.Statement.RaiseErrorOnNotFound = true
	tx.Statement.Dest = dest
	return tx.callbacks.Query().Execute(tx)
}
```

可以看到，他调用了`db.Limit(1)`这个对外暴露的方法，并且添加了排序。

且其对`tx.Statement.Dest`做了赋值，后调用`tx.callbacks.Query().Execute(tx)`做执行。

我们从[callbacks](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks.go#L28-L31)开始看起，看他是个什么东西，并且看其是在哪里做了初始化。

```go
type callbacks struct {
	processors map[string]*processor
}
```

[processor](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks.go#L33-L38)定义

```go
type processor struct {
	db        *DB
	Clauses   []string
	fns       []func(*DB)
	callbacks []*callback
}
```

其[Query](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks.go#L55-L57)方法如下

```go
func (cs *callbacks) Query() *processor {
	return cs.processors["query"]
}
```

我们可以看到，其具体Query方法就是查询出map中的变量，并将其返回。因此，我们看其在哪里被赋值的，且其值为什么。

其初始化操作为 [initializeCallbacks](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks.go#L15-L26)

```go
func initializeCallbacks(db *DB) *callbacks {
	return &callbacks{
		processors: map[string]*processor{
			"create": {db: db},
			"query":  {db: db},
			"update": {db: db},
			"delete": {db: db},
			"row":    {db: db},
			"raw":    {db: db},
		},
	}
}
```

在gorm.Open中被调用[`db.callbacks = initializeCallbacks(db)`](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/gorm.go#L178)

其就是将gorm.DB直接传入，没有其他特殊处理。

接着往下看

#### [Execute](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks.go#L76-L154)

```go
func (p *processor) Execute(db *DB) *DB {
	// call scopes
	for len(db.Statement.scopes) > 0 {
		db = db.executeScopes()
	}

	var (
		curTime           = time.Now()
		stmt              = db.Statement
		resetBuildClauses bool
	)

	if len(stmt.BuildClauses) == 0 {
		stmt.BuildClauses = p.Clauses
		resetBuildClauses = true
	}

	if optimizer, ok := db.Statement.Dest.(StatementModifier); ok {
		optimizer.ModifyStatement(stmt)
	}

	// assign model values
	if stmt.Model == nil {
		stmt.Model = stmt.Dest
	} else if stmt.Dest == nil {
		stmt.Dest = stmt.Model
	}

	// parse model values
	if stmt.Model != nil {
		if err := stmt.Parse(stmt.Model); err != nil && (!errors.Is(err, schema.ErrUnsupportedDataType) || (stmt.Table == "" && stmt.TableExpr == nil && stmt.SQL.Len() == 0)) {
			if errors.Is(err, schema.ErrUnsupportedDataType) && stmt.Table == "" && stmt.TableExpr == nil {
				db.AddError(fmt.Errorf("%w: Table not set, please set it like: db.Model(&user) or db.Table(\"users\")", err))
			} else {
				db.AddError(err)
			}
		}
	}

	// assign stmt.ReflectValue
	if stmt.Dest != nil {
		stmt.ReflectValue = reflect.ValueOf(stmt.Dest)
		for stmt.ReflectValue.Kind() == reflect.Ptr {
			if stmt.ReflectValue.IsNil() && stmt.ReflectValue.CanAddr() {
				stmt.ReflectValue.Set(reflect.New(stmt.ReflectValue.Type().Elem()))
			}

			stmt.ReflectValue = stmt.ReflectValue.Elem()
		}
		if !stmt.ReflectValue.IsValid() {
			db.AddError(ErrInvalidValue)
		}
	}

	for _, f := range p.fns {
		f(db)
	}

	if stmt.SQL.Len() > 0 {
		db.Logger.Trace(stmt.Context, curTime, func() (string, int64) {
			sql, vars := stmt.SQL.String(), stmt.Vars
			if filter, ok := db.Logger.(ParamsFilter); ok {
				sql, vars = filter.ParamsFilter(stmt.Context, stmt.SQL.String(), stmt.Vars...)
			}
			return db.Dialector.Explain(sql, vars...), db.RowsAffected
		}, db.Error)
	}

	if !stmt.DB.DryRun {
		stmt.SQL.Reset()
		stmt.Vars = nil
	}

	if resetBuildClauses {
		stmt.BuildClauses = nil
	}

	return db
}
```

1. 其中，p.Clauses值为`SELECT` `FROM` `WHERE` `GROUP BY` `ORDER BY` `LIMIT` `FOR`
   - 其在[RegisterDefaultCallbacks](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks/callbacks.go#L22-L83)中初始化
2. stmt.Model 赋值为 stmt.Dest
3. p.fns内含三个函数
   - [Query](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks/query.go#L14-L30)
   - [Preload](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks/query.go#L266-L285)
   - [AfterQuery](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks/query.go#L287-L303)
4. 

-----

上述查询过程实际上已经完成，我们稍微详细扒一下

#### [callbacks.Query](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks/query.go#L14-L30)

其调用了`BuildQuerySQL(db)`，并执行对应的sql操作。最终调用Scan去扫描读取数据。

```go
func Query(db *gorm.DB) {
	if db.Error == nil {
		BuildQuerySQL(db)

		if !db.DryRun && db.Error == nil {
			rows, err := db.Statement.ConnPool.QueryContext(db.Statement.Context, db.Statement.SQL.String(), db.Statement.Vars...)
			if err != nil {
				db.AddError(err)
				return
			}
			defer func() {
				db.AddError(rows.Close())
			}()
			gorm.Scan(rows, db, 0)
		}
	}
}
```



#### [callbacks.BuildQuerySQL](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks/query.go#L32-L264)

（代码较长，省略）

stmt.ReflectValue在Execute中被赋值了，其值为dest（也就是`First(&xxx)`的xxx）。

1. 如果目标结构体与查询表相同，并且其主键存在值，则搜索时附带。
2. 处理Select+Omit+传入xxx的结构体存在字段项（选择查询字段）
3. 处理连表操作，若没有，则在Clauses中添加FROM key
4. 若没有Select，则在Clauses中添加SELECT key
5. 调用[Statement.Build](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L468-L486)构建SQL语句。



#### [Statement.Build](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L468-L486)

代码很短，看到这里我们就能明白，[processor.Clauses](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/callbacks.go#L36)里定义的值就是一条条的需要去从tx.Statement中取出的key，也就是我们`.Table(xxx)`与`.Where()`与`.Limit`、`.Order By` 的key。

下面代码基于此key，逐步拼接，汇聚成一条sql语句。

```go
// Build build sql with clauses names
func (stmt *Statement) Build(clauses ...string) {
	var firstClauseWritten bool

	for _, name := range clauses {
		if c, ok := stmt.Clauses[name]; ok {
			if firstClauseWritten {
				stmt.WriteByte(' ')
			}

			firstClauseWritten = true
			if b, ok := stmt.DB.ClauseBuilders[name]; ok {
				b(c, stmt)
			} else {
				c.Build(stmt)
			}
		}
	}
}
```

在gorm中，其对一条SQL语句的定义进行了拆分，拆分成多个Clause，如：

- SELECT
- FROM
- WHERE
- ORDER BY 
- GROUP BY
- LIMIT 
- FOR...

每个[Clause](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/clause.go#L3-L8)都实现了`Name()` `Build(Builder)` `MergeClause(*Clause)` 方法

且每个查询都是一个[Statement](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L21-L50)，SQL是由多个[Clauses](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L30)所组成。



#### [Where.Build && Where.BuildExprs](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/where.go#L22-L89)

此处处理Where下的全部Expression，将其拼接（因支持OR，所以此处需要处理括号）



#### [clause.Expr](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/expression.go#L20-L76)

此实现是sql与参数切分，参数占位符由后续的[AddVar](####Statement.AddVar)实现

```go
func (expr Expr) Build(builder Builder) {
	var (
		afterParenthesis bool
		idx              int
	)

	for _, v := range []byte(expr.SQL) {
		if v == '?' && len(expr.Vars) > idx {
			if afterParenthesis || expr.WithoutParentheses {
				if _, ok := expr.Vars[idx].(driver.Valuer); ok {
					builder.AddVar(builder, expr.Vars[idx])
				} else {
					switch rv := reflect.ValueOf(expr.Vars[idx]); rv.Kind() {
					case reflect.Slice, reflect.Array:
						if rv.Len() == 0 {
							builder.AddVar(builder, nil)
						} else {
							for i := 0; i < rv.Len(); i++ {
								if i > 0 {
									builder.WriteByte(',')
								}
								builder.AddVar(builder, rv.Index(i).Interface())
							}
						}
					default:
						builder.AddVar(builder, expr.Vars[idx])
					}
				}
			} else {
				builder.AddVar(builder, expr.Vars[idx])
			}

			idx++
		} else {
			if v == '(' {
				afterParenthesis = true
			} else {
				afterParenthesis = false
			}
			builder.WriteByte(v)
		}
	}

	if idx < len(expr.Vars) {
		for _, v := range expr.Vars[idx:] {
			builder.AddVar(builder, sql.NamedArg{Value: v})
		}
	}
}
```

#### [Statement.AddVar](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/statement.go#L169-L262)

处理占位符

1. 处理多种传入类型，参数为"不定长参数"，循环开头，若是idx>0，则注入`,`。
   - 若是传入的为数组，则在开头加个`(`，并将数组值拆分后再次调用当前函数，在结束后再加个`)`



#### [clause.Builder](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/clause/clause.go#L18-L24)

```go
// Builder builder interface
type Builder interface {
	Writer
	WriteQuoted(field interface{})
	AddVar(Writer, ...interface{})
	AddError(error) error
}
```



最终，我们得到以下图，其查询流程如下：

![gorm_statement](gorm.assets\gorm_statement.png)





#### [gorm.Scan](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/scan.go#L124-L360)

扫表操作

操作其实非常简单，如果是slice类型，且cap为0，它将初始化20容量的切片[reflect.MakeSlice](https://github.com/go-gorm/gorm/blob/4a50b36f638c6899089e6e3457425528ce693933/scan.go#L293)

后续直接Append，没有做多于操作。

