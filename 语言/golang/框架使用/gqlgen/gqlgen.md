#gqlgen
[文档](https://gqlgen.com)

当前为 gqlgen 的学习笔记

什么是 gqlgen？ gqlgen是什么？

就跟ent一样，我什么都不知道，可以说是刚开坑。但根据别人的描述，据说这是一个图查询的服务框架。
官网给出的解释↓
```markdown
## What is gqlgen?[](https://gqlgen.com/#what-is-gqlgen)

[gqlgen](https://github.com/99designs/gqlgen) is a Go library for building GraphQL servers without any fuss.

-   **gqlgen is based on a Schema first approach** — You get to Define your API using the GraphQL [Schema Definition Language](http://graphql.org/learn/schema/).
-   **gqlgen prioritizes Type safety** — You should never see `map[string]interface{}` here.
-   **gqlgen enables Codegen** — We generate the boring bits, so you can focus on building your app quickly.

Still not convinced enough to use **gqlgen**? Compare **gqlgen** with other Go graphql [implementations](https://gqlgen.com/feature-comparison/)
```

#graphql

简单说一下，GraphQL 就是一个查询语句的模式，可以理解为SQL语句，只不过其连带关系更加明确，可读性更强。
[GraphQL概念](https://graphql.org/learn/schema/)
[[GraphQL]]


接下来开始我们的框架学习

gqlgen 只是GraphQL的其中一种实现，其主要是通过配置文件，生成相应方法。我个人认为这也是未来的主流。比如entgo、go-zero这些框架都运用了生成器，甚至gorm也开始使用生成器了。
代码生成器可以有效的帮我们降低、规范代码，这在企业的标准化开发中是属于一种非常优秀的设计。只要清晰了解每个包是用来干什么的，就可以快速掌握其内容。

## 快速开始

### 初始化一个项目
初始化项目
```
mkdir gqlgen-todos
cd gqlgen-todos
go mod init github.com/[username]/gqlgen-todos
```
创建 `tools.go` 文件
```
//go:build tools
// +build tools package tools 

import (
	_ "github.com/99designs/gqlgen" 
)
```
自动添加依赖
```shell
go mod tidy
```

### 创建一个服务
运行
```
go run github.com/99designs/gqlgen init
```

将会创建一堆目录，我们来看看都是些什么
```
├── go.mod 
├── go.sum 
├── gqlgen.yml - The gqlgen config file, knobs for controlling the generated code. 
├── graph 
│   ├── generated - A package that only contains the generated runtime 
│   │   └── generated.go 
│   ├── model - A package for all your graph models, generated or otherwise 
│   │   └── models_gen.go 
│   ├── resolver.go - The root graph resolver type. This file wont get regenerated 
│   ├── schema.graphqls - Some schema. You can split the schema into as many graphql files as you like 
│   └── schema.resolvers.go - the resolver implementation for schema.graphql 
└── server.go - The entry point to your app. Customize it however you see fit
```
根据其描述
- `/gqlgen.yml` 是gqlgen的配置文件，控制生成的代码
- `/graph/generated` 目录是生成器
- `/graph/model`  在`gqlgen.yml`中定义的类型将会生成在此包下
- `/graph/resolver.go` 图的根解析器类型，这个文件不会被重新生成
- `/graph/schema.grahpqls` GraphQL的标注图文件
- `/graph/schema.resolvers.go` 解析器实现schema GraphQL
- `/server.go` 程序的入口，可自由定制

### 定义schema
gqlgen 是一个schema-first的库 - 在你写代码之前，你需要使用GraphQL定义你的API。默认时，你需要写入到`/graph/schema.graphqls`下。（当然，你可以拆分到多个不同文件）

schema默认将写入下面这些内容
```GraphQL
type Todo {  
  id: ID!  
  text: String!  
  done: Boolean!  
  user: User!  
}  
  
type User {  
  id: ID!  
  name: String!  
}  
  
type Query {  
  todos: [Todo!]!  
}  
  
input NewTodo {  
  text: String!  
  userId: String!  
}  
  
type Mutation {  
  createTodo(input: NewTodo!): Todo!  
}
```

### 实现resolver（解析器）
当执行gqlgen的`generate`命令时，将会比对`/graph/schema.graphqls`与`/graph/model/*`。如果可以，他将会直接绑定到model中（如果不同，将会直接生成到model中）。这在`init`时已经完成。我们将会在后面的教程中修改`schema`文件，我们先看已经生成的
如果我们查看`graph/schema.resolvers.go` 我们将会看到：
```go
// CreateTodo is the resolver for the createTodo field.  
func (r *mutationResolver) CreateTodo(ctx context.Context, input model.NewTodo) (*model.Todo, error) {  
   panic(fmt.Errorf("not implemented: CreateTodo - createTodo"))  
}  
  
// Todos is the resolver for the todos field.  
func (r *queryResolver) Todos(ctx context.Context) ([]*model.Todo, error) {  
   panic(fmt.Errorf("not implemented: Todos - todos"))  
}
```
现在这两个方法都没有实现，我们只需要将其实现，即可让我们的服务正常工作

首先我们需要跟踪我们的状态，让我们将其放在`/graph/resolver.go`中
`/graph/resolver.go`文件是我们声明的app依赖，就像我们的数据库，当我们创建图时，它将在`/server.go`中初始化一次。
```go
type Resolver struct{
	todos []*model.Todo // 假设你是数据库
}
```
返回`/graph/schema.resolvers.go`，让我们给`CreateTodo`实现一个方法（假装其是数据库的创建操作）。同时也给`Todos`实现一下（作为查询，直接返回创建的值）。
```go
// CreateTodo is the resolver for the createTodo field.  
func (r *mutationResolver) CreateTodo(ctx context.Context, input model.NewTodo) (*model.Todo, error) {  
   todo := &model.Todo{  
      Text: input.Text,  
      ID:   fmt.Sprintf("T%d", rand.Int()),  
      User: &model.User{ID: input.UserID, Name: "user " + input.UserID},  
   }  
   r.todos = append(r.todos, todo)  
   return todo, nil  
}

// Todos is the resolver for the todos field.  
func (r *queryResolver) Todos(ctx context.Context) ([]*model.Todo, error) {  
   return r.todos, nil  
   //panic(fmt.Errorf("not implemented: Todos - todos"))  
}
```
完成上面的实现后，我们就可以开启服务器并进行简单的实验了。
运行服务
```go
go run server.go
```
浏览器打开 http://localhost:8080
输入以下命令，用于创建用户
```GraphQL
mutation createTodo {
  createTodo(input: { text: "todo", userId: "1" }) {
    user {
      id
    }
    text
    done
  }
}
```
通过以下命令，查询
```go
query findTodos {
  todos {
    text
    done
    user {
      name
    }
  }
}
```


### 不用急于获取用户（获取少量用户）
这个例子很棒，但是真实世界中，获取大量对象是非常昂贵的。我们通常不想加载User用户，除非用户真的需要他。所以我们需要重新生成一下`Todo`方法，让其更小，更贴近于现实。

首先，启动`autobind`。其作用是允许gqlgen使用定制models，让gqlgen可以找到他们而不是生成他们。我们可以通过取消`/gqlgen.yml`文件中`autobind`的注释来启用他。
```go
autobind:
 - "github.com/[username]/gqlgen-todos/graph/model"
```
在`/gqlgen.yml`中添加 `Todo` 字段解析去生成`user`字段的解析器
```yml
# This section declares type mapping between the GraphQL and go type systems  
#  
# The first line in each type will be used as defaults for resolver arguments and  
# modelgen, the others will be allowed when binding to fields. Configure them to  
# your liking  
models:  
  ID:  
    model:  
      - github.com/99designs/gqlgen/graphql.ID  
      - github.com/99designs/gqlgen/graphql.Int  
      - github.com/99designs/gqlgen/graphql.Int64  
      - github.com/99designs/gqlgen/graphql.Int32  
  Int:  
    model:  
      - github.com/99designs/gqlgen/graphql.Int  
      - github.com/99designs/gqlgen/graphql.Int64  
      - github.com/99designs/gqlgen/graphql.Int32  
  Todo:  
    fields:  
      user:  
        resolver: true
```

```go
package model  
  
type Todo struct {  
   ID     string `json:"id"`  
   Text   string `json:"text"`  
   Done   bool   `json:"done"`  
   UserID string `json:"userId"`  
   User   *User  `json:"user"`  
}
```
同时运行`go run github.com/99designs/gqlgen generate`

现在，当我们查看`/graph/schema.resolvers.go`时，我们能看见一个新的解析器，让我们实现它，并且修复`CreateTodo`

```go
func (r *mutationResolver) CreateTodo(ctx context.Context, input model.NewTodo) (*model.Todo, error) {  
   todo := &model.Todo{  
      Text:   input.Text,  
      ID:     fmt.Sprintf("T%d", rand.Int()),  
      User:   &model.User{ID: input.UserID, Name: "user " + input.UserID},  
      UserID: input.UserID,  
   }  
   r.todos = append(r.todos, todo)  
   return todo, nil  
   //panic(fmt.Errorf("not implemented: CreateTodo - createTodo"))  
}

// User is the resolver for the user field.  
func (r *todoResolver) User(ctx context.Context, obj *model.Todo) (*model.User, error) {  
   return &model.User{ID: obj.UserID, Name: "user " + obj.UserID}, nil  
   //panic(fmt.Errorf("not implemented: User - user"))  
}
```
在我们的 `resolvers.go`文件中，在`package`和`import`中间加入
```go
//go:generate go run github.com/99designs/gqlgen generate
```



## 参考

当前参考有许多的案例用于学习，简单高效。

### APQ 
APQ = Automatic Persisted Queries 自动持久查询？
默认情况下，当你使用GraphQL作为查询时，你的查询会随每个请求一起传输。那样会浪费带宽。为了避免上述情况，你可以使用APQ

APQ就是你只发送查询的hash值（将查询语句hash计算）到服务器。如果hash值没有在服务器中查找到，则客户端发起第二次请求（将完整查询发送）去注册一个查询hash

服务器端需要实现`graphql.Cache`接口，并且传实例给`extension.AutomaticPersistedQuery`类型。确保扩展应用到你的GraphQL处理中。

```go
  
import (  
	"context"  
	"time"  
	  
	"github.com/99designs/gqlgen/graphql/handler"  
	"github.com/99designs/gqlgen/graphql/handler/extension"  
	"github.com/99designs/gqlgen/graphql/handler/transport"  
	"github.com/go-redis/redis"  
)  
  
type Cache struct {  
   client redis.UniversalClient  
   ttl    time.Duration  
}  
  
const apqPrefix = "apq:"  
  
func NewCache(redisAddress string, ttl time.Duration) (*Cache, error) {  
   client := redis.NewClient(&redis.Options{  
      Addr:     redisAddress,  
   })  
  
   err := client.Ping().Err()  
   if err != nil {  
      return nil, fmt.Errorf("could not create cache: %w", err)  
   }  
  
   return &Cache{client: client, ttl: ttl}, nil  
}  
  
func (c *Cache) Add(ctx context.Context, key string, value interface{}) {  
   c.client.Set(apqPrefix+key, value, c.ttl)  
}  
  
func (c *Cache) Get(ctx context.Context, key string) (interface{}, bool) {  
   s, err := c.client.Get(apqPrefix + key).Result()  
   if err != nil {  
      return struct{}{}, false  
   }  
   return s, true  
}  
  
func main() {  
   cache, err := NewCache(cfg.RedisAddress, 24*time.Hour)  
   if err != nil {  
      log.Fatalf("cannot create APQ redis cache: %v", err)  
   }  
  
   c := Config{ Resolvers: &resolvers{} }  
   gqlHandler := handler.New(  
      generated.NewExecutableSchema(c),  
   )  
   gqlHandler.AddTransport(transport.POST{})  
   gqlHandler.Use(extension.AutomaticPersistedQuery{Cache: cache})  
   http.Handle("/query", gqlHandler)  
}
```

-----

### 变更集 Changesets

在某些时候你需要区分是`nil`还是存在，在gqlgen中，我们可以使用`map`来实现
```GrapQL
type Mutation{
	updateUser (id: ID!, changes: UserChanges!): User
}

type UserChanges {
	name: String
	email: String
}
```
同时，设置config如下
```yaml
models:
	UserChanges:
		model: "map[string]interface{}"
```
然后运行generate，你将会看到解析器类似下面这样
```go
func (r *mutationResolver) UpdateUser(ctx context.Context, id int, changes map[string]interface{}) (*User, error) {  
   u := fetchFromDb(id)  
   /// apply the changes  
   saveToDb(u)  
   return u, nil  
}
```
我们经常使用 mapstructure 库通过反射直接将这些变更集直接应用到对象：
```go
func ApplyChanges(changes map[string]interface{}, to interface{}) error {  
   dec, err := mapstructure.NewDecoder(&mapstructure.DecoderConfig{  
      ErrorUnused: true,  
      TagName:     "json",  
      Result:      to,  
      ZeroFields:  true,  
      // This is needed to get mapstructure to call the gqlgen unmarshaler func for custom scalars (eg Date)  
      DecodeHook: func(a reflect.Type, b reflect.Type, v interface{}) (interface{}, error) {  
         if reflect.PtrTo(b).Implements(reflect.TypeOf((*graphql.Unmarshaler)(nil)).Elem()) {  
            resultType := reflect.New(b)  
            result := resultType.MethodByName("UnmarshalGQL").Call([]reflect.Value{reflect.ValueOf(v)})  
            err, _ := result[0].Interface().(error)  
            return resultType.Elem().Interface(), err  
         }  
  
         return v, nil  
      },  
   })  
  
   if err != nil {  
      return err  
   }  
  
   return dec.Decode(changes)  
}
```
-----
### 数据加载 Dataloaders
在我眼里，看起来就像是一个kv的缓存结构
通过`Dataloaders`优化N+1 数据库查询

Dataloaders 将信息检索整合到更少的批处理调用中。下面这个案例演示了dataloaders通过整合多个SQL查询到一个单独的大查询中。

**问题描述**
假设你有一个图，有一个todos列表的查询
```GraphQL
query { todos { user { name } } }
```
并且`todo.user`解析器从数据库读取了`User`
```go
func (r *todoResolver) User(ctx context.Context, obj *model.Todo) (*model.User, error) {  
   res := db.LogAndQuery(  
      r.Conn,  
      "SELECT id, name FROM users WHERE id = ?",  
      obj.UserID,  
   )  
   defer res.Close()  
  
   if !res.Next() {  
      return nil, nil  
   }  
   var user model.User  
   if err := res.Scan(&user.ID, &user.Name); err != nil {  
      panic(err)  
   }  
   return &user, nil  
}
```
这个查询的执行将会调用`Query.Todos` 解析器将会调用`SELECT * FROM todo` 并且返回 N个todos。如果嵌套的`User`被选择，上面`UserRaw`解析器将会切分查询到每一个user中，结果将会查询N+1个数据查询
e.g.
```MySQL
SELECT id, todo, user_id FROM todo  
SELECT id, name FROM users WHERE id = ?  
SELECT id, name FROM users WHERE id = ?  
SELECT id, name FROM users WHERE id = ?  
SELECT id, name FROM users WHERE id = ?  
SELECT id, name FROM users WHERE id = ?  
SELECT id, name FROM users WHERE id = ?
```
有什么问题吗？
大多数todos是属于一个用户的，我们可以做的比这个更好。

**Dataloader**
Dataloader 允许我们将给定的GraphQL请求的所有解析器中的`todo.user`获取请求整合到单个数据库查询中，甚至缓存后续的请求结果

我们将使用`graph-gophers/dataloader` 来实现大量获取users。
```go
go get -u github.com/graph-gophers/dataloader
```
接下来，我们实现一个数据加载中间件，用于拦截数据加载请求的context
```go
package storage  
  
// import graph gophers with your other imports  
import (  
"github.com/graph-gophers/dataloader"  
)  
  
type ctxKey string  
  
const (  
   loadersKey = ctxKey("dataloaders")  
)  
  
// UserReader reads Users from a database  
type UserReader struct {  
   conn *sql.DB  
}  
  
// GetUsers implements a batch function that can retrieve many users by ID,  
// for use in a dataloader  
func (u *UserReader) GetUsers(ctx context.Context, keys dataloader.Keys) []*dataloader.Result {  
   // read all requested users in a single query  
   userIDs := make([]string, len(keys))  
   for ix, key := range keys {  
      userIDs[ix] = key.String()  
   }  
   res := u.db.Exec(  
      r.Conn,  
      "SELECT id, name  
   FROM users  
   WHERE id IN (?" + strings.Repeat(",?", len(userIDs-1)) + ")",  
   userIDs...,  
)  
   defer res.Close()  
   // return User records into a map by ID  
   userById := map[string]*model.User{}  
   for res.Next() {  
      user := model.User{}  
      if err := res.Scan(&user.ID, &user.Name); err != nil {  
         panic(err)  
      }  
      userById[user.ID] = &user  
   }  
   // return users in the same order requested  
   output := make([]*dataloader.Result, len(keys))  
   for index, userKey := range keys {  
      user, ok := userById[userKey.String()]  
      if ok {  
         output[index] = &dataloader.Result{Data: record, Error: nil}  
      } else {  
         err := fmt.Errorf("user not found %s", userKey.String())  
         output[index] = &dataloader.Result{Data: nil, Error: err}  
      }  
   }  
   return output  
}  
  
// Loaders wrap your data loaders to inject via middleware  
type Loaders struct {  
   UserLoader *dataloader.Loader  
}  
  
// NewLoaders instantiates data loaders for the middleware  
func NewLoaders(conn *sql.DB) *Loaders {  
   // define the data loader  
   userReader := &UserReader{conn: conn}  
   loaders := &Loaders{  
      UserLoader: dataloader.NewBatchedLoader(userReader.GetUsers),  
   }  
   return loaders  
}  
  
// Middleware injects data loaders into the context  
func Middleware(loaders *Loaders, next http.Handler) http.Handler {  
   // return a middleware that injects the loader to the request context  
   return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {  
      nextCtx := context.WithValue(r.Context(), loadersKey, loaders)  
      r = r.WithContext(nextCtx)  
      next.ServeHTTP(w, r)  
   })  
}  
  
// For returns the dataloader for a given context  
func For(ctx context.Context) *Loaders {  
   return ctx.Value(loadersKey).(*Loaders)  
}  
  
// GetUser wraps the User dataloader for efficient retrieval by user ID  
func GetUser(ctx context.Context, userID string) (*model.User, error) {  
   loaders := For(ctx)  
   thunk := loaders.UserLoader.Load(ctx, dataloader.StringKey(userID))  
   result, err := thunk()  
   if err != nil {  
      return nil, err  
   }  
   return result.(*model.User), nil  
}
```
让我们来更新解析器调用dataloader
```go
func (r *todoResolver) User(ctx context.Context, obj *model.Todo) (*model.User, error) {  
   return storage.GetUser(ctx, obj.UserID)  
}
```
结果返回，只有两条查询
```MySQL
SELECT id, todo, user_id FROM todo
SELECT id, name from user WHERE id IN (?,?,?,?,?)
```
-----

### 字段收集 Field Collection 
决定什么字段在查询时需要

没咋看懂，感觉是一个请求时需确定其所需返回字段的一个东西。

这个通常在我们知道我们需要查询哪几个字段时有效。有这些信息可以允许解析器从数据源只获取必要字段，而不是过度获取所有内容并让gqlgen完成其余工作。

此过程称为字段手机 -- gql自动执行此操作，以便知道哪些字段应该是影响负载的一部分，但是，收集的字段集确实取决于要解析的类型。查询可以包含片段，解析器可以返回interface和unions，因此在知道解析对象的类型之前，无法完全确定收集的字段集.

在解析器中，有多种 API 方法可用于查询所选字段。

####  CollectAllFields
CollecteAllFields 时获取查询字段集的最简单方法。它将从查询中返回一段字符名称的字符串切片。这将是一组唯一的字段，并将返回所有片段，忽略片段类型条件

```GraphQL
query {
	foo {
		fieldA
		... on Bar {
			fieldB
		}
		... on Baz {
			fieldC
		}
	}
}
```

从解析器调用`CollectAllFields`将会产生`fieldA`，`fieldB`，`fieldC`的字符串切片集合


#### CollectFieldsCtx
`CollectFieldsCtx` 在需要有关匹配的更多信息，或收集的字段集应匹配已解析类型 的 片段类型条件的情况下很有用。`CollectFieldsCtx`接受一个`satisfies`参数，它应该是解析 类型将满足的字符串类型切片
例子
```GraphQL
interface Shape{
	area: Float
}
type Circle implements Shape {
	radius: Float
	area: Float
}
union Shapes = Circle
```
`Circle`将满足`Circle`, `Shape`, 和`Shapes`— 这些值应该被传递给以`CollectFieldsCtx`获取已解析`Circle`对象的收集字段集。

**实际例子**
```GraphQL
query {  
   flowBlocks {  
      id  
      block {  
         id  
         title  
         type  
         choices {  
            id  
            title  
            description  
            slug  
         }    
      }  
   }  
}
```
我们不想过度获取我们的数据库，所以我们想知道请求了哪个字段。这是一个将所有请求的字段作为方便的字符串切片的示例，可以轻松检查。
```go
func GetPreloads(ctx context.Context) []string {  
   return GetNestedPreloads(  
      graphql.GetOperationContext(ctx),  
      graphql.CollectFieldsCtx(ctx, nil),  
      "",  
   )  
}  
  
func GetNestedPreloads(ctx *graphql.OperationContext, fields []graphql.CollectedField, prefix string) (preloads []string) {  
   for _, column := range fields {  
      prefixColumn := GetPreloadString(prefix, column.Name)  
      preloads = append(preloads, prefixColumn)  
      preloads = append(preloads, GetNestedPreloads(ctx, graphql.CollectFields(ctx, column.Selections, nil), prefixColumn)...)  
   }  
   return  
}  
  
func GetPreloadString(prefix, name string) string {  
   if len(prefix) > 0 {  
      return prefix + "." + name  
   }  
   return name  
}
```
因此，我们如果在解析器中调用这些助手
```go
func (r *queryResolver) FlowBlocks(ctx context.Context) ([]*FlowBlock, error) { 
	preloads := GetPreloads(ctx)
}
```
它将返回以下字符串切片
```go
["id", "block", "block.id", "block.title", "block.type", "block.choices", "block.choices.id", "block.choices.title", "block.choices.description", "block.choices.slug"]
```

-----
### 上传文件
[docs](https://gqlgen.com/reference/file-upload/)

GraphQL服务器已经内置了Upload标量，用于使用多部份请求上传文件。
它实现了以下规范[https://github.com/jaydenseric/graphql-multipart-request-spec](https://github.com/jaydenseric/graphql-multipart-request-spec)，它为 GraphQL 请求定义了一个可互操作的多部分表单字段结构，供各种文件上传客户端实现使用。
要使用它，您需要在架构中添加 Upload 标量，它会自动将编组行为添加到 Go 类型。

**配置**
可以为上传文件配置两个特定选项
- `uploadMaxSize` 
	- 此选项指定用于将请求正文解析为 `multipart/form-data` 的最大字节数。
- uploadMaxMemory
	- 此选项指定用于将请求正文解析为内存中的 `multipart/form-data`的最大字节数，其余字符存储在磁盘的临时文件中。

**例子**
单个文件上传
对于此用例，Schema可能如下所示。
```GraphQL  
"The `UploadFile, // b.txt` scalar type represents a multipart file upload."  
scalar Upload  
  
"The `Query` type, represents all of the entry points into our object graph."  
type Query {  
	...  
}  
  
"The `Mutation` type, represents all updates we can make to our data."  
type Mutation {  
	singleUpload(file: Upload!): Boolean!  
}
```
cURL可用于进行如下查询
```shell
curl localhost:4000/graphql \ 
	-F operations='{ "query": "mutation ($file: Upload!) { singleUpload(file: $file) }", "variables": { "file": null } }' \
	-F map='{ "0": ["variables.file"] }' \
	-F 0=@a.txt
```
这会调用以下操作
```GraphQL
{  
   query: `  
      mutation($file: Upload!) {
        singleUpload(file: $file)
      }     `,  
   variables: {  
	   file: File // a.txt  
   }  
}
```
多个文件上传就不作展示了。可参考文档

-----
### 处理错误
#### 返回错误
所有解析器返回错误将会发送给用户。这是假设这里返回任何错误给用户都是合适的。如果确定信息是不安全的，定制错误展示

**多错误 Multiple Error**
返回多错误，你可以调用 `graphql.Error` 方法，像这样
```go
package foo  
  
import (  
"context"  
  
"github.com/vektah/gqlparser/v2/gqlerror"  
"github.com/99designs/gqlgen/graphql"  
)  
  
func (r Query) DoThings(ctx context.Context) (bool, error) {  
   // Print a formatted string  
   graphql.AddErrorf(ctx, "Error %d", 1)  
  
   // Pass an existing error out  
   graphql.AddError(ctx, gqlerror.Errorf("zzzzzt"))  
  
   // Or fully customize the error  
   graphql.AddError(ctx, &gqlerror.Error{  
      Path:       graphql.GetPath(ctx),  
      Message:    "A descriptive error message",  
      Extensions: map[string]interface{}{  
         "code": "10-4",  
      },  
   })  
  
   // And you can still return an error if you need  
   return false, gqlerror.Errorf("BOOM! Headshot")  
}
```

他们将会返回相同的信息在`response`中，例如：

```json
{
  "data": {
    "todo": null
  },
  "errors": [
    { "message": "Error 1", "path": [ "todo" ] },
    { "message": "zzzzzt", "path": [ "todo" ] },
    { "message": "A descriptive error message", "path": [ "todo" ], "extensions": { "code": "10-4" } },
    { "message": "BOOM! Headshot", "path": [ "todo" ] }
  ]
}
```

#### Hooks
**错误主持 The error presenter**
所有通过解析器或从验证返回的`errors`都会通过一个hook。这个hook给了你定制返回错误给app的能力。

默认的`error presenter`将会拦截解析器路径和在response中使用错误信息的请求。

你可以在创建服务的时候改变这个
```go

server := handler.NewDefaultServer(MakeExecutableSchema(resolvers))  
server.SetErrorPresenter(func(ctx context.Context, e error) *gqlerror.Error {  
   err := graphql.DefaultErrorPresenter(ctx, e)  
  
   var myErr *MyError  
   if errors.As(e, &myErr) {  
      err.Message = "Eeek!"  
   }  
  
   return err  
})
```

将使用生成它的相同解析器上下文调用此函数，因此您可以提取当前解析器路径以及您可能想要通知客户端的任何其他状态。


**panic 处理 The panic handler**
这同样也是`panic handler`，每当发生panic时，在停止解析之前，优雅的返回信息。这是一个很棒的点去通知`bug tracker`同时发送定制消息给用户。任何错误从这里返回将同样穿过`error presenter`

-----
### 自我检查 Introspection 
禁用自我检查

GraphQL中一个最大的特性是强大的可发现性，当你使用`NewDefaultServer`时，将默认包含

#### 禁用整个服务的自我检查
要在全局范围内选择退出自省，您应该仅使用您使用的功能构建自己的服务器
举个例子，一个简单的服务器只处理POST请求，并且只在开发时自省
```go
srv := handler.New(es)  
  
srv.AddTransport(transport.Options{})  
srv.AddTransport(transport.POST{})  
  
if os.GetEnv("ENVIRONMENT") == "development" {  
	srv.Use(extension.Introspection{})  
}
```

#### 禁用基于身份验证的自省
也可以在每个请求context的基础上启用自省。例如，您可以在基于用户身份验证的中间件对其进行修改。
```go
srv := handler.NewDefaultServer(es)  
srv.AroundOperations(func(ctx context.Context, next graphql.OperationHandler) graphql.ResponseHandler {  
   if !userForContext(ctx).IsAdmin {  
      graphql.GetOperationContext(ctx).DisableIntrospection = true  
   }  
  
   return next(ctx)  
})
```

### 名称冲突 Name Collision
处理命名冲突

虽然大多数生成的 Golang 类型必须具有唯一的名称，因为它们基于它们的 GraphQL`type`对应物，它们本身必须是唯一的，但有一些边缘场景可能会发生冲突。本文档描述了如何处理这些冲突。

#### 枚举 Enum
枚举类型生成是可能发生命名冲突的一个主要示例，因为我们将每个值的const名称构建为枚举名称和每个单独值的组合

示例
```GraphQL
enum MyEnum {
	value1
	value2
	value3
	value4
}
```
这将导致以下 Golang：
```go
// golang  
  
type MyEnum string  
  
const (  
   MyEnumValue1 MyEnum = "value1"  
   MyEnumValue2 MyEnum = "value2"  
   MyEnumValue3 MyEnum = "value3"  
   MyEnumValue4 MyEnum = "value4"  
)
```
但是，上面的枚举值只是字符串。如果您遇到需要执行以下操作的情况怎么办：
```GraphQL  
# graphql  
  
enum MyEnum {  
   value1  
   value2  
   value3  
   value4  
   Value4  
   Value_4  
}
```
和枚举值不能直接转换为相同的“漂亮”命名约定，因为它们生成的常量名称会与 的名称冲突`Value4`，如下所示：`Value_4``value4`
```go
// golang  
  
type MyEnum string  
  
const (  
   MyEnumValue1 MyEnum = "value1"  
   MyEnumValue2 MyEnum = "value2"  
   MyEnumValue3 MyEnum = "value3"  
   MyEnumValue4 MyEnum = "value4"  
   MyEnumValue4 MyEnum = "Value4"  
   MyEnumValue4 MyEnum = "Value_4"  
)
```
这回立即导致编译错误，因为我们现在有三个同名但是值不同的常量。

**解法**
- 将生成的每个名字存储为运行的一部分以供以后比较
- 尝试将`name`强转换为`CapitalCase`。如果没有冲突，请使用。
	- 此过程尝试将标识符分解为单词，通过大写字母、下划线、连字符和空格来标识。
	- 每个单词都大写并附加到前一个单词。
- 如果是非复合名称，则将整数附加到名称的末尾，从 0 开始到`math.MaxInt`
- 如果复合名称，以相反的顺序，名称的各个部分应用了一个不太固执的转换器
- 如果所有其他方法都失败，则将整数附加到名称的末尾，从 0 开始到`math.MaxInt`


-----
### 插件 Plugin
在gqlgen中，怎么写插件

插件提供了一种hook到 gqlgen 代码生成生命周期的方法。为了使用默认插件以外的任何东西，您需要创建自己的入口点：
```go  
// +build ignore  
package main  
  
import (  
"flag"  
"fmt"  
"io"  
"log"  
"os"  
"time"  
  
"github.com/99designs/gqlgen/api"  
"github.com/99designs/gqlgen/codegen/config"  
"github.com/99designs/gqlgen/plugin/stubgen"  
)  
  
func main() {  
   cfg, err := config.LoadConfigFromDefaultLocations()  
   if err != nil {  
      fmt.Fprintln(os.Stderr, "failed to load config", err.Error())  
      os.Exit(2)  
   }  
  
  
   err = api.Generate(cfg,  
      api.AddPlugin(yourplugin.New()), // This is the magic line  
   )  
   if err != nil {  
      fmt.Fprintln(os.Stderr, err.Error())  
      os.Exit(3)  
   }  
}
```

#### 写插件
当前只有两种 hooks
- MutateConfig： 允许插件在 codegen 启动之前改变配置。这个允许插件定制化指令，定义类型，实现解析器。[案例 modelgen](https://github.com/99designs/gqlgen/tree/master/plugin/modelgen)
- GenerateCode：允许插件生成新的输出文件，[案例 stubgen](https://github.com/99designs/gqlgen/tree/master/plugin/stubgen)

可在[plugin.go](https://github.com/99designs/gqlgen/blob/master/plugin/plugin.go)查看完整hooks


-----
### 查询复杂度 Query Complexity
防止过于复杂的查询

GraphQL 提供了一种强大的数据查询方式，但将强大的功能交给 API 客户端也会使您面临拒绝服务攻击的风险。您可以通过限制您允许的查询的复杂性来降低 gqlgen 的风险。

**昂贵的代价**
考虑一个允许列出博客文章的模式。每篇博文也与其他博文相关。
```GraphQL  
type Query {  
   posts(count: Int = 10): [Post!]!  
}  
  
type Post {  
   title: String!  
   text: String!  
   related(count: Int = 10): [Post!]!  
}
```
制作一个会引起很大响应的查询并不难：
```GraphQL
{
  posts(count: 100) {
    related(count: 100) {
      related(count: 100) {
        related(count: 100) {
          title
        }
      }
    }
  }
}
```
响应的大小随着`related`字段的每个附加级别呈指数增长。幸运的是，gqlgen `http.Handler`包含一种方法来防范这种类型的查询。

#### 限制查询复杂性
限制查询复杂性就像使用提供的扩展包指定它一样简单。
```go
func main() {
	c := Config{ Resolvers: &resolvers{} }
	srv := handler.NewDefaultServer(blog.NewExecutableSchema(c))
	srv.Use(extension.FixedComplexityLimit(5)) // This line is key
	r.Handle("/query", srv)
}
```
现在任何复杂度大于 5 的查询都会被 API 拒绝。默认情况下，每个字段和深度级别都会使整体查询复杂性增加一个。您还可以使用`extension.ComplexityLimit`动态配置每个请求的复杂性限制。

这有帮助，但我们仍然有一个问题：返回数组的`posts`and字段比标量和字段`related`的解析成本要高得多。但是，默认的复杂性计算对它们进行同等加权。对数组字段应用更高的成本会更有意义。`title``text`

#### 自定义复杂度计算
要将更高的成本应用于某些领域，我们可以使用自定义复杂度函数。
```go
func main() {
	c := Config{ Resolvers: &resolvers{} }

	countComplexity := func(childComplexity, count int) int {
		return count * childComplexity
	}
	c.Complexity.Query.Posts = countComplexity
	c.Complexity.Post.Related = countComplexity

	srv := handler.NewDefaultServer(blog.NewExecutableSchema(c))
	srv.Use(extension.FixedComplexityLimit(5))
	http.Handle("/query", gqlHandler)
}
```
当我们将函数分配给适当的`Complexity`字段时，该函数将用于复杂度计算。在这里，`posts`和`related`字段根据其`count`参数的值进行加权。这意味着客户端请求的帖子越多，查询复杂度就越高。就像我们原始查询中响应的大小会成倍增加一样，复杂性也会成倍增加，因此任何试图滥用 API 的客户端都会很快遇到限制。

通过应用查询复杂性限制并在正确的位置指定自定义复杂性函数，您可以轻松防止客户端使用不成比例的资源并中断您的服务。


-----
### 解析器 Resolvers
解决 graphQL 请求

有多种方法可以将 graphQL 类型绑定到允许许多用例的 Go 结构。

#### 直接绑定到结构体字段名称

这是最常见的用例，Go 结构中的字段名称与 graphQL 类型中的字段名称匹配。如果 Go 结构字段未导出，则不会绑定到 graphQL 类型。
```go
type Car struct {
    Make string
    Model string
    Color string
    OdometerReading int
}
```
然后在您的 graphQL 模式中：
```GraphQL
type Car {
    make: String!
    model: String!
    color: String!
    odometerReading: Int!
}
```
在 gqlgen 配置文件中：
```yaml
models:
    Car:
        model: github.com/my/app/models.Car
```
在这种情况下，graphQL 类型中的每个字段都将绑定到 go 结构上的相应字段，而忽略字段的大小写

#### 绑定到方法名称
这也是非常常见的用例，我们希望将 graphQL 字段绑定到 Go 结构方法
```go
type Person struct {
    Name string
}

type Car struct {
    Make string
    Model string
    Color string
    OwnerID *string
    OdometerReading int
}

func (c *Car) Owner() (*Person) {
    // get the car owner
    //....
    return owner
}
```
然后在您的graphQL中
```GraphQL
type Car {
    make: String!
    model: String!
    color: String!
    odometerReading: Int!
    owner: Person
}
```
在 gqlgen 配置文件中：
```yaml
models:
    Car:
        model: github.com/my/app/models.Car
    Person:
        model: github.com/my/app/models.Person
```
在这里，我们看到 car 上有一个名为 的方法`Owner`，因此`Owner`如果 graphQL 请求包含要解析的字段，则该函数将被调用。

模型方法可以选择将上下文作为其第一个参数。如果需要上下文，模型方法也将并行运行。

#### 字段名称不匹配时绑定
当 Go 结构和 graphQL 类型不匹配时，有两种方法可以绑定到字段。
第一种方法是您可以将解析器绑定到基于结构标签的结构，如下所示：
```go
type Car struct {
    Make string
    ShortState string
    LongState string `gqlgen:"state"`
    Model string
    Color string
    OdometerReading int
}
```
然后在您的 graphQL 模式中：
```GraphQL
type Car {
    make: String!
    model: String!
    state: String!
    color: String!
    odometerReading: Int!
}
```
并在 gqlgen 配置文件中添加以下行：
```YAML
struct_tag: gqlgen

models:
    Car:
        model: github.com/my/app/models.Car
```
在这里，即使 graphQL 类型和 Go 结构具有不同的字段名称，也有一个`longState` 匹配的 Go 结构标记字段，因此`state`将绑定到`LongState`.

绑定字段的第二种方法是在配置文件中添加一行，例如：
```go
type Car struct {
    Make string
    ShortState string
    LongState string
    Model string
    Color string
    OdometerReading int
}
```
然后在您的 graphQL 模式中：

```graphql
type Car {
    make: String!
    model: String!
    state: String!
    color: String!
    odometerReading: Int!
}
```
并在 gqlgen 配置文件中添加以下行：

```yaml
models:
    Car:
        model: github.com/my/app/models.Car
        fields:
            state:
                fieldName: LongState
```

#### 绑定到匿名或嵌入式结构

上面的所有规则都适用于具有嵌入式结构的结构。这是一个例子
```go
type Truck struct {
    Car
    Is4x4 bool
}

type Car struct {
    Make string
    ShortState string
    LongState string
    Model string
    Color string
    OdometerReading int
}
```

然后在您的 graphQL 模式中：
```graphql
type Truck {
    make: String!
    model: String!
    state: String!
    color: String!
    odometerReading: Int!
    is4x4: Bool!
}
```
在这里，Go struct Car 中的所有字段仍将绑定到 graphQL 模式中匹配的相应字段

嵌入式结构是围绕数据访问类型创建瘦包装器的好方法，示例如下：
```go
type Cat struct {
    db.Cat
    //...
}

func (c *Cat) ID() string {
    // return a custom id based on the db shard and the cat's id
     return fmt.Sprintf("%d:%d", c.Shard, c.Id)
}
```

这将与以下 gqlgen 配置文件相关：
```yaml
models:
    Cat:
        model: github.com/my/app/models.Cat
```

#### 绑定优先级

如果`struct_tags`存在配置，则结构标记绑定比所有其他类型的绑定具有最高优先级。在所有其他情况下，找到的第一个与 graphQL 类型字段匹配的 Go 结构字段将是绑定的字段。


-----
### 标量 Scalars

#### 内置
gqlgen 为常见的自定义标量用例`Time`、`Any`、`Upload`和`Map`. 将这些中的任何一个添加到模式中都会自动将编组行为添加到 Go 类型中。

##### 时间

```graphql
scalar Time
```
`Time`将GraphQL 标量映射到 Go结构`time.Time`。此标量遵循[time.RFC3339Nano](https://pkg.go.dev/time#pkg-constants)格式。

##### 地图

```graphql
scalar Map
```
将任意 GraphQL 值映射到`map[string]interface{}`Go 类型。

##### 上传

```graphql
scalar Upload
```
`Upload`将GraphQL 标量映射到结构`graphql.Upload`，定义如下：
```go
type Upload struct {
	File        io.ReadSeeker
	Filename    string
	Size        int64
	ContentType string
}
```

##### 任何
```graphql
scalar Any
```
将任意 GraphQL 值映射到`interface{}`Go 类型。


#### 具有用户定义类型的自定义标量
对于用户定义的类型，您可以实现[graphql.Marshaler](https://pkg.go.dev/github.com/99designs/gqlgen/graphql#Marshaler)和[graphql.Unmarshaler](https://pkg.go.dev/github.com/99designs/gqlgen/graphql#Unmarshaler)或实现[graphql.ContextMarshaler](https://pkg.go.dev/github.com/99designs/gqlgen/graphql#ContextMarshaler)和[graphql.ContextUnmarshaler](https://pkg.go.dev/github.com/99designs/gqlgen/graphql#ContextUnmarshaler)接口，它们将被调用。

```go
type YesNo bool

// UnmarshalGQL implements the graphql.Unmarshaler interface
func (y *YesNo) UnmarshalGQL(v interface{}) error {
	yes, ok := v.(string)
	if !ok {
		return fmt.Errorf("YesNo must be a string")
	}

	if yes == "yes" {
		*y = true
	} else {
		*y = false
	}
	return nil
}

// MarshalGQL implements the graphql.Marshaler interface
func (y YesNo) MarshalGQL(w io.Writer) {
	if y {
		w.Write([]byte(`"yes"`))
	} else {
		w.Write([]byte(`"no"`))
	}
}

```
然后连接 .gqlgen.yml 中的类型或通过正常的指令：
```yaml
models:
  YesNo:
    model: github.com/me/mypkg.YesNo
```

#### 具有第三方类型的自定义标量
有时您无法将添加方法添加到一个类型 - 也许您不拥有该类型，或者它是标准库的一部分（例如 string 或 time.Time）。为了支持这一点，我们可以构建一个外部封送器：
```go
package mypkg

import (
    "fmt"
    "io"
    "strings"
    "github.com/99designs/gqlgen/graphql"
)

func MarshalMyCustomBooleanScalar(b bool) graphql.Marshaler {
    return graphql.WriterFunc(func(w io.Writer) {
        if b {
            w.Write([]byte("true"))
        } else {
            w.Write([]byte("false"))
        }
    })
}

func UnmarshalMyCustomBooleanScalar(v interface{}) (bool, error) {
    switch v := v.(type) {
    case string:
        return "true" == strings.ToLower(v), nil
    case int:
        return v != 0, nil
    case bool:
        return v, nil
    default:
        return false, fmt.Errorf("%T is not a bool", v)

    }

}
```
然后在 .gqlgen.yml 中指向前面没有 Marshal|Unmarshal 的名称：
```yaml
models:
  MyCustomBooleanScalar:
    model: github.com/me/mypkg.MyCustomBooleanScalar
```
**注意：** 您也可以通过这种方法取消/编组指针类型，只需在您的 func 中接受一个指针并在您的 `Marshal...`func 中返回一个`Unmarshal...`。
**注意：** 您还可以通过让您的自定义编组函数返回 a `graphql.ContextMarshaler` _并且_您的解组函数将 a`context.Context`作为第一个参数来取消/编组上下文。
有关更多示例，请参见[_examples/scalars](https://github.com/99designs/gqlgen/tree/master/_examples/scalars)包

#### 编组/解组错误

作为自定义标量编组/解组的一部分发生的错误将返回该字段的完整路径。例如，给定以下架构……
```graphql
extend type Mutation{
    updateUser(userInput: UserInput!): User!
}

input UserInput {
    name: String!
    primaryContactDetails: ContactDetailsInput!
    secondaryContactDetails: ContactDetailsInput!
}

scalar Email
input ContactDetailsInput {
    email: Email!
}
```
…以及以下变量：
```json
{
  "userInput": {
    "name": "George",
    "primaryContactDetails": {
      "email": "not-an-email"
    },
    "secondaryContactDetails": {
      "email": "george@gmail.com"
    }
  }
}
```
… 以及一个 unmarshal 函数，如果电子邮件无效则返回错误。突变将返回包含完整路径的错误：
```json
{
  "message": "email invalid",
  "path": [
    "updateUser",
    "userInput",
    "primaryContactDetails",
    "email"
  ]
}
```
**注意：**`graphql.ContextMarshaler`只有在使用样式接口时才能返回编组错误。

-----
### 模式指令 Schema Directives
使用模式指令实现权限检查

指令的作用有点像注解、装饰器或 HTTP 中间件。它们为您提供了一种基于字段或参数以通用且可重用的方式指定某些行为的方法。这对于横切关注点非常有用，例如可以在 API 中广泛应用的权限检查。

**注意**：当前的指令实现仍然相当有限，旨在涵盖最常见的“现场中间件”情况。

#### 基于用户角色限制访问

例如，我们可能希望根据经过身份验证的用户的角色来限制客户端可以进行哪些突变或查询：

```graphql
type Mutation {
	deleteUser(userID: ID!): Bool @hasRole(role: ADMIN)
}
```

##### 在模式中声明它

在我们可以使用指令之前，我们必须在模式中声明它。以下是我们定义`@hasRole`指令的方式：

```graphql
directive @hasRole(role: Role!) on FIELD_DEFINITION

enum Role {
    ADMIN
    USER
}
```

接下来，运行`go generate`，gqlgen 会将指令添加到 DirectiveRoot：

```go
type DirectiveRoot struct {
	HasRole func(ctx context.Context, obj interface{}, next graphql.Resolver, role Role) (res interface{}, err error)
}
```

论据是：

-   _ctx_ : 父上下文
-   _obj_：包含 this 应用于的值的对象，例如：
    -   对于字段定义指令 ( `FIELD_DEFINITION`)，包含字段的对象/输入对象
    -   对于参数指令 ( `ARGUMENT_DEFINITION`)，包含所有参数的映射
-   _next_：指令链中的下一个指令，或字段解析器。应该调用它来获取字段/参数/其他的值。`next(ctx)` 例如，您可以通过在检查用户是否具有所需权限后不调用来阻止对该字段的访问。
-   _…args_：最后，指令模式定义中定义的任何参数都被传入

#### 执行指令

现在我们必须执行该指令。指令函数在注册 GraphQL 处理程序之前分配给 Config 对象。

```go
package main

func main() {
	c := generated.Config{ Resolvers: &resolvers{} }
	c.Directives.HasRole = func(ctx context.Context, obj interface{}, next graphql.Resolver, role model.Role) (interface{}, error) {
		if !getCurrentUser(ctx).HasRole(role) {
			// block calling the next resolver
			return nil, fmt.Errorf("Access denied")
		}

		// or let it pass through
		return next(ctx)
	}

	http.Handle("/query", handler.NewDefaultServer(generated.NewExecutableSchema(c), ))
	log.Fatal(http.ListenAndServe(":8081", nil))
}
```

而已！您现在可以将该`@hasRole`指令应用于架构中的任何突变或查询。