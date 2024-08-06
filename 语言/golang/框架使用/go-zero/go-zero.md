# go-zero

此章将框架的使用。

建议直接看go-zero的github，此文档操作仅记录学习过程。

使用前我们的理解如下：

1. 它是一个微服务框架
2. 它能实现单体的http服务
3. 他能根据API生成代码（具体API是啥，长啥样不知道）
4. 它是一个脚手架，默认能生成一些目录，使代码可能更规范。



我们按照官方文档的Quick Start来操作，

> （github上有我就直接按照github走了，若没有才从官方网站找）
>
> https://github.com/zeromicro/go-zero/blob/master/readme-cn.md



以下描述不一定准确，仅根据认知决定。

安装"脚手架"，其可以自动生成一些代码

- 安装go-ctl，官方文档描述为 go control，

```go
go install github.com/zeromicro/go-zero/tools/goctl@latest
```

使用脚手架初始化一个项目模板

```shell
goctl api new greet
cd greet
go mod tidy
go run greet.go -f etc/greet-api.yaml
```

此时我们输出当前创建的文件：

```shell
tree /F
│  go.mod
│  go.sum
│  greet.api
│  greet.go
│
├─etc
│      greet-api.yaml
│
└─internal
    ├─config
    │      config.go
    │
    ├─handler
    │      greethandler.go
    │      routes.go
    │
    ├─logic
    │      greetlogic.go
    │
    ├─svc
    │      servicecontext.go
    │
    └─types
            types.go
```

其内有 greet.api文件，文档中描述其定义了对外的HTTP接口，可参考 [api 规范](https://github.com/zeromicro/zero-doc/blob/main/docs/zero/goctl-api.md)

我们按照[api 规范](https://github.com/zeromicro/zero-doc/blob/main/docs/zero/goctl-api.md)中的实例，来生成一个user的http

在当前目录中

```go
goctl api go -api user.api -dir .
```

他还会生成一个user.go，且其中包含main方法，与我们上层的greet冲突。

（看来是使用的不对，又或者，其使用方式是一个项目一个.api文件？）

通过以下网上搜索到的文章，感觉 go-zero的http服务定义就是BFF层，几乎不涉及数据库调用，主要使用grpc原生调具体的微服务来实现业务。

> https://www.cnblogs.com/kevinwan/p/16369542.html

换句话说，我可能不是很理解这个目录结构，因不清楚db相关放在哪里比较合适。是放在svc中？还是是放在handler中？

- svc 部分
  - 应该是作为全局的控制依赖，大部分数据都是依赖于此
- handler 部分
  - 看着是能写些"闭包"变量，用作临时缓存或逻辑的处理。

但放在上述两个位置可能都有不同的问题

例如

1. 若是我习惯用dao层，且将所有dao都塞入svc中，那么svc可能会变成一个灾难。但在某种意义上，若是将svc中配置的更有条理，可能会更合理。
   - 我猜测他是 svc 直接存DB级别的dao层，例如 ent 或 gorm.gen 生成的最外部的库，不提供具体dao层。Logic直接接收
     - 这样有个好处，开事务方便。（事务都是db级别，会跨表，现在大多数dao定义都基于表）
     - 但是后续若是有库变动表有变动，你无法直观的确定哪个logic使用了变动的库，维护非常麻烦
     - 单测感觉会爆炸？
   - 或者是具体dao层在handler层初始化，并放在内部变量中，只给Logic传递有限的dao数据。
     - 初步看还行，具体不确定。