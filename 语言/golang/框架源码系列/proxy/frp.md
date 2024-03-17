# frp

深圳电信，在2024年3月初，突然发现深圳电信不提供公网IPv4了（如有需要，可以每月100的费用额外购买），价格过高，不进行考虑。根据相关了解，其也不提供IPv6。但有时又需要访问家里的设备（obsidian、mysql测试库）。

基于以上原因，打算了解内网穿透相关概念。

市面上有多种内网穿透软件，frp、n2n、zerotier、headscale（开源）+tailscale。

其中

- n2n 反馈是 500M宽带，能跑到300M（P2P），评判较为优秀
- zerotier，500M带宽，可能才100M（P2P）

其中 frp 是公司当前主用软件，同时又是go语言，打算基于此开始学习相关内网穿透

[源码](https://github.com/fatedier/frp)，基于acf33db4e4b6c9cf9182d93280299010637b6324 commit版本

## 简介

frp是一款代理工具，它可以无视复杂的网络环境做代理，只需要客户端与服务器能相互连接，即可通过连接服务器来实现代理模式。

他是基于端口形的代理，与上述的内网穿透还是有一定的差别。上述几个内网穿透软件，都是通过创建虚拟网卡实现的互联。



## 源码解析

因为我们主要是为了学习内网穿透（NAT穿透、NAT打洞、P2P），所以主要内容还是看他的xtcp。其余功能简单带过，理解一下他的大致实现方式即停，不深究。

其主要初始化手段是go的[`package init()`](https://go.dev/doc/effective_go#init)，此方式个人不是很建议。看起代码来其实还是比较复杂的。

### 使用库

主要涉及库

| 库名                                               | 功能                                                         |
| -------------------------------------------------- | ------------------------------------------------------------ |
| [cobra](https://github.com/spf13/cobra)            | 一个强大的cli 命令行提示工具，简单理解为类似flag包即可，不过其提示功能做的更加完善与强大 |
| [websockect](https://github.com/gorilla/websocket) | gorilla 的 websocket包，但已经不更新了                       |
| [fatedier/mux](https://github.com/fatedier/golib)  | 作者自有库，用于复用网络连接，根据数据的前几个字节将网络分发给不同的监听器。 |
| [fatedier/msg](https://github.com/fatedier/golib)  | 作者自有库，传递消息的控制实现                               |

#### cobra

类似官方提供的flag包，Execute可以看作为 flag.Parse()。

个人感觉只要定义清晰非常好用。

相较于官方的flag包，他提供了自动补全，自动生成手册页（`man`），以及在用户输入错误的情况下，自动提供了演示

- Easy subcommand-based CLIs: `app server`, `app fetch`, etc.
- Fully POSIX-compliant flags (including short & long versions)
- Nested subcommands
- Global, local and cascading flags
- Intelligent suggestions (`app srver`... did you mean `app server`?)
- Automatic help generation for commands and flags
- Grouping help for subcommands
- Automatic help flag recognition of `-h`, `--help`, etc.
- Automatically generated shell autocomplete for your application (bash, zsh, fish, powershell)
- Automatically generated man pages for your application
- Command aliases so you can change things without breaking them
- The flexibility to define your own help, usage, etc.
- Optional seamless integration with [viper](https://github.com/spf13/viper) for 12-factor apps



#### mux

当前这个库其实是一个工具包，可能是作者使用偏好罢了，其完整路径如下：github.com/fatedier/golib/net/mux

其作用是：定义了一个复用网络连接的包。它可以监听网络连接，根据数据的前几个字节将网络连接分发给不同的监听器。这样就可以在同一个端口上服务多种协议。例如，你可以在同一个端口上同时监听 HTTP 和 HTTPS 连接。

主要的代码逻辑由以下几个部分组成：

- `NewMux`：初始化一个新的 `Mux` 结构体实例，它将在一个给定的网络监听器上进行操作。
- `Listen`：这是一个扩展功能，用于依据指定的优先级，需要的字节数以及匹配函数在复用的网络监听器上建立监听。在函数内部，新的监听器会被按优先级和需要的字节数排序并加入监听器列表。同时需要提供**匹配函数**。
- `ListenHttp`和`ListenHttps`：这两个函数是用于创建 HTTP 和 HTTPS 的监听器。
- `DefaultListener`：如果没有默认的监听器存在，就创建一个新的监听器，并作为默认监听器返回。
- `Serve`：这个函数开始接受连接，并为每个连接启动一个新的 Go 协程来处理。
- `handleConn`：这个函数逐个检查获得的网络连接，通过调用注册的**匹配函数**来确定是否应该处理该连接。一旦找到匹配项，连接就会被发送给匹配的监听器。如果没有找到匹配项则关闭连接。
- `listener`的`Accept`和`Close`方法分别用于接受新连接和关闭监听器。

一个**匹配函数**的模板

```go
var HttpMatchFunc MatchFunc = func(data []byte) bool {
	if len(data) < int(HttpNeedBytesNum) {
		return false
	}

	_, ok := httpHeadBytes[string(data[:3])]
	return ok
}
```

当需要注册多个时，并使用：

```go
func NewMux(ln net.Listener) (mux *Mux) {
	mux = &Mux{
		ln:  ln,
		lns: make([]*listener, 0),
	}
	return
}

func (mux *Mux) ListenHttp(priority int) net.Listener {
	return mux.Listen(priority, HttpNeedBytesNum, HttpMatchFunc)
}

func (mux *Mux) ListenHttps(priority int) net.Listener {
	return mux.Listen(priority, HttpsNeedBytesNum, HttpsMatchFunc)
}

func main(){
	// ln:= ...
    mu :=     NewMux(ln)
    // 相同端口注册 http 与 https 
    httpListen := mu.ListenHttp(0)
    httpsListen := mu.ListenHttps(1)
    // 运行接收
    go func (){
        for {
            conn, err := httpListen.Accept()
            // do something
        }
    }()
    go func (){
        for {
            conn, err := httpsListen.Accept()
            // do something
        }
    }()
}
```



### frps

#### 结构体介绍

##### Service

https://github.com/fatedier/frp/blob/acf33db4e4b6c9cf9182d93280299010637b6324/server/service.go#L73

当前结构体算是有状态结构体，用于保存所有链接，同时监听webserver提供外部访问。所有操作都是基于此开展（监听端口/新增链接）





##### Control

https://github.com/fatedier/frp/blob/acf33db4e4b6c9cf9182d93280299010637b6324/server/control.go#L97C2-L151C2

当前看到，处理客户端链接时，使用此结构体

在最开始建立链接后，通过`Service.RegisterControl` 创建`control`对象对链接进行管理。

发送数据与接收数据`msgDispatcher` 

| 参数名        | 解释                           |
| ------------- | ------------------------------ |
| msgDispatcher | 处理链接(conn)的消息传递与接收 |
| runID         | 客户端注册ID                   |





##### Dispatcher

封装了对链接的发送、输出操作，

| 参数        | 解析                                                         |
| ----------- | ------------------------------------------------------------ |
| sendCh      | Writer操作，写操作只需要通过channel传递即可                  |
| msgHandlers | Read 操作 消息处理，根据从conn读到的消息类型，决定需要使用什么方法解析<br/>比如内部使用的ping/pong用于包活，该类型已经封装好了，该解析就不需要**使用者**处理。 |
| rw          | 就是conn，具体的链接                                         |

```go
type Dispatcher struct {
	rw io.ReadWriter

	sendCh         chan Message
	doneCh         chan struct{}
	msgHandlers    map[reflect.Type]func(Message)
	defaultHandler func(Message)
}
```



##### msgCtl

封装了对消息的解析，封包处理。

后续发送消息时，只需要把具体消息Pack后发出，不需要了解或处理具体需要Pack什么。

后继解析消息时，也只需要把具体消息Unpack后丢入处理，不需要了解具体时怎么Unpack的。

```go
type MsgCtl struct {
	typeMap     map[byte]reflect.Type
	typeByteMap map[reflect.Type]byte

	maxMsgLength int64
}

// 注册消息类型，根据typeByte可查找到msg.Type，
// 也可以根据 msg.Type 查询到typeByte的定义
// typeByte应该为消息头的第一个字节，根据该字节，决定使用什么类型进行解析解析
func (msgCtl *MsgCtl) RegisterMsg(typeByte byte, msg interface{}) {
	msgCtl.typeMap[typeByte] = reflect.TypeOf(msg)
	msgCtl.typeByteMap[reflect.TypeOf(msg)] = typeByte
}

func (msgCtl *MsgCtl) UnPack(typeByte byte, buffer []byte) (msg Message, err error) {}
func (msgCtl *MsgCtl) Pack(msg Message) ([]byte, error) {}
```



#### 配置文件

[详细配置文件](https://github.com/fatedier/frp/blob/dev/conf/frps_full_example.toml)



#### 流程

frp 的 server端，看当前服务端的主要原因是想稍微了解一一下其代理是如何实现的。学习后可以更加深刻的了解代理软件。

##### 初始化

我们从main方法开始看

1. 其代码非常简单，只有两行`frp/cmd/frps/main.go`

   ```go
   func main() {
   	crypto.DefaultSalt = "frp"
   	Execute()
   }
   ```

2. 其主要初始化流程其实需要查看`frp/cmd/frps/root.go`

   - 当前文件用于注册参数，然后由main方法调用`root.go`的Execute执行

     ```go
     func Execute() {
     	rootCmd.SetGlobalNormalizationFunc(config.WordSepNormalizeFunc)
     	if err := rootCmd.Execute(); err != nil {
     		os.Exit(1)
     	}
     }
     ```

   - Excute将会调用cobra的cli工具，解析`root.go`注册的参数，解析后执行其结构体的Run方法

     ```go
     var rootCmd = &cobra.Command{
     	Use:   "frps",
     	Short: "frps is the server of frp (https://github.com/fatedier/frp)",
     	RunE: func(cmd *cobra.Command, args []string) error {
     		// ... show version command ... 
     		// ... init variable ...
     		if cfgFile != "" {
     			svrCfg, isLegacyFormat, err = config.LoadServerConfig(cfgFile, strictConfigMode)
     			if err != nil {
     				fmt.Println(err)
     				os.Exit(1)
     			}
     			if isLegacyFormat {
     				fmt.Printf("WARNING: ini format is deprecated and the support will be removed in the future, " +
     					"please use yaml/json/toml format instead!\n")
     			}
     		} else {
     			serverCfg.Complete()
     			svrCfg = &serverCfg
     		}
     		// ... verify config ... 
     		
             // start proxy server 
     		if err := runServer(svrCfg); err != nil {
     			fmt.Println(err)
     			os.Exit(1)
     		}
     		return nil
     	},
     }
     ```

   - 加载配置后调用 `runServer(svraCfg)`进行初始化。

3. 启动服务

   ```go
   func runServer(cfg *v1.ServerConfig) (err error) {
   	// ... log and cfg checked ... 
   	svr, err := server.NewService(cfg)
   	if err != nil {
   		return err
   	}
   	log.Infof("frps started successfully")
   	svr.Run(context.Background())
   	return
   }
   ```

   - `NewService` 初始化了Service的结构体，根据其配置文件是否存在，决定是否初始化（会直接生成相应`Listen`，或说socket，但此时只生成，不处理链接）

     ```go
     // BindAddr 是服务端与客户端互联的端口，同时Service结构体上也标记了：Accept connections from client，所以我们知道了这是客户端的监听socket。
     // Listen for accepting connections from client.
     address := net.JoinHostPort(cfg.BindAddr, strconv.Itoa(cfg.BindPort))
     ln, err := net.Listen("tcp", address)
     if err != nil {
         return nil, fmt.Errorf("create server listener error, %v", err)
     }
     
     svr.muxer = mux.NewMux(ln)
     svr.muxer.SetKeepAlive(time.Duration(cfg.Transport.TCPKeepAlive) * time.Second)
     go func() {
         _ = svr.muxer.Serve()
     }()
     ln = svr.muxer.DefaultListener()
     
     svr.listener = ln
     ```

   - `svr.Run(context.Background())`，启动并且监听

至此，服务监听流程已实现完毕



##### client 连接流程

在初始化流程中，已经开启了监听，并将相关信息保存到了Service结构体中。

1. 在 `svr.Run(context.Background())`中，其执行了这么一句

   ```go
   svr.HandleListener(svr.listener, false)
   ```

   - 我们已经知道了`svr.listener`就是客户端连接的socket，所以此处是处理客户端相关的操

2. `svr.HandleListener` 处理了tls与tcp mux，但我们默认没有配置tls与tcp mux，所以也是掠过，直接执行`svr.handleConnection(ctx, frpConn, internal)` 方法

3. 其[handleConnection](https://github.com/fatedier/frp/blob/acf33db4e4b6c9cf9182d93280299010637b6324/server/service.go#L411C1-L472C2)是对接入的连接进行处理。

   1. 读取数据

      ```go
      // 根据上述（结构体介绍部分） msgCtl 的实现
      // 我们是可以通过链接中的某一个Byte知道他具体是什么结构的，这样我们就知道了我们需要解析成什么数据结构。
      // 在当前 ReadMsg 中，具体协议如下（删除`+`号）： typeByte+数据总长度+具体消息
      if rawMsg, err = msg.ReadMsg(conn); err != nil {
          log.Tracef("Failed to read message: %v", err)
          conn.Close()
          return
      }
      ```

   2. 根据消息类型，判断当前应该执行哪些内容 [代码](https://github.com/fatedier/frp/blob/acf33db4e4b6c9cf9182d93280299010637b6324/server/service.go#L427C1-L471C3) 

      - 当前为客户端，所以会访问msg.Login操作，正常流程下会走到 svr.RegisterControl 位置

      ```go
      switch m := rawMsg.(type) {
      	case *msg.Login:
      		// server plugin hook
      		content := &plugin.LoginContent{
      			Login:         *m,
      			ClientAddress: conn.RemoteAddr().String(),
      		}
      		retContent, err := svr.pluginManager.Login(content)
      		if err == nil {
      			m = &retContent.Login
      			err = svr.RegisterControl(conn, m, internal)
      		}
      		// ... 登陆失败错误处理 ... 
      	case *msg.NewWorkConn:
      		if err := svr.RegisterWorkConn(conn, m); err != nil {
      			conn.Close()
      		}
      	case *msg.NewVisitorConn:
          	
      		if err = svr.RegisterVisitorConn(conn, m); err != nil {
      			xl.Warnf("register visitor conn error: %v", err)
      			_ = msg.WriteMsg(conn, &msg.NewVisitorConnResp{
      				ProxyName: m.ProxyName,
      				Error:     util.GenerateResponseErrorString("register visitor conn error", err, lo.FromPtr(svr.cfg.DetailedErrorsToClient)),
      			})
      			conn.Close()
      		} else {
      			_ = msg.WriteMsg(conn, &msg.NewVisitorConnResp{
      				ProxyName: m.ProxyName,
      				Error:     "",
      			})
      		}
      	default:
      		log.Warnf("Error message type for the new connection [%s]", conn.RemoteAddr().String())
      		conn.Close()
      	}
      ```

4. 登陆成功，将当前连接注册到Service中，并生成注册相应的ctlManager [代码](https://github.com/fatedier/frp/blob/acf33db4e4b6c9cf9182d93280299010637b6324/server/service.go#L558C1-L607C2)

   1. 判断RunID 是否存在，不存在则生成

   2. 创建Control，用于管理链接部分 [代码](https://github.com/fatedier/frp/blob/acf33db4e4b6c9cf9182d93280299010637b6324/server/control.go#L154)

      1. 将lastPing设置为当前

      2. 初始化Dispatcher（读取发送管理）

      3. 注册消息处理（表当前链接所接收的所有消息结构体类型，此处单独讲

         ```go
         ctl.msgDispatcher.RegisterHandler(&msg.NewProxy{}, ctl.handleNewProxy) // 代理
         ctl.msgDispatcher.RegisterHandler(&msg.Ping{}, ctl.handlePing) // ping
         ctl.msgDispatcher.RegisterHandler(&msg.NatHoleVisitor{}, msg.AsyncHandler(ctl.handleNatHoleVisitor)) // NAT 访问者
         ctl.msgDispatcher.RegisterHandler(&msg.NatHoleClient{}, msg.AsyncHandler(ctl.handleNatHoleClient)) // NAT 客户端
         ctl.msgDispatcher.RegisterHandler(&msg.NatHoleReport{}, msg.AsyncHandler(ctl.handleNatHoleReport)) // 
         ctl.msgDispatcher.RegisterHandler(&msg.CloseProxy{}, ctl.handleCloseProxy) // 关闭代理
         ```

         

   3. 写入ControlManager，根据RunID分配具体链接。

      ```go
      type ControlManager struct {
      	// controls indexed by run id
      	ctlsByRunID map[string]*Control
      
      	mu sync.RWMutex
      }
      ```

   4. Control开始工作

      - 心跳
      - 读取写入信息

   至此，客户端链接结束



##### 消息处理能力

###### proxy

###### ping

###### NatHoleVisitor

###### NatHoleClient

###### NatHoleReport

###### CloseProxy