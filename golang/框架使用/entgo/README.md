当前为ent的学习笔记。


什么是ent？ent是什么？

是啥我也不知道，刚开坑，什么东西都不懂。根据了解，这是一款orm(数据库映射)库。

咦，那岂不是跟gorm一样吗？但看概念，好像更加复杂一点。这上面像是个图概念，有点，有边的概念。

为什么我会学习entgo？ 因为我看某tg群里，很多人吹这技术，说用entgo+gqlgen写业务代码，爽的不要不要的。

下面开始仔细研究是什么。

官网 [entgo.io](https://entgo.io/)
文档 [docs](https://entgo.io/docs/getting-started)

本教程以MySQL为基础（其他的我也不会

文档本身很全，跟着一步步走下来四个小时差不多能学明白（假的，学不明白了。已经超过四个小时了，发现竟然还有grpc生成拓展，而且还要拓展图概念😢

## 自己的文档

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

### 初始化数据结构

#### 初始化操作
初始化一个User结构体，对应数据库users

```go
go run -mod=mod entgo.io/ent/cmd/ent init User
```
该结构体长这样
```go
package schema  
  
import "entgo.io/ent"  
  
// User holds the schema definition for the User entity.  
type User struct {  
	ent.Schema  
}  
  
// Fields of the User.  
func (User) Fields() []ent.Field {  
	return nil  
}  
  
// Edges of the User.  
func (User) Edges() []ent.Edge {  
	return nil  
}
```
当前文件用于给ent解析生成相应的go crud代码，并不是我们进行使用。


#### 字段和边
其中，Field 就是数据库中的字段，最后将会生成对应文件。

Edge 为边。在MySQL中类似外键概念，可以理解为，我们可以通过这一条边，找到其他表的数据。

比如我们现在有两张表
- 一个User表，其中有年龄、姓名字段
- 一个Car表，其中有型号，注册时间
- 其关系为一对多，一个User对多个Car。
- 建立此关系后，我们可以通过User查找到Car，也可以通过Car反查找到User。

```go
package schema  
  
import "entgo.io/ent"  
  
// User holds the schema definition for the User entity.  
type User struct {  
	ent.Schema  
}  
  
// Fields of the User.  
func (User) Fields() []ent.Field {  
	return []ent.Field{  
		field.Int("age").  
			Positive(),  
		field.String("name").  
			Default("unknown"),  
	}  
}
  
// Edges of the User.  
func (User) Edges() []ent.Edge {  
	return []ent.Edge{  
		edge.To("cars", Car.Type),  
	}
}
```

```go
package schema  
  
import "entgo.io/ent"  
  
// User holds the schema definition for the User entity.  
type Car struct {  
	ent.Schema  
}  
  
// Fields of the User.  
func (Car) Fields() []ent.Field {  
	return []ent.Field{  
		field.String("model"),  
		field.Time("registered_at"),  
	}  
}
  
// Edges of the User.  
func (Car) Edges() []ent.Edge {  
	return []ent.Edge{  
		// Create an inverse-edge called "owner" of type `User`  
		// and reference it to the "cars" edge (in User schema)  
		// explicitly using the `Ref` method.  
		edge.From("owner", User.Type).  
			Ref("cars").  
		// setting the edge to unique, ensure  
		// that a car can have only one owner.  
			Unique(),  
	}
}
```

完成上面配置后，我们调用 `go generate ./ent` 将可以生成相应的CRUD方法

#### Index

可以在一个或多个字段上配置索引，以提高数据检索速度或定义唯一性。
```go
package schema  
  
import (  
	"entgo.io/ent"  
	"entgo.io/ent/schema/index"  
)  
  
// User holds the schema definition for the User entity.  
type User struct {  
	ent.Schema  
}  
  
func (User) Indexes() []ent.Index {  
	return []ent.Index{  
	// non-unique index.  
		index.Fields("field1", "field2"),  
		// unique index.  
		index.Fields("first_name", "last_name").  
			Unique(),  
	}  
}
```

#### Mixin

混合，说白了就是可以创建几个基础字段，让其他字段引用，类似（create_at, update_at, delete_at）
```go
package schema  
  
import (  
	"time"  
	  
	"entgo.io/ent"  
	"entgo.io/ent/schema/field"  
	"entgo.io/ent/schema/mixin"  
)  
  
// -------------------------------------------------  
// Mixin definition  
  
// TimeMixin implements the ent.Mixin for sharing  
// time fields with package schemas.  
type TimeMixin struct{  
// We embed the `mixin.Schema` to avoid  
// implementing the rest of the methods.  
	mixin.Schema  
}  
  
func (TimeMixin) Fields() []ent.Field {  
	return []ent.Field{  
		field.Time("created_at").  
			Immutable().  
			Default(time.Now),  
		field.Time("updated_at").  
			Default(time.Now).  
			UpdateDefault(time.Now),  
	}  
}

type User struct {  
	ent.Schema  
}  
  
func (User) Mixin() []ent.Mixin {  
	return []ent.Mixin{  
		TimeMixin{},  
	}  
}  
  
func (User) Fields() []ent.Field {  
	return []ent.Field{  
		field.String("nickname").  
			Unique(),  
	}  
}
```

#### Annotations

注释，也可以说是标记。
附带了一个很好玩的功能，可以级联删除（删除当前表时同时删除外键）
```go
package schema  
  
import (  
	"entgo.io/ent"  
	"entgo.io/ent/dialect/entsql"  
	"entgo.io/ent/schema/edge"  
	"entgo.io/ent/schema/field"  
)  
  
// User holds the schema definition for the User entity.  
type User struct {  
	ent.Schema  
}  
  
// Fields of the User.  
func (User) Fields() []ent.Field {  
	return []ent.Field{  
		field.String("name").  
			Default("Unknown"),  
	}  
}  
  
// Edges of the User.  
func (User) Edges() []ent.Edge {  
	return []ent.Edge{  
		edge.To("posts", Post.Type).  
			Annotations(entsql.Annotation{  
				OnDelete: entsql.Cascade,  
			}),  
	}  
}
```

----- 

### 创建数据库链接

创建数据库链接也是非常简单的
```go
package main  
  
import (  
	"context"  
	"log"  
	  
	"entdemo/ent"  
	  
	_ "github.com/go-sql-driver/mysql"  
)  
  
func main() {  
	client, err := ent.Open("mysql", "<user>:<pass>@tcp(<host>:<port>)/<database>?parseTime=True")  
	if err != nil {  
		log.Fatalf("failed opening connection to mysql: %v", err)  
	}  
	defer client.Close()  
	// Run the auto migration tool.  
	if err := client.Schema.Create(context.Background()); err != nil {  
		log.Fatalf("failed creating schema resources: %v", err)  
	}  
}
```


### 调用操作

这里就是ent的亮点，大量的业务代码直接由其框架直接生成，我们可以获得到拆箱及用的爽感。

#### 创建
`Save` 与 `SaveX` 的差距是，一个返回Err，一个直接Panic
```go
a8m, err := client.User. // UserClient.  
	Create(). // User create builder.  
	SetName("a8m"). // Set field value.  
	SetNillableAge(age). // Avoid nil checks.  
	AddGroups(g1, g2). // Add many edges.  
	SetSpouse(nati). // Set unique edge.  
	Save(ctx) // Create and return.
```
批创造
```go
names := []string{"pedro", "xabi", "layla"}  
bulk := make([]*ent.PetCreate, len(names))  
for i, name := range names {  
	bulk[i] = client.Pet.Create().SetName(name).SetOwner(a8m)  
}  
pets, err := client.Pet.CreateBulk(bulk...).Save(ctx)
```


#### 更新

```go
a8m, err = a8m.Update(). // User update builder.  
	RemoveGroup(g2). // Remove a specific edge.  
	ClearCard(). // Clear a unique edge.  
	SetAge(30). // Set a field value.  
	AddRank(10). // Increment a field value.  
	AppendInts([]int{1}). // Append values to a JSON array.  
	Save(ctx)
```

通过id 更新
```go
pedro, err := client.Pet. // PetClient.  
	UpdateOneID(id). // Pet update builder.  
	SetName("pedro"). // Set field name.  
	SetOwnerID(owner). // Set unique edge, using id.  
	Save(ctx)
```

使用WHERE过滤
```go
n, err := client.User. // UserClient.  
	Update(). // Pet update builder.  
	Where( //  
		user.Or( // (age >= 30 OR name = "bar")  
			user.AgeGT(30), //  
			user.Name("bar"), // AND  
		), //  
		user.HasFollowers(), // UserHasFollowers()  
	). //  
	SetName("foo"). // Set field name.  
	Save(ctx)
```

使用边条件更新
```go
n, err := client.User. // UserClient.  
	Update(). // Pet update builder.  
	Where( //  
		user.HasFriendsWith( // UserHasFriendsWith (  
			user.Or( // age = 20  
				user.Age(20), // OR  
				user.Age(30), // age = 30  
			) // )  
		), //  
	). //  
	SetName("a8m"). // Set field name.  
	Save(ctx)
```


#### 更新或插入

Upsert
```go
err := client.User.  
	Create().  
	SetAge(30).  
	SetName("Ariel").  
	OnConflict().  
	// Use the new values that were set on create.  
	UpdateNewValues().  
	Exec(ctx)  
  
id, err := client.User.  
	Create().  
	SetAge(30).  
	SetName("Ariel").  
	OnConflict().  
	// Use the "age" that was set on create.  
	UpdateAge().  
	// Set a different "name" in case of conflict.  
	SetName("Mashraki").  
	ID(ctx)  
  
// Customize the UPDATE clause.  
err := client.User.  
	Create().  
	SetAge(30).  
	SetName("Ariel").  
	OnConflict().  
	UpdateNewValues().  
	// Override some of the fields with a custom update.  
	Update(func(u *ent.UserUpsert) {  
		u.SetAddress("localhost")  
		u.AddCount(1)  
		u.ClearPhone()  
	}).  
	Exec(ctx)
```

更新多个值
```go
err := client.User. // UserClient  
	CreateBulk(builders...). // User bulk create.  
	OnConflict(). // User bulk upsert.  
	UpdateNewValues(). // Use the values that were set on create in case of conflict.  
	Exec(ctx) // Execute the statement.
```


#### 查找
查询
```go
users, err := client.User. // UserClient.  
	Query(). // User query builder.  
	Where(user.HasFollowers()). // filter only users with followers.  
	All(ctx) // query and return.
```

通过边（关系）进行查询
```go
users, err := a8m.  
	QueryFollowers().  
	All(ctx)
```

查找边的边
```go
users, err := a8m.  
	QueryFollowers().  
	QueryPets().  
	All(ctx)
```

Where
```go
n, err := client.Post.  
	Query().  
	Where(  
		post.Not(  
			post.HasComments(),  
		)  
	).  
	Count(ctx)
```

扫描所有宠物到自定义结构体中
```go
var v []struct {  
	Age int `json:"age"`  
	Name string `json:"name"`  
}  
err := client.Pet.  
	Query().  
	Select(pet.FieldAge, pet.FieldName).  
	Scan(ctx, &v)  
	
if err != nil {  
	log.Fatal(err)  
}
```

#### 删除
```go
err := client.User.  
	DeleteOne(a8m).  
	Exec(ctx)
```

删除多个
```go
_, err := client.File.  
	Delete().  
	Where(file.UpdatedAtLT(date)).  
	Exec(ctx)
```

#### 突变 Mutation

还没看懂是干啥的，但感觉是一个，因不满足于ent提供的CRUD方法而额外自定义拓展的方法。

可以说是一种抽象设计，类似代理模式，你将东西传过来，我帮你调用。


-----
## 缺点

到现在为止，我也发现了部分的缺点 

entgo 在表Join的同时，返回两张表数据（虽然其他的orm也没有此功能）

entgo 不能指定查询表名
- 这就导致了如果你按时间分库分表，在ent上是十分不友好的
- https://github.com/ent/ent/issues/1990
- https://github.com/ent/ent/pull/2020

 有一个解决方式：
```go
only, err := client.Dua.Query().  
   Where(func(s *sql.Selector) {  
	  tab := sql.Table("d_" + strconv.Itoa(i))  
	  s.From(tab)  
   }).Only(ctx)
```

需要注意，初始化命名可能会与结构体产生冲突
- create 将默认使用大写字母+c
- query 将默认使用大写字母+q
- delete 将默认使用大写字母+d
- update 将默认使用大写字母+u




## 深扒源码
