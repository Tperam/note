#graphql 
[GraphQL介绍](https://graphql.org/learn/schema/)

GraphQL是什么，让我猜一猜，这是不是一个类似SQL的东西？SQL 意味着 Structure Query Language。那GraphQL是不是就是GraphQL Query Language？

为什么要学习GraphQL？这是一种较新的概念，因框架gqlgen配合了其概念，而且对于其具体设计，相比于rest风格API，其所需字段，查询内容更加的清晰明了。（也更是因于此，查询时可能需要附带更多的逻辑，这也是额外的负担。）
[[golang/框架使用/gqlgen/README]] 

### 类型系统

GraphQL 查询语言是基于对象的字段选择。
下面为一个查询案例
```GraphQL
{
  hero {
    name
    appearsIn
  }
}
```
1. 我们以`root`对象开始
2. 我们查询了`hero`字段
3. 对于`hero`的字段，我们选择了它的`name`字段和`appearsIn`字段
下面为返回值
```GraphQL
{
  "data": {
    "hero": {
      "name": "R2-D2",
      "appearsIn": [
        "NEWHOPE",
        "EMPIRE",
        "JEDI"
      ]
    }
  }
}
```
因为GraphQL查询非常类似于匹配结果，你可以在不清楚服务器的情况下，预测查询将会返回什么。但他需要精确的数据描述：我们能查询到什么字段？他们可能返回什么对象类型？什么字段在这些子对象上可用？这就是模式的应用。

每一个GraphQL服务定义了一个集合类型，其完整描述了能在集合中查询到的所有数据。当查询来时，他将会验证和执行该模式

### 类型定义
GraphQL 服务可以被任何语言所实现。因为其不依赖任何语言语法。像是JavaScript，也可以实现该类型模式。或者说，这就像是一个SQL语句。

### 对象类型和字段
GraphQL的大多数基础组件是`Object`类型，就是一种你从你服务器获取的对象与字段。在GraphQL 模式语言中，我们代表他像：
```GraphQL
type Character {
	name: String!
	appearsIn: [Episode!]!
}
```
语言可读性很强，简单解释一下：
- `Character` 是一个GraphQL对象类型，意思是这个类型有一些字段。在你的模式（schema）中大多数将会是它
- `name` 与`appearsIn` 是`Character`字段。那意味着在GraphQL中，`name`和`appearsIn`是`Character`对象中唯一能被访问和查询的字段。
- `String`是一个内置标记类型（变量类型），规定在查询时其不能有子选项
- `String!` 代表不能为空，意味着在你查询时GraphQL服务器将会保证给你返回值。在类型语言中，我们以感叹号标记
- `[Episode!]!` 代表这是一个`Episode`数组对象。同样，他也是非空的（包括0，或更多对象）。因为`Episode!`也是一个非空对象，你总是能从其中取出`Episode`对象。

### 参数
每一个GraphQL对象的字段都可以可以有0或更多的参数，例如：长度
```GraphQL
type Starship{
	id: ID!
	name: String!
	length(unit: LengthUnit = METER): Float
}
```
所有参数是被命名的，不像是js或python的方法，将获取一个列表用于参数。在GraphQL中，所有的参数必须是被特殊明明的。在这个案例中，`length`字段定义了一个参数 `unit`
参数可以选择必填或可选。当参数可选时，我们将定义一个默认值，如果`unit`参数不传，他将`METER`设为默认值


### 查询和突变类型
在schema中，大多数类型是正常对象，但是有两个特殊类型在schema里

```GraphQL
schema {
	query: Query
	mutation: Mutation
}
```
每一个GraphQL服务都必须有`query`类型，可以有也可以没有`mutation`。这个类型是规则对象类型，但他们是特殊的，因为他们是定义每个GraphQL查询的入口。所以你可以看到查询类似这样：
```GraphQL
query {
	hero {
		name
	}
	droid(id: "2000") {
		name
	}
}
```
result
```
{
	"data": {
		"hero": {
			"name": "R2-D2"
		},
		"droid": {
			"name": "C-3PO"
		}
	}
}
```
上面意味着GraphQL服务的`Query`类型有`hero`和`droid`字段
```GraphQL
type Query {
	hero(episode: Episode): Character
	droid(id:ID!): Droid
}
```
突变工作方式是相似的。你定义突变字段，那些根突变字段你可以在你的查询中调用。

除了作为模式(schema)的入口点以外，`Query`和`Mutation`类型与其他任何GraphQL对象类型相同，并且他们的工作方式完全相同。

### 标量类型

GraphQL对象有名字和字段，但一些字段必须解析一些确切的数据。这就是标量类型（变量类型），他们代表查询的叶子（查询的值或具体的值）

在下面的查询中，`name`与`appearsIn`字段将会解析为标量类型
```GraphQL
{
	hero{
		name
		appearsIn
	}
}
```


```GraphQL
{
  "data": {
    "hero": {
      "name": "R2-D2",
      "appearsIn": [
        "NEWHOPE",
        "EMPIRE",
        "JEDI"
      ]
    }
  }
}
```

我们知道这些因为有些字段不包含任何子字段，他们是查询的叶子。
GraphQL 默认给标量类型为：
- `Int`: 32-bit
- `Float`: 双精度浮点
- `String` UTF-8 字符串
- `Boolean`: 布尔值
- `ID`: ID 标量类型代表唯一的身份，通常用于重取对象或用于缓存的`key`。ID类型的序列化方式与`String`相同。无论如何定义它为`ID`表示这不是人类可读的

在大多数GraphQL服务是线上，这是一种定义标量类型的方式：
```GraphQL
scalar Date
```

然后由我们的实现来定义应该如何序列化、反序列化和验证该类型。例如，您可以指定该`Date`类型应始终序列化为整数时间戳，并且您的客户端应该知道该格式适用于任何日期字段。


### Enum 枚举

GraphQL模式语言定义样子：
```GraphQL
enum Episode {
  NEWHOPE
  EMPIRE
  JEDI
}
```

### 列表和非 Null

定义如下
```GraphQL
type Character {
	name: String!
	appearsIn: [Episode]!
}
```
通过`!`符号，用于表示当前变量类型不为空。
通过`[]`表示，当前类型为列表。
当出现异常时，将会处罚GraphQL执行错误

非空类型`!`同样也可以在定义参数时使用，如果传空，也将导致GraphQL报错。
定义的类型
```GraphQL
query DroidById($id: ID!) {
  droid(id: $id) {
    name
  }
}
```
查询操作
```GraphQL
{
	"id": null
}
```
返回结果
```GraphQl
{
  "errors": [
    {
      "message": "Variable \"$id\" of non-null type \"ID!\" must not be null.",
      "locations": [
        {
          "line": 1,
          "column": 17
        }
      ]
    }
  ]
}
```

列表的工作方式与上相同。我们可以定义类型为List为`[type]`，通过中括号将数组对象包括住。

非空`!`与`[]`可以联合使用，比如：
```GraphQl
myField: [String!]
```
这意味着列表自己可以为空，但不能包括任何的非空元素，例如JSON：
```GraphQL
myField: null // valid
myField: [] // valid
myField: ['a', 'b'] // valid
myField: ['a', null, 'b'] // error
```
以下是`[String]!`的效果
```GraphQL
myField: null // error
myField: [] // valid
myField: ['a', 'b'] // valid
myField: ['a', null, 'b'] // valid
```

### 接口
就像是类型系统，GraphQL支持接口。Interface是抽象类型，包含一些的集合的字段。当有类型想要实现接口时，必须实现Interface中的字段。
例如
```GraphQL
interface Character{
	id: ID!
	name: String!
	friends: [Character]
	appearsIn: [Episode]!
}
```
这意味着实现`Character`必须包含这些指定字段

```GraphQL
type Human implements Character {
  id: ID!
  name: String!
  friends: [Character]
  appearsIn: [Episode]!
  starships: [Starship]
  totalCredits: Int
}

type Droid implements Character {
  id: ID!
  name: String!
  friends: [Character]
  appearsIn: [Episode]!
  primaryFunction: String
}
```
你可以看到这两个类型都包含了`Character`接口中的字段，同时还额外附带了一些字段。这就是特殊的部分。

当你想要返回一个对象集合，但这些可能是几个不同的类型时，Interface就非常有用了。
举个例子
```GraphQL
query HeroForEpisode($ep: Episode!) {
  hero(episode: $ep) {
    name
    primaryFunction
  }
}
```

```GraphQL
{
  "ep": "JEDI"
}
```

```GraphQL
{
  "errors": [
    {
      "message": "Cannot query field \"primaryFunction\" on type \"Character\". Did you mean to use an inline fragment on \"Droid\"?",
      "locations": [
        {
          "line": 4,
          "column": 5
        }
      ]
    }
  ]
}
```

`hero`字段返回的类型是Character，他根据`Episode`参数决定返回`Human`和`Droid`。
在上面的查询中，你可能只能请求存在于`Character`接口中的字段，其不包含`primaryFunction`
为了访问具体的对象字段，你需要使用内敛分段

```GraphQL
query HeroForEpisode($ep: Episode!) {
  hero(episode: $ep) {
    name
    ... on Droid {
      primaryFunction
    }
  }
}
```

```GraphQL
{
  "ep": "JEDI"
}
```

```GraphQL
{
  "data": {
    "hero": {
      "name": "R2-D2",
      "primaryFunction": "Astromech"
    }
  }
}
```

### 联合类型
联合类型非常像Interface，但他们二者没有任何的共同字段

```GraphQL
union SearchResult = Human | Droid | Starship
```
无论如何，我们返回`SearchResult`类型在我们的模式中，我们可以获取`Human`，`Droid`，`Starship`。注意，联合类型的成员必须是具体的对象，你不能创造联合类型为Interface或其他的联合类型。

在下面的例子中，如果你查询字段返回`SearchResult` 联合类型，你需要去使用`inline fragment`去查询任意字段。
```GraphQL
{
  search(text: "an") {
    __typename
    ... on Human {
      name
      height
    }
    ... on Droid {
      name
      primaryFunction
    }
    ... on Starship {
      name
      length
    }
  }
}
```

```GraphQL
{
  "data": {
    "search": [
      {
        "__typename": "Human",
        "name": "Han Solo",
        "height": 1.8
      },
      {
        "__typename": "Human",
        "name": "Leia Organa",
        "height": 1.5
      },
      {
        "__typename": "Starship",
        "name": "TIE Advanced x1",
        "length": 9.2
      }
    ]
  }
}
```
`__typenames`字段解析为`String`
在这个例子中，因为`Human`和`Droid`拥有共同的Interface(`Character`)，你可以查询他们的共同字段，不用再每一个地方重复
```GraphQL
{
  search(text: "an") {
    __typename
    ... on Character {
      name
    }
    ... on Human {
      height
    }
    ... on Droid {
      primaryFunction
    }
    ... on Starship {
      name
      length
    }
  }
}
```
请注意在`Starship`中还是需要写`name`，因为`Starship`没有实现`Character`接口

### 输入类型

到目前为止，我们只讨论了将标量值（如枚举或字符串）作为参数传递给字段。但是您也可以轻松地传递复杂的对象。这在突变的情况下特别有价值，您可能希望传入要创建的整个对象。在 GraphQL 模式语言中，输入类型看起来与常规对象类型完全相同，但使用关键字`input`而不是`type`：
```GraphQL
input ReviewInput {
	stars: Int!
	commentary: String
}
```
以下是在突变中使用输入对象类型的方法
```GraphQL
mutation CreateReviewForEpisode($ep: Episode!, $review: ReviewInput!) {
  createReview(episode: $ep, review: $review) {
    stars
    commentary
  }
}
```
请求
```GraphQL
{
  "ep": "JEDI",
  "review": {
    "stars": 5,
    "commentary": "This is a great movie!"
  }
}
```
结果
```GraphQL
{
  "data": {
    "createReview": {
      "stars": 5,
      "commentary": "This is a great movie!"
    }
  }
}
```