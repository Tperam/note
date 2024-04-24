# tailscale

tailscale 在23年开始就火起来了

刚好最近在看内网穿透，打算连此部分一起看了

分为几个部分：

- 最终总结（后写）
  - 主要写关键逻辑等。
- 代码流程
- 代码层级

客户端：[tailscale](https://github.com/tailscale/tailscale/tree/ec87e219ae8828f74448c74a7026016a8b037a19)

服务端：[headscale](https://github.com/juanfont/headscale/tree/8a8e25a8d1e6bc5fa27b7f72f99bbf24b290e0a6)

中转服务器（其实就是tailscale的cmd/derper）：[derper](https://github.com/tailscale/tailscale/tree/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/derper)

官方只开源了tailscale的客户端代码，也只开源了tailscale的核心代码，没有开源UI部分。在我们仅了解学习的情况下，我们不需要考虑UI部分。

服务端我们读 headscale，这个是社区贡献，不过据说发起人也是原先tailscale的开发者。

同事反馈，tailscale的技术博客写的不错，把打洞/stun那些操作写的都很清楚。可以去翻阅一下。（下面的是我随便找的，还没看具体的）

> https://tailscale.com/blog/how-tailscale-works
>
> https://tailscale.com/blog/how-nat-traversal-works



> This repository contains the majority of Tailscale's open source code. Notably, it includes the `tailscaled` daemon and the `tailscale` CLI tool. The `tailscaled` daemon runs on Linux, Windows, [macOS](https://tailscale.com/kb/1065/macos-variants/), and to varying degrees on FreeBSD and OpenBSD. The Tailscale iOS and Android apps use this repo's code, but this repo doesn't contain the mobile GUI code.



## 使用流程

学习之前肯定要先用用，看看支持什么功能，看看他文档中对那个功能的定义是什么。

我们当前基于headscale+tailscale进行使用。

> 参考文章：
>
> [Headscale 搭建 P2P 内网穿透 - Kovacs](https://mritd.com/2022/10/19/use-headscale-to-build-a-p2p-network/#三、搭建-Headscale-服务端)
>
> [Tailscale 基础教程：Headscale 的部署方法和使用教程 – 云原生实验室 - Kubernetes|Docker|Istio|Envoy|Hugo|Golang|云原生](https://icloudnative.io/posts/how-to-set-up-or-migrate-headscale/)
>
> [Tailscale 基础教程：部署私有 DERP 中继服务器 – 云原生实验室 - Kubernetes|Docker|Istio|Envoy|Hugo|Golang|云原生](https://icloudnative.io/posts/custom-derp-servers/)
>
> [Tailscale/Headscale ACL 使用教程 – 云原生实验室 - Kubernetes|Docker|Istio|Envoy|Hugo|Golang|云原生](https://icloudnative.io/posts/tailscale-acls/#tailscale-acl-语法)
>
> 官方文档：
>
> [How-to Guides · Tailscale](https://tailscale.com/kb/guides/)
>
> https://headscale.net/

其实用起来不难，简单来说就是

- 服务端部署headscale，并创建个用户。
- 本地部署tailscale并链接入headscale即可。

其代理模式是通过创建虚拟网卡+虚拟路由实现的（不像frp或shadowsocks，是通过代理端口进行转发的）



tailscale 加入 headscale 操作有几种方式，我比较喜欢preauthkeys，直接一条命令加入即可，不需要额外的操作。

- tailscale 直接加入headscale

  1. tailscale链接到headscale

     ```shell
     tailscale login --login-server http://192.168.2.114:8309
     ```

  2. tailscale本地（浏览器）会获取到一个token，以及完整的headscale命令

  3. headscale 节点注册（输入客户端获取到的命令

     ```shell
     headscale nodes register --user USERNAME --key nodekey:******
     ```

  4. 完成链接，此时 headscale就有

- tailscale 使用 preauthkeys 加入 headscale

  ```go
  tailscale up --login-server https://headscale.balabal.com --auth-key 9a06067406b9c553683c354eb9d24d4ee40d4127b13941fc
  ```



此时，就可以在看到tailscale启动起来了，并生成了虚拟网卡。





------

### 高级功能

#### 子路由

[文档：设置子路由](https://tailscale.com/kb/1019/subnets#step-2-connect-to-tailscale-as-a-subnet-router)

```shell
tailscale up --advertise-routes=192.168.0.0/24,192.168.1.0/24
```

这个功能很有意思，它可以实现使用tailscale某个客户端的子网

例如你现在有三个不同的内网，但是你想在B内网访问到A内网的其他上设备。就可以使用上述功能实现。

后续你的tailscale将在B内网的机器上建立一条规则，访问192.168.0.0/24的网络时，走tailscale到A内网机器上，再由A内网机器转发（具体没操作过，但看文档是这个意思）

以及支持一些ACL的访问规则。此规则是用于控制访问的，本次看代码可能会掠过该部分。

他也支持ipv4转ipv6

## 最终总结



## 代码流程

我们主要看几个目标

- P2P是如何实现的
- derper（中转）是如何实现的
- 创建虚拟网卡，并监听是如何实现的
- 子路由功能是如何实现的
- 与服务器的交互

本次我们目标比较明确，直接奔着上述目标去看

> PS：
>
> 去年7月的headscale版本（0.22.3）其实不支持自定义IP的，修改IP只能通过修改他的数据库（sqlite）来实现。
>
> 而且不同用户共享同一个IP段的，不清楚是我设置问题还是什么原因，也有可能是暂时不支持。

### 库

我们先从CMD看起，他提供了多个客户端（项目工程协定，通常cmd是可编译代码，直接编译对应文件夹就可以得到二进制程序）

根据[README](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/README.md?plain=1#L9-L11)提到的，其核心部分其实是tailscale与tailscaled，后续在看个derper的逻辑即可。

### tailscale

| 使用库                                       | 描述                                                         |
| -------------------------------------------- | ------------------------------------------------------------ |
| [ffcli](github.com/peterbourgon/ff/v3/ffcli) | 与cobra类似的一个命令行参数解析库，不过感觉不如cobra，其描述为轻量级的cli，直观高效。 |
|                                              |                                                              |
|                                              |                                                              |

[入口代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/tailscale.go)

逻辑很简单，就是os.Args[1:] 获取传入的参数，丢给`cli.Run`方法进行解析

`cli.Run` 就是对传入参数进行解析，后通过`ffcli`库解析，拆分成多个[子命令](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/cli.go#L109-L135) 

子命令列表

```go
Subcommands: []*ffcli.Command{
    upCmd, // 启动，关注
    downCmd, // 关闭
    setCmd,
    loginCmd, // 登录命令，关注
    logoutCmd, // 登出命令
    switchCmd,
    configureCmd,
    netcheckCmd,
    ipCmd, 
    statusCmd,
    pingCmd, 
    ncCmd,
    sshCmd,
    funnelCmd(),
    serveCmd(),
    versionCmd,
    webCmd,
    fileCmd,
    bugReportCmd,
    certCmd,
    netlockCmd,
    licensesCmd,
    exitNodeCmd,
    updateCmd,
    whoisCmd,
},
```

我们主要关注几个

- upCmd
  - [loginCmd](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/login.go#L15-L31) 也是使用此底层命令（具体为runUp
  - 创建虚拟网卡，登录
- downCmd
  - 关闭tailscale，关闭网卡
- statusCmd
  - 输出当前tailscale状态，可以看到IP信息，对端客户端，以及如果建立了链接，其是中转还是打洞。

此处我们先看upCmd。

其就是调用了[`runUp`](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/up.go#L391-L643)（在login也是调用此方法）

此处tailscaled也被命名为守护进程（个人定义，方便称呼）（d=daemon）

1. 检查本地tailscaled状态
   - 其实就是往本地的tailscaled发送一个HTTP请求
     - GET /localapi/v0/status 
       - 直接通过sock发送请求，"local-tailscaled.sock"
     - 守护进程返回[Status](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnstate/ipnstate.go#L31-L84)
2. 过滤设备：[群晖不支持一些操作](https://github.com/tailscale/tailscale/issues/1995)
3. 校验配置文件，并隐藏变量域 [prefsFromUpArgs](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/up.go#L228-L311)
4. 从守护进程获取[Prefs](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/prefs.go#L51-L238)
   - GET /localapi/v0/prefs
5. 如果是up命令，则将守护进程的ProfileName覆盖当前客户端参数的ProfileName.
6. 解析配置文件 ，分出具体的情况[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/up.go#L313-L379)
   - 是否只是SimpleUp?
   - 是否只改变不需要重启生效的参数JustEditMP？
7. 如果是justEditMP，则直接调用客户端，修改配置。[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/up.go#L472-L476)
   - PATCH /localapi/v0/prefs
8. 挂了个[`WatchIPNBus`](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/client/tailscale/localclient.go#L1373-L1404)，暂不知其意
   - GET /localapi/v0/watch-ipn-bus?mask=0
9. 中间跳过一段，暂时没看懂。[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/up.go#L503-L572)
   - 与WatchIPNBus相关，看着是什么登录处理？
   - 可能是把客户端的一些up操作改为了流程式的实现？
     - 比如，登录可能分为几步，但当前只完成了第一步，还需要等待第二步。
     - 此处可能就封装了一个能.Next().Next()的Iterator模式的调用？直到登录成功？
   - 调用了 startLoginInteractive
     - POST /localapi/v0/login-interactive
10. 判断是否是simpleUp
    - 如果是，则修改一些配置。[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/up.go#L577-L585)
    - 如果不是，则从获取authKey开始[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscale/cli/up.go#L587-L607)
      - 调用start
        - POST /localapi/v0/start
        - 传入启动参数以及Authkey
11. 等待服务改变为running
12. 结束登录

上述就是upCmd的全过程，其中结束时我们可以看到这么一段表述

```go
// This whole 'up' mechanism is too complicated and results in
// hairy stuff like this select. We're ultimately waiting for
// 'running' to be done, but even in the case where
// it succeeds, other parts may shut down concurrently so we
// need to prioritize reads from 'running' if it's
// readable; its send does happen before the pump mechanism
// shuts down. (Issue 2333)
```

#### 简述

我们也可以看到，其up命令的实现是蛮复杂的：

1. 首先判断你守护进程状态，如果你开启着，则将守护进程的配置拉下来，与当前运行的命令进行对比。
   1. 如果开启了，并且配置一致，或仅产生一些简单变更参数（在该参数不需要重启的情况下），将直接更新参数
   2. 如果没有开启，则判断是否是简单启动
   3. 如果不是，则需要处理登录操作逻辑有没有登录。
      - 由于登录蛮复杂的，所以此处实现也蛮复杂。	
      - 它支持客户端在没有密钥的情况下申请登录到服务端中，但需服务端批准，所以此处实现为了状态模式，不同状态此处也会有不同的处理。
2. 等待操作结束，告知running

-----



### tailscaled

作为tailscale客户端部分的服务器（或是守护进程）。所有操作其实都是在tailscaled部分进行，tailscale仅是一个命令行的客户端，便于用户登录操作，不需要用户去记住请求以及交互流程等。如果提供到服务级别，可能仅需要开个Web服务器，做一个web服务的封装即可。（有桌面gui应用更佳）

在上述代码中，我们其实已经看到了，他在up流程中使用了多个API。

1. 查看状态 GET /localapi/v0/status 
2. 获取当前运行的配置文件（或首选项） GET /localapi/v0/prefs
3. 疑似让用户登录的？ GET /localapi/v0/watch-ipn-bus?mask=0
   - POST /localapi/v0/login-interactive
4. 启动的 POST /localapi/v0/start

调用流程就是这样，我们直接从这几个API看起，与上述关联起来。

我们通过全局搜索`/localapi/v0` （因为没搜到`/localapi/v0/status`，所以想尝试删除，看看能不能匹配到前半段部分）搜索到此部分，[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/localapi/localapi.go#L75-L143) 其中注册了许多Handler方法。

我们回溯到源头，其实在tailscaled.go文件中进行的调用[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscaled/tailscaled.go#L487)

调用过程：

1. main.go run

2. 调用 [startIPNServer](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscaled/tailscaled.go#L412)

3. 调用 [srv.Run](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscaled/tailscaled.go#L487)

4. 配置了[hs作为http.Server](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnserver/server.go#L543-L562)，这里主要看[Handler](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnserver/server.go#L544)参数

5. 其传入的[serveHTTP](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnserver/server.go#L149-L224)，判断了URL的前缀。我们所关注的前缀刚好是`/localapi/`，所以我们看此处的lah.ServeHTTP

   ```go
   if strings.HasPrefix(r.URL.Path, "/localapi/") {
       lah := localapi.NewHandler(lb, s.logf, s.netMon, s.backendLogID)
       lah.PermitRead, lah.PermitWrite = s.localAPIPermissions(ci)
       lah.PermitCert = s.connCanFetchCerts(ci)
       lah.ConnIdentity = ci
       lah.ServeHTTP(w, r)
       return
   }
   ```

6. [lah.ServeHTTP](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/localapi/localapi.go#L194-L227) 其中调用了[handleForPath](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/localapi/localapi.go#L222)

7. 最终在handleForPath中找到了[handler](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/localapi/localapi.go#L270)这个Map，其指向了最终的每个路径的处理方法。



我这里只好奇两个，一个status，一个start，猜测status用于展露状态，start用于开启代理（此部分应该是tailscaled的核心代码）

#### status

上述初始化咱们暂时就不看了，直接从status状态开始看起实现

```go
func (h *Handler) serveStatus(w http.ResponseWriter, r *http.Request) {
	if !h.PermitRead {
		http.Error(w, "status access denied", http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	var st *ipnstate.Status
	if defBool(r.FormValue("peers"), true) {
		st = h.b.Status()
	} else {
		st = h.b.StatusWithoutPeers()
	}
	e := json.NewEncoder(w)
	e.SetIndent("", "\t")
	e.Encode(st)
}
```

我们最开始调用时并没有传入任何参数，所以这里的值为`""`，`defBool`方法判断peers是否为空，如果为空则使用第二个传入值，所以此处为true。

走 [`h.b.Status()`](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnlocal/local.go#L726-L730) 方法，其调用[`UpdateStatus()`](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnlocal/local.go#L741-L860)方法去读取具体的状态。

可能因为[Status](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnstate/ipnstate.go#L31-L84)传入值比较多，这里使用的是[Builder](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnstate/ipnstate.go#L321-L329)设计模式。

1. 加载状态 [Status](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnstate/ipnstate.go#L31-L84)

   | Name           |                                                              |                                                              |
   | -------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
   | Version        | string                                                       | 版本                                                         |
   | TUN            | bool                                                         |                                                              |
   | BackendState   | string                                                       | 守护进程状态：<br/>"NoState"<br/>"InUseOtherUser"<br/>"NeedsLogin"<br/>"NeedsMachineAuth"<br/>"Stopped"<br/>"Starting"<br/>"Running" |
   | AuthURL        | string                                                       | 验证地址的复制链接（复制到服务端直接执行的）                 |
   | ClientVersion  | [ClientVersion](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/tailcfg/tailcfg.go#L1902-L1932) | 客户端版本信息（最后运行版本，最新版本，紧急安全更新，...)   |
   | Health         | []string                                                     | 版本更新提醒、守护进程错误信息、以及各种警告信息（报错信息也在此列） |
   | CertDomains    | string                                                       | DNS证书                                                      |
   | CurrentTailnet | [TailnetStatus](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnstate/ipnstate.go#L151-L167) | 域名以及DNS服务                                              |

2. 加载私有状态 [ipnstate.PeerStatus](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnstate/ipnstate.go#L208-L309)

   | Name          |                                                              |              |
   | ------------- | ------------------------------------------------------------ | ------------ |
   | OS            | string                                                       | 系统名       |
   | Online        | bool                                                         | 在线状态     |
   | HostName      | string                                                       |              |
   | DNSName       | string                                                       |              |
   | UserID        | ID (int64)                                                   | 用户ID       |
   | PublicKey     | [NodePublic](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/types/key/node.go#L154-L157) | 公钥         |
   | PrimaryRoutes | [views.Slice[netip.Prefix]](views.Slice[netip.Prefix])  ([]Prefix) | 私有路由     |
   | AllowedIPs    | [views.Slice[netip.Prefix]](views.Slice[netip.Prefix])  ([]Prefix) | 允许访问的IP |
   | Expired       | bool                                                         | 是否过期     |
   | KeyExpiry     | time.Time                                                    | 密钥过期时间 |

3. 读取其他节点状态（同服务器下或称同ACL规则内？）

   1. 读取用户配置 [UserProfile](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/types/netmap/netmap.go#L79) 
   2. 遍历所有节点
      1. 最后在线时间
      2. tailscale的ip列表
      3. 在线信息
      4. 以及加载该节点的私有状态
      5. 将当前节点信息添加到Builder中

4. 完成Status读取



#### prefs

略，用于配置文件的

#### watch-ipn-bus

略，后续可补看

#### login-interactive

略

#### start

路由[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/localapi/localapi.go#L121)在此

我们往里走，看具体的请求处理

先从http的Body中读取了[Options](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/backend.go#L232-L251)结构体

该结构体如下，与[Prefs](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/prefs.go#L50-L238)结构体

```go
type Options struct {
	// FrontendLogID is the public logtail id used by the frontend.
	FrontendLogID string
	// LegacyMigrationPrefs are used to migrate preferences from the
	// frontend to the backend.
	// If non-nil, they are imported as a new profile.
	LegacyMigrationPrefs *Prefs `json:"Prefs"`
	// UpdatePrefs, if provided, overrides Options.LegacyMigrationPrefs
	// *and* the Prefs already stored in the backend state, *except* for
	// the Persist member. If you just want to provide prefs, this is
	// probably what you want.
	//
	// TODO(apenwarr): Rename this to Prefs, and possibly move Prefs.Persist
	//   elsewhere entirely (as it always should have been). Or, move the
	//   fancy state migration stuff out of Start().
	UpdatePrefs *Prefs
	// AuthKey is an optional node auth key used to authorize a
	// new node key without user interaction.
	AuthKey string
}

```

再将请求传给[LocalBackend.Start](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/ipnlocal/local.go#L1619-L1870)

Start包揽了所有启动相关的操作，我们针对此进行阅读。



-----

### other: tailscaled 源码阅读其他方式

想了想，直接放弃好像有点可惜，不看到他P2P的实现真的很苦恼，现在有几条路子：

1. 直接debug打断点+tailscale运行看实际流程（要自己搭建各种测试环境）
2. 看Blog有没有对代码的解释和说明，如果没有，那就看看他blog中对P2P实现的描述，假装自己已经读过源码
3. 玩点骚的，根据命名，以及大致行为，猜测其可能的功能
   - 比如我现在就有怀疑对象，他的LocalBackend应该是贯穿全局的结构体，各个地方都会修改它
     - 它里面的netMap可能就是管理节点的
     - peer什么的估计也是相关的





-----

### tailscaled v0.96

> 上面的版本过于复杂了，不看了。看他第一版，估计也实现了相应功能，就是可能有点Bug。
>
> 咱们换到v0.96，最老tag版本的handler方法起看：[handler](https://github.com/tailscale/tailscale/blob/da4e92bf0198115c9c5a02611831aeae67062aba/ipn/localapi/localapi.go#L72-L144)。
>
> 依旧很熟悉的map路由表
>
> 依旧熟悉的ipn.Options + Start操作
>
> 嗯，代码看似简单了点，但好像也没简单到哪里去...。
>
> 好，此处二次放弃！



好的，突然发现我原先down了源码忘记换分支了，跟着这个思路再走一遍看看。



#### wireguard

ok 我们现在看了个wireguard的逻辑（暂时没测试，知道了以下流程）

- wireguard 配置
  - 需要配置一个私钥与公钥（有命令直接生成）
  - 在两台机器上互相配置对方的公钥
  - 配置allowed-ips
  - 配置endpoint（对方机器的代理点？）
  - 两台机器上自己配置自己的IP
- wireguard会本地生成一个虚拟网卡
  - 本地会有个服务将所有发往虚拟网卡的包都拦截下来
  - 此处根据对方的pubkey进行加密
  - 并使用UDP往配置的endpoint中发送包
- 对方监听endpoint，收到包后使用当前的privatekey
  - 若解包成功，则根据allowed ip 判断是否需要处理该包
  - 若匹配，则直接发给源包的dst.ip与dst.port
  - 若不匹配，则丢弃

当前tailscaled宣称是基于wireguard的。

所以其实tailscale所作的事情就是维护 wireguard 

1. 私钥+密钥 的传输（原先需要用户配置）
2. endpoint的配置
   - 此处就是内网穿透的核心了（此处都是tailscale所需要做的）
   - 需要通过一系列的打洞操作，确定双方客户端最终暴露在公网的endpoint
   - 测试通过后，再来wireguard中固定下来
3. allowed ip 的配置

所以我们只需要看tailscale的上述操作，并且其中1，多半是通过服务器转发得到的，我们不需要特别关注。3又仅是服务器的配置下发实现。

所以我们主要关注的还是endpoint的获取，这里应该就是tailscale的实际操作。

-----

定义：

- 新版本为 [版本](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19)

#### tailscale

v0.96的版本与之前看的[版本](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19)差距比较大，我们从[tailscale.go](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/cmd/tailscale/tailscale.go)快速看起。

从这里可以看到，当前已经有up命令了。我们直接看他的执行

```go
upCmd := &ffcli.Command{
		Name:       "up",
		ShortUsage: "up [flags]",
		ShortHelp:  "Connect to your Tailscale network",

		LongHelp: strings.TrimSpace(`
"tailscale up" connects this machine to your Tailscale network,
triggering authentication if necessary.

The flags passed to this command set tailscaled options that are
specific to this machine, such as whether to advertise some routes to
other nodes in the Tailscale network. If you don't specify any flags,
options are reset to their default.
`),
		FlagSet: upf,
		Exec:    runUp,
	}
```

[runUp](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/cmd/tailscale/tailscale.go#L120-L204)方法

```go
func runUp(ctx context.Context, args []string) error {
	// ... 省略代码...
	c, err := safesocket.Connect(upArgs.socket, 0)
	if err != nil {
		log.Fatalf("safesocket.Connect: %v\n", err)
	}
    // 客户端发信到守护进程
	clientToServer := func(b []byte) {
        // 可能定义了协议头等
		ipn.WriteMsg(c, b)
	}
	// ... 优雅处理错误省略 ... 
	bc := ipn.NewBackendClient(log.Printf, clientToServer)
	bc.SetPrefs(prefs)
	opts := ipn.Options{
		StateKey: globalStateKey,
        // ... opts配置省略 ...
		},
	}
	// We still have to Start right now because it's the only way to
	// set up notifications and whatnot. This causes a bunch of churn
	// every time the CLI touches anything.
	//
	// TODO(danderson): redo the frontend/backend API to assume
	// ephemeral frontends that read/modify/write state, once
	// Windows/Mac state is moved into backend.
	bc.Start(opts)
	pump(ctx, bc, c)

	return nil
}
```

我们可以看到，他在[代码中](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/cmd/tailscale/tailscale.go#L200)直接调用了bc.Start，现在看当时的设计并没有使用http相关，完全使用的是tcp，

其定义了一个Command，用于与服务器沟通，我们bc.Start就是将opts给了Command.Start后，直接发信给服务器。

```go
// ... 
bc.send(Command{Start: &StartArgs{Opts: opts}})
// ...
type Command struct {
	Version string

	// Exactly one of the following must be non-nil.
	Quit                  *NoArgs
	Start                 *StartArgs
	StartLoginInteractive *NoArgs
	Logout                *NoArgs
	SetPrefs              *SetPrefsArgs
	RequestEngineStatus   *NoArgs
	FakeExpireAfter       *FakeExpireAfterArgs
}
```



#### taiscaled

由于调用状态与新版不是很一致（新版http，当前tcp）。说明改了很多地方，我们之前使用的搜索Url方法失效了。但由于有之前看代码的经验，有一定的关键字累积，所以我们瞄准其对应关键字：LocalBackend, peer(wireguard), endpoint(wireguard), 以及netMap。

>  我们在新版本的地方也看到了，其ipnserver就是用来处理从tailscale发送上来的请求，所以我们在main 中看到了 ipnserver.Run，就直接对着他往下找

main方法中调用[ipnserver.Run](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/cmd/tailscaled/tailscaled.go#L87)

1. 其监听了一个启动时传递的socketPath，（若没传递，默认路径`/var/run/tailscale/tailscaled.sock`）
2. 其直接在[这里](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/ipnserver/server.go#L158-L183)做了请求的接收，当tailscale发起请求，则会触发此Accept
3. 这里调用了[pump](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/ipnserver/server.go#L173)，将接收到的请求直接传递进去并处理。
   1. pump里面实现其实非常简单，就是调用ipn.readMsg，将整个消息读出，读到[]byte
   2. 后调用[bs.GotCommandMsg](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/ipnserver/server.go#L71)，将[]byte 传递进去处理（此处实现感觉不如frp一根毛，不够优雅）
   3. GotCommandMsg将消息用json解析后，用if else比对，找到为空的[command](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/message.go#L102-L105)
   4. 最终调到[localbackend.Start](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L125-L311)



我们此时就基于[localbackend.Start](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L125-L311)开始看，看看他究竟做了什么，还是主要关注 peer, endpoint, netmap

```go
func (b *LocalBackend) Start(opts Options) error {
	// ... 参数检查 ...
	hi := controlclient.NewHostinfo()
	hi.BackendLogID = b.backendLogID
	hi.FrontendLogID = opts.FrontendLogID
	// ... 对 LocalBackend 上锁 以及部分参数获取 ... 
	hi.RoutableIPs = append(hi.RoutableIPs, b.prefs.AdvertiseRoutes...)
	// ...各种参数初始化与DERP处理...
    
    // 初始化了一个controlclient
	cli, err := controlclient.New(controlclient.Options{
		Logf:            logger.WithPrefix(b.logf, "control: "),
		Persist:         *persist,
		ServerURL:       b.serverURL,
		Hostinfo:        hi,
		KeepAlive:       true,
		NewDecompressor: b.newDecompressor,
	})
    // ... 

	b.mu.Lock()
	b.c = cli
    // endpoints 
	endpoints := b.endpoints
	b.mu.Unlock()
	
	if endpoints != nil {
		cli.UpdateEndpoints(0, endpoints)
	}

	cli.SetStatusFunc(func(newSt controlclient.Status) {
        // ... 各种参数检查处理检查，当前仅是给StatusFunc赋值，不执行 ...
	})

	b.e.SetStatusCallback(func(s *wgengine.Status, err error) {
        // 错误处理&参数赋值
		b.endpoints = append([]string{}, s.LocalAddrs...)
		b.mu.Unlock()

		if c != nil {
			c.UpdateEndpoints(0, s.LocalAddrs)
		}
		b.stateMachine()

		b.statusLock.Lock()
		b.statusChanged.Broadcast()
		b.statusLock.Unlock()

		b.send(Notify{Engine: &es})
	})
    // ... 
	return nil
}
```

##### endpoint

在上面start中，我们没有找到非常明显的状态转换&&endpoint赋值，仅看到了在[b.e.SetStatusCallback](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L271-L298)中有两行与endpoints相关。一行为直接赋值，另一行则是给cli的endpoints赋值，不是我们直接想要的。

又没头绪了...

###### 溯源 b.e.SetStatusCallback 调用具体位置

既然只有[b.e.SetStatusCallback](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L271-L298)给endpoints进行了赋值，同时我们知道该方法当前仅做注册，估计是用于后续状态切换时的回调操作，我们就一路跟踪，查找到在哪里进行调用的（由于代码比较复杂，全由状态或channel进行传递管理，此处跟踪代码可能不是非常详细准确，此部分不讲述实现逻辑，仅用来记录查找endpoints生成逻辑）：

1. [Engine](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/wgengine.go#L91-L137) 接口

   - > *Engine is the Tailscale WireGuard engine interface.*

2. 查找其具体实现，有[watchdog](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/watchdog.go#L69-L71)与[userspaceEngine](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L424-L428)两个实现

   - watchdog 看起来是一个错误处理或log的wrap层，本身调用了wrap中的具体实现。
   - 那么就剩下[userspaceEngine](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L424-L428)了

3. [userspaceEngine](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L424-L428) 给statusCallback赋值

4. 其被[userspaceEngine.getStatusCallback()](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L430-L434) 传递出去（此处上锁）

5. 在此处[userspaceEngine.RequestStatus](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L533-L565) 进行了处理

   - 简单来说这里定义了一个reqCh，初始化为1，每次调用该请求时都尝试往reqCH中发送一个"信号值"，如果内部有值，则走default，不处理，若没值，则传递进入。（此处感觉实现有点小bug，但是在某些超多并发的情况下将会拦截掉部分请求。
     - 我的建议是，不如尝试使用trylock，trylock失败代表里面正在执行，trylock成功则执行即可。（也可尝试`atomic.CompareAndSwapInt32`）

6. 其先调用了[getStatus](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L437-L532)获取基础状态，后将获取的状态传入最开始的[b.e.SetStatusCallback](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L271-L298)

7. 该getStatus将自己本身的endpoints甩了出去，但此处并没有初始化endpoints，所以我们查看该结构体的endpoints是如何被赋值的

8. 在[newUserspaceEngineAdvanced](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L99-L224)的地方提供了赋值方法[endpointsFn](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L114-L120)被赋值、

9. 其传递给了[magicsockOpts.EndpointsFunc](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L121-L124)参数，后续通过[endpointsFunc](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L151-L156)方法将其返回出去

10. 在[magicsock.Listen](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L196)中被传递给[Conn.epFunc](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L50) 

    - [Conn](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L44-L101) 在描述中是用来路由UDP包，并且管理endpoints列表的，它实现了wireguard/devices的绑定

11. [Conn.epFunc](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L294) 最终在 [Conn.epUpdate](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L236-L297) 中被调用，

    - Conn.epUpdate其描述为单独占用一个goroutine，直到传递进来的context.Context 被关闭，

12. 当前猜测此部分就是获取endpoints的方法，所以从此处开始详细看



###### updateNetInfo

[代码](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L299-L340)

他先在Conn结构体的stunReceiveFunc中存放了个处理STUNPacket的[方法](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L105-L121)，与stun关键字有关，后续可能会用到。此处先记录

后续调用[GetReport](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L123-L345) 用于获取derp信息与公网ipv4与ipv6，我们这里主要看GetReport方法

当前看代码逻辑会尽量省略ipv6部分，因感觉逻辑一致。当前方法是用于获取一个[report.Report](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L28-L40) 结构体，可能目标是用于打洞等相关操作。

1. 调用`c.DERP.STUN4()`，获取一个字符串数组
   - 其默认为 `derp1.tailscale.com:3478`，`derp2.tailscale.com:3478`，`derp3.tailscale.com:3478`，`derp4.tailscale.com:3478`
2. 创建一个ipv4的udp socket，端口随机，命名为[pc4Hair](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L173)
3. 创建一个[startHairCheck](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L180-L185)方法，该方法使用pc4Hair给指定的udp4发包
   - 发c.hairTX
4. 创建一个[add](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L196-L235)方法，接收参数`(server, ipPort string,  d time.Duration)`，看起来像是将映射的公网IP添加到Report返回值中
   - 在ipv4的情况下，且gotEP4为空时，调用startHairCheck（发送udp包检测）
     - 在为空的时候，使用pc4Hair，尝试自己给自己发包（可能是用于探通的），并且将gotEP4赋值。
     - 在不为空的时，比对ipPort与上次的gotEP4。若不一致，则标明 [Report.MappingVariesByDestIP = "true"](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L223)
5. 创建[STUNConn](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L77-L82)接口，看起来是便于处理udp的发包与收包的管理
6. 通过[c.GetSTUNConn4](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L213) 调用到了最开始初始化Conn结构体时，初始化的[new(RebindingUDPConn)](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L190)
   - [RebindingUDPConn](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L1422-L1427) 看注释，表当前结构体的socket可以被重新绑定，可能此地实际实现逻辑就是，先建立一个udp用于打洞，当打洞成功后，以迅雷不及掩耳之势将其切换成wireguard（我对这里实现的猜测，仅猜测）
7. 使用c.GetStunConn4生成一个p.conn链接给pc4赋值
8. 创建[reader](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L265-L287)方法，接收参数`(s *stunner.Stunner, pc STUNConn)`，看起来像是读取Stun服务器的返回值
   - 从传入的 pc STUNConn 中读取数据
   - 并使用传入的 s *stunner.Stunner接收传入的请求 [s.Recevie](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L284)
9. 创建 [&stunner.Stunner](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L291-L297)命名 s4
   - 此处endpoints为，4. 的add方法
   - Send 为 6. && 7. 的 p.conn.WriteTo
   - Server为 1. 所传入的字符串数字（derp1服务器地址）
10. 使用errgroup.Group，开goroutine调用[s4.Run](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L133-L210)（因为还有s6.Run，可同步发出请求，但不是重点，所以上面忽略）
    1. 开始[s4.Run](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L133-L210)
    2. 初始化变量
       1. 创建一个[map[serverStr]sender](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L158)，命名为need，用于处理接收信息
       2. 创建一个 [channel struct{}](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L159)，命名为allDone，用于处理当len(need)==0时，告知父goroutine消息已经接收完毕
    3. 创建[s.onPacket](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L161-L174) 在上面的reader的 [s.Recevie](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L284)中会有调用，
       1. 其就做了一件事儿，使用传入的server，从need map中找到对应的sender
       2. 调用sender.cancel（可能是触发后续的某个回调）
       3. 删除map的 server元素
       4. [s.Endpoint](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L170) 调用上面的add方法，传入server与endpoint
       5. 其判断need map 是否被清空了，若是清空则[close(allDone)](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L171-L173)
    4. 遍历所有s.Servers，并初始化对应的map
    5. 遍历所有的need，并开携程 [s.sendPackets](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L187)
       - [s.sendPackets](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L262-L287) 就是将原先的server转为net.UDPAddr，并调用上面初始化 [&stunner.Stunner](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L291-L297) 传入的Send操作去发信
    6. 等待所有服务器返回响应
    7. 完成s4.Run
11. 等待上述group完成
12. 判断`ret.MappingVariesByDestIP == "false" &&  gotEP4 != ""`
    - （判断条件与add相关，主要是判断ip与Port是否有发生变化，没发生变化则考虑可能是NAT1，可直接打通，下面就可以稍微等待一下[startHairCheck](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L180-L185)发的探测包）
13. 等待`<-c.gotHairSTUN`的探测包，其在reader中的[`c.handleHairSTUN`](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L281-L283)触发，通过比对解析包后的tx是否是c.hairTX，得出请求是否是本机发出
14. 若上述得到返回值则`ret.HairPinning.Set(true)`，否则为`ret.HairPinning.Set(false)`
15. 此处包含[注释](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L338-L342)，大致意思是udp没打通的情况下，是否做测量tcp到DERP服务器的连接时间测试。
16. 返回深度`ret.Clone()`

-------

上述就是updateNetInfo的全流程

其实透过整个流程，我们可以看到几个关键方法，其余都不是很重要

- [add](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L196-L235)：添加获取到的映射IP
- [startHairCheck](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L180-L185)：给自己发包，看看能否收到
- [reader](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L265-L287) 处理服务器返回的包，并以下面两种方式解析，
  - 处理startHairCheck发过来的包
  - 交给 初始化的 [s4 :=&stunner.Stunner](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L291-L297) ，调用[s.Recevie](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L284)处理
- [s.Recevie](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L284)：处理传入的包，判断是否是我们发出的tx
  - 若是则解析出映射的IP+Port，作为endpoint传入[s.onPacket](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L161-L174)处理
  - 若不是则丢弃，不处理。
- [s.onPacket](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L161-L174)：剔除掉need中已完成的server，并调用[add](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/netcheck/netcheck.go#L196-L235) 添加获取到的映射IP
- [s.sendPackets](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/stunner/stunner.go#L262-L287)：给derp*服务器发送STUN包。
  - 其中用于发包的链接为[Conn.pconn](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L190)
  - 其在最开始的[magicsock.Listen](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L158-L227) 中初始化，[具体命令](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L218) 
    - 若无具体配置，其实际链接通常是：`packetConn = net.ListenPacket("udp4", 0)`，也就是一个随机的UDP端口。

------

上述updateNetInfo已经看完了，并且也算是理解了，其在最开始启动时Listen一个随机端口，并通过上面的一系列方法与STUN交互，并确认是否能成功打洞，而得到一个netReport信息。

然后调用[determineEndpoints](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L423-L481) 根据上面返回的 netReport 生成具体的ip+port端口（它将公网IPv4，公网IPv6，内网IPv4，内网IPv6，都生成到了[]string中）

- 若内网IPv4为0.0.0.0，则遍历所有网卡，并将所有网卡添加进去（此处假设某台机子下有多个WAN口，以及若是两个P2P客户端在相同局域网的情况下）

对比当前的endpoints与lastEndpoints是否一致

不一致则调用我们心心念念的[溯源 b.e.SetStatusCallback 调用具体位置](#####溯源 b.e.SetStatusCallback 调用具体位置)方法，更新endpoints，也就是最终调用到了[endpointsFn](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L113-L119)，等待userspaceEngine 调用[Status](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L436-L531)

最终通过[e.getStatusCallback()](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L560-L562)调回[b.e.SetStatusCallback](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L271-L298)设置的方法，实现LocalBackend的Endpoints更新！

-----

上面我们已经知道了endpoint是如何被获取的，并且将endpoint成功存入了LocalBackend

接下来我们需要找如何与对端节点建立链接的。。。

嗯好，寄了。我又找不到想要的了...看来只能暴力点了。

理论上来说，我们现在有了endpoints，这个endpoints会在某种情况发送给远程服务器，然后服务器将此endpoints发送给其他的peer。然后我们这边也会接收到其他的peer的相关信息，（类似：routing && publickey），所以我现在尝试从endpoints入手，

-----

##### direct

阴差阳错下，我找到了 [Client.UpdateEndpoints](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L289) 其也是更新endpoints的方法，刚好也在[b.e.SetStatusCallback](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L271-L298) 内，其更新了[Client.Direct](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/auto.go#L105) 的endpoints，并且根据注释的描述，其很大可能是与服务器沟通的操作

> direct  *Direct *// our interface to the server APIs*

其在更新endpoint的时候比较了是否与之前的endpoint相冲突，若是有，则调用[c.cancelMapSafely](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/auto.go#L201-L235)。我的直觉告诉我，这步很重要，但现在看不懂。先忽略，既然是与服务器沟通，那肯定还有其他API，咱们先看看其他的。

其提供了几个操作

- TryLogout
- WaitLoginURL
- PollNetMap
- SetHostinfo
- SetNetInfo

这几个操作中，看上去比较重要的是 PollNetMap && SetNetInfo。

根据命名猜测，PollNetMap，是用来拉服务端的所有节点的。而SetNetInfo，感觉可能是将自身信息设置上去？

先来尝试阅读一下PollNetMap

###### PollNetMap



运行该方法的名称叫[mapRoutine](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/auto.go#L382-L480)，[调用部分](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/auto.go#L431-L462)如下，传入了一个callback方法，

```go
err := c.direct.PollNetMap(ctx, -1, func(nm *NetworkMap) {
    c.mu.Lock()

    select {
        case <-c.newMapCh:
        c.logf("mapRoutine: new map request during PollNetMap. canceling.\n")
        c.cancelMapLocked()

        // Don't emit this netmap; we're
        // about to request a fresh one.
        c.mu.Unlock()
        return
        default:
        }

    c.synced = true
    c.inPollNetMap = true
    if c.loggedIn {
        c.state = stateSynchronized
    }
    exp := nm.Expiry
    c.expiry = &exp
    stillAuthed := c.loggedIn
    state := c.state

    c.mu.Unlock()

    c.logf("mapRoutine: netmap received: %s\n", state)
    if stillAuthed {
        c.sendStatus("mapRoutine2", nil, "", nm)
    }
})
```

实际方法如下：[代码](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/direct.go#L433-L594)

不出意外的，此处与服务器通信

1. 生成request为：[tailcfg.MapRequest](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/tailcfg/tailcfg.go#L378-L393)

   ```go
   request := tailcfg.MapRequest{
       Version:   4, 
       KeepAlive: c.keepAlive, // 客户端是否需要keepAlive
       NodeKey:   tailcfg.NodeKey(persist.PrivateNodeKey.Public()), // pubKey
       Endpoints: ep, // 上面获取到的endpoints
       Stream:    allowStream,
       Hostinfo:  hostinfo,
   }
   ```

2. 发出HTTP 请求 POST  "$serverURL/machine/$machinePubkey/map"

   - 其中 serverURL 为传入值或默认值https://login.tailscale.com
   - `machinePubkey = persist.PrivateMachineKey.Public().HexString()`

3. 考虑res的body过于庞大，做了个超时动作，没仔细看 [代码](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/direct.go#L488-L512)

4. 读取body

   - 头4字节为body长度，第一次先读长度
   - 第二次读取全部数据。

5. 将body解析到[tailcfg.MapResponse](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/tailcfg/tailcfg.go#L395-L411)中，此处获取到几个重要数据

   - 节点过期时间
   - 本机节点
   - 对端节点列表
   - ACL操作（不重要，不算是本次学习目标）

6. 将resp的数据加载到 [nm := NetworkMap](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L23-L48) 中，此刻我们获得了

   - 本机节点信息
     - 公钥
     - 私钥
     - 节点过期时间
     - 地址
     - 用户
   - 对端节点信息
   - ACL鉴权相关
   - DNS

7. 调用传入的cb，将nm传入

8. 处理一些操作后（还没看懂），调用[c.sendStatus("mapRoutine2", nil, "", nm)](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/auto.go#L513-L556)

   - 不出意外，c.sendStatus又是回调..
   - 其调用了[Client.statusFunc](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/auto.go#L113)，也就是最初的[cli.SetStatusFunc](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L202-L269)方法。
   - 其在做了一堆我看不懂的操作后，将其赋值给[b.netMapCache](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L235) 

9. 结束PollNetMap

上述操作中，其实忽略了一个结构体 [PacketFilter](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L36) 这个结构体看起来可能是后续routing的关键，内部保存了SrcIPs与DstPortsRange，结构体[Match](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/filter/match.go#L47-L50)。

-----

当前我们有了本机的endpoint + 对端节点的endpoint+pubkey，以及IP相关，此时此刻，就可以生成wireguard网卡（或更新），以及一些打洞操作，去访问对端的endpoint。但现在还是不是很清楚是怎么触发打洞操作的。

-------

##### 打洞操作

既然已经知道，它通过一系列操作后会调用到`SetStatusFunc`，并在其中设置`b.netMapCache = newSt.NetMap`，

netMap是[NetworkMap](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L23-L48)类型，其存放了对端节点的信息，我们根据这个信息，来看其对peers的调用操作，通过查找引用，我们可以看到，他在三个方法中被调用，我们分别来看

- [Concise](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L76-L97)
- [UserMap](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L107-L155)
- [_WireGuardConfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L206-L290)

我们深入进去后发现

- [Concise](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L76-L97)，将其使用字符串拼接了起来后返回，外部通常用于比对两个netmap是否相等使用。
  
    > NetworkMap: self: $pubkey auth=$MachineStatus :$port $Address
    >
    > $peer_pubkey $user $endpoints
  
- [UserMap](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L107-L155)，暂未用到，但看大概意思是生成了一个可以通过用户名查找ip的map

- [_WireGuardConfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L206-L290)，既然上述的用户都不是用于链接对端节点，那此处大概率就是用于连接对端节点了。

  - 这里也是将其拼成字符串，不过与WireGuard的配置比较相像：

    > [Interface]
    >
    > PrivateKey = xxxxxx
    >
    > Address = 192.168.0.1 , 100.1.1.1, 123.123.123.123
    >
    > ListenPort = 12345
    >
    > DNS = xxxxx
    >
    > [Peer]
    >
    > PublicKey =  xxxxx
    >
    > Endpoint = 192.168.0.1:12345,123.123.123.123:45573,192.168.88.1:12345
    >
    > AllowedIPs = 10.0.0.1/8
    >
    > [Peer]
    >
    > PublicKey =  xxxxx
    >
    > Endpoint = 192.168.73.1:12345,123.123.123.124:45576,192.168.88.1:12345
    >
    > AllowedIPs = 10.0.0.1/8
    
  - 后将其返回给上层[WGCfg](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L194-L197) 与 [WireGuardConfigOneEndpoint](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L199-L205)，其中[WireGuardConfigOneEndpoint](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L199-L205)未被调用（其描述为只使用一个Endpoint）。



所以我们此处直接从WGCfg开始看，先看他里面具体实现，再看他上层调用



###### 建立WireGuard网卡



我们接着上述内容，代码 [WGCfg](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/netmap.go#L194-L197) 继续向下看

```go
func (nm *NetworkMap) WGCfg(uflags int, dnsOverride []wgcfg.IP) (*wgcfg.Config, error) {
	s := nm._WireGuardConfig(uflags, dnsOverride, true)
	return wgcfg.FromWgQuick(s, "tailscale")
}
```

通过nm._WireGuardConfig，我们已经得到了一个WireGuard的超集配置（string类型）（比原定义的WireGuard要多）

（由于没有找到对应的库链接，考虑可能删库，所以此处直接粘贴代码）

```go
func FromWgQuick(s string, name string) (*Config, error) {
	if !TunnelNameIsValid(name) {
		return nil, &ParseError{"Tunnel name is not valid", name}
	}
	lines := strings.Split(s, "\n")
	parserState := notInASection
	conf := Config{Name: name}
	sawPrivateKey := false
	var peer *Peer
	for _, line := range lines {
		pound := strings.IndexByte(line, '#')
		if pound >= 0 {
			line = line[:pound]
		}
		line = strings.TrimSpace(line)
		lineLower := strings.ToLower(line)
		if len(line) == 0 {
			continue
		}
		if lineLower == "[interface]" {
			conf.maybeAddPeer(peer)
			parserState = inInterfaceSection
			continue
		}
		if lineLower == "[peer]" {
			conf.maybeAddPeer(peer)
			peer = &Peer{}
			parserState = inPeerSection
			continue
		}
		if parserState == notInASection {
			return nil, &ParseError{"Line must occur in a section", line}
		}
		equals := strings.IndexByte(line, '=')
		if equals < 0 {
			return nil, &ParseError{"Invalid config key is missing an equals separator", line}
		}
		key, val := strings.TrimSpace(lineLower[:equals]), strings.TrimSpace(line[equals+1:])
		if len(val) == 0 {
			return nil, &ParseError{"Key must have a value", line}
		}
		if parserState == inInterfaceSection {
			switch key {
			case "privatekey":
				k, err := ParseKey(val)
				if err != nil {
					return nil, err
				}
				conf.PrivateKey = PrivateKey(*k)
				sawPrivateKey = true
			case "listenport":
				p, err := parsePort(val)
				if err != nil {
					return nil, err
				}
				conf.ListenPort = p
			case "mtu":
				m, err := parseMTU(val)
				if err != nil {
					return nil, err
				}
				conf.MTU = m
			case "address":
				addresses, err := splitList(val)
				if err != nil {
					return nil, err
				}
				for _, address := range addresses {
					a, err := ParseCIDR(address)
					if err != nil {
						return nil, err
					}
					conf.Addresses = append(conf.Addresses, *a)
				}
			case "dns":
				addresses, err := splitList(val)
				if err != nil {
					return nil, err
				}
				for _, address := range addresses {
					a := ParseIP(address)
					if a == nil {
						return nil, &ParseError{"Invalid IP address", address}
					}
					conf.DNS = append(conf.DNS, *a)
				}
			default:
				return nil, &ParseError{"Invalid key for [Interface] section", key}
			}
		} else if parserState == inPeerSection {
			switch key {
			case "publickey":
				k, err := ParseKey(val)
				if err != nil {
					return nil, err
				}
				peer.PublicKey = *k
			case "presharedkey":
				k, err := ParseKey(val)
				if err != nil {
					return nil, err
				}
				peer.PresharedKey = SymmetricKey(*k)
			case "allowedips":
				addresses, err := splitList(val)
				if err != nil {
					return nil, err
				}
				for _, address := range addresses {
					a, err := ParseCIDR(address)
					if err != nil {
						return nil, err
					}
					peer.AllowedIPs = append(peer.AllowedIPs, *a)
				}
			case "persistentkeepalive":
				p, err := parsePersistentKeepalive(val)
				if err != nil {
					return nil, err
				}
				peer.PersistentKeepalive = p
			case "endpoint":
				eps, err := parseEndpoints(val)
				if err != nil {
					return nil, err
				}
				peer.Endpoints = eps
			default:
				return nil, &ParseError{"Invalid key for [Peer] section", key}
			}
		}
	}
	conf.maybeAddPeer(peer)

	if !sawPrivateKey {
		return nil, &ParseError{"An interface must have a private key", "[none specified]"}
	}
	for _, p := range conf.Peers {
		if p.PublicKey.IsZero() {
			return nil, &ParseError{"All peers must have public keys", "[none specified]"}
		}
	}

	return &conf, nil
}
```

上述`wgcfg.FromWgQuick(s, "tailscale")` 操作，其实就是将我们生成的配置，转回一个他内部的配置，便于对方使用（这里可以理解为解耦，使用规定的配置与字符串解析减少两个项目的耦合度，此项目为tailscale开发的[wireguard-go](https://github.com/tailscale/wireguard-go/)。

```go
// Config is a wireguard configuration.
type Config struct {
	Name       string
	PrivateKey PrivateKey
	Addresses  []CIDR
	ListenPort uint16
	MTU        uint16
	DNS        []IP
	Peers      []Peer
}
type Peer struct {
	PublicKey           Key
	PresharedKey        SymmetricKey
	AllowedIPs          []CIDR
	Endpoints           []Endpoint
	PersistentKeepalive uint16
}
type Endpoint struct {
	Host string
	Port uint16
}
```

其实际上就是WireGuard网口的一个超集，主要就是endpoints多了个List。（可能也多了DNS，但我们主要关注endpoint）

我们往回找，发现最终实际上是[LocalBackend.authReconfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L593-L649) 调用了生成WireGuard配置的操作，并且具体配置交由[b.e.Reconfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L644)处理

其具体实现为[userspaceEngine.Reconfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L299-L378)，该方法对原先配置进行更新，并且对比新老配置（判断其是否修改过）。

后调用了[e.wgdev.Reconfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L337)，重新配置网卡。

该部分也是由tailscale实现，[wireguard-go](https://github.com/tailscale/wireguard-go/)，当时可能是没有开源，所以没有直接的git引用，此处简单略读一下：

```go
// Reconfig replaces the existing device configuration with cfg.
func (device *Device) Reconfig(cfg *wgcfg.Config) (err error) {
	defer func() {
		if err != nil {
			device.log.Debug.Printf("device.Reconfig: failed: %v", err)
			device.RemoveAllPeers()
		}
	}()

	// Remove any currentt peers not in the new configuration.
	device.peers.RLock()
	oldPeers := make(map[wgcfg.Key]bool)
	for k := range device.peers.keyMap {
		oldPeers[k] = true
	}
	device.peers.RUnlock()
	for _, p := range cfg.Peers {
		delete(oldPeers, p.PublicKey)
	}
	for k := range oldPeers {
		device.log.Debug.Printf("device.Reconfig: removing old peer %s", k.ShortString())
		device.RemovePeer(k)
	}

	device.staticIdentity.Lock()
	curPrivKey := device.staticIdentity.privateKey
	device.staticIdentity.Unlock()

	if !curPrivKey.Equal(cfg.PrivateKey) {
		device.log.Debug.Println("device.Reconfig: resetting private key")
		if err := device.SetPrivateKey(cfg.PrivateKey); err != nil {
			return err
		}
	}

	device.net.Lock()
	device.net.port = cfg.ListenPort
	device.net.Unlock()

	if err := device.BindUpdate(); err != nil {
		return ErrPortInUse
	}

	// TODO(crawshaw): UAPI supports an fwmark field

	newKeepalivePeers := make(map[wgcfg.Key]*Peer)
	for _, p := range cfg.Peers {
		peer := device.LookupPeer(p.PublicKey)
		if peer == nil {
			device.log.Debug.Printf("device.Reconfig: new peer %s", p.PublicKey.ShortString())
			peer, err = device.NewPeer(p.PublicKey)
			if err != nil {
				return err
			}
			if p.PersistentKeepalive != 0 && device.isUp.Get() {
				newKeepalivePeers[p.PublicKey] = peer
			}
		}

		if !p.PresharedKey.IsZero() {
			peer.handshake.mutex.Lock()
			peer.handshake.presharedKey = p.PresharedKey
			peer.handshake.mutex.Unlock()

			device.log.Debug.Printf("device.Reconfig: setting preshared key for peer %s", p.PublicKey.ShortString())
		}

		peer.Lock()
		peer.persistentKeepaliveInterval = p.PersistentKeepalive
		if len(p.Endpoints) > 0 && (peer.endpoint == nil || !endpointsEqual(p.Endpoints, peer.endpoint.Addrs())) {
			str := p.Endpoints[0].String()
			for _, cfgEp := range p.Endpoints[1:] {
				str += "," + cfgEp.String()
			}
			ep, err := device.createEndpoint(p.PublicKey, str)
			if err != nil {
				peer.Unlock()
				return err
			}
			peer.endpoint = ep

			// TODO(crawshaw): whether or not a new keepalive is necessary
			// on changing the endpoint depends on the semantics of the
			// CreateEndpoint func, which is not properly defined. Define it.
			if p.PersistentKeepalive != 0 && device.isUp.Get() {
				newKeepalivePeers[p.PublicKey] = peer

				// Make sure the new handshake will get fired.
				peer.handshake.mutex.Lock()
				peer.handshake.lastSentHandshake = time.Now().Add(-RekeyTimeout)
				peer.handshake.mutex.Unlock()
			}
		}
		peer.Unlock()

		device.allowedips.RemoveByPeer(peer)
		for _, allowedIP := range p.AllowedIPs {
			ones := uint(allowedIP.Mask)
			ip := allowedIP.IP.IP()
			if allowedIP.IP.Is4() {
				ip = ip.To4()
			}
			device.allowedips.Insert(ip, ones, peer)
		}
	}

	// Send immediate keepalive if we're turning it on and before it wasn't on.
	for k, peer := range newKeepalivePeers {
		device.log.Debug.Printf("device.Reconfig: sending keepalive to peer %s", k.ShortString())
		peer.SendKeepalive()
	}

	return nil
}
```

- 其占用了最初创建并且探测的端口 `device.net.port = cfg.ListenPort`，并尝试开启监听
- 其创建了`map[wgcfg.Key]*Peer`，用于保存节点相关信息，其中包括对端节点的endpoints

此处的endpoints作为重点排查，通过溯源发现，其直接就做调用了`err := peer.device.net.bind.Send(buffer, peer.endpoint)`

其具体实现为：[Conn.Send](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L597-L640)

- 简单来说，就是判断conn.Endpoint是什么类型的，若是单一地址，则直接发包并返回
- 若是多地址，则遍历全部地址，并都发送

所以此处并没有相对应的"打洞"操作，当前流程看下来，若是没有遗漏，则应该只支持NAT1打洞。











-----



Device结构体如下，其部分操作其实都在[newUserspaceEngineAdvanced](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L143-L177)下初始化

```go
type Device struct {
	isUp           AtomicBool // device is (going) up
	isClosed       AtomicBool // device is closed? (acting as guard)
	log            *Logger
	handshakeDone  func(peerKey wgcfg.Key, allowedIPs []net.IPNet)
	skipBindUpdate bool
	createBind     func(uport uint16, device *Device) (conn.Bind, uint16, error)
	createEndpoint func(key [32]byte, s string) (conn.Endpoint, error)

	filterLock sync.Mutex
	filterIn   func(b []byte) FilterResult
	filterOut  func(b []byte) FilterResult

	// synchronized resources (locks acquired in order)

	state struct {
		starting sync.WaitGroup
		stopping sync.WaitGroup
		sync.Mutex
		changing AtomicBool
		current  bool
	}

	net struct {
		starting sync.WaitGroup
		stopping sync.WaitGroup
		sync.RWMutex
		bind          conn.Bind // bind interface
		netlinkCancel *rwcancel.RWCancel
		port          uint16 // listening port
		fwmark        uint32 // mark value (0 = disabled)
	}

	staticIdentity struct {
		sync.RWMutex
		privateKey wgcfg.PrivateKey
		publicKey  wgcfg.Key
	}

	peers struct {
		sync.RWMutex
		keyMap map[wgcfg.Key]*Peer
	}

	// unprotected / "self-synchronising resources"

	allowedips    AllowedIPs
	indexTable    IndexTable
	cookieChecker CookieChecker

	unexpectedip func(key *wgcfg.Key, ip wgcfg.IP)

	rate struct {
		underLoadUntil atomic.Value
		limiter        ratelimiter.Ratelimiter
	}

	pool struct {
		messageBufferPool        *sync.Pool
		messageBufferReuseChan   chan *[MaxMessageSize]byte
		inboundElementPool       *sync.Pool
		inboundElementReuseChan  chan *QueueInboundElement
		outboundElementPool      *sync.Pool
		outboundElementReuseChan chan *QueueOutboundElement
	}

	queue struct {
		encryption chan *QueueOutboundElement
		decryption chan *QueueInboundElement
		handshake  chan QueueHandshakeElement
	}

	signals struct {
		stop chan struct{}
	}

	tun struct {
		device tun.Device
		mtu    int32
	}
}
```

















## 梳理代码流程

### tailscaled v0.96

我觉得不管怎么样，先得捋一遍代码层级，知道其设计模式，才能更好的读新的代码。

老代码部分看着感觉打洞操作很简单，仅是lan口+endpoint，并且不考虑ip变化的情况，好像不如frp的打洞尝试（当然frp打洞尝试也没看全，但其对应建议的方法是比较全的，NAT4主打一个碰运气）。

当前理解到的，就是tailscale做了一堆的回调，挂了一堆的函数。这种方式可能类似状态机的实现？

就经常是初始化时挂几个方法，然后balabala处理后来消息了，调用初始化挂的方法去执行。

或者也可以说是异步？

这玩意接触的比较少，所以看起代码来非常吃力。

还是喜欢frp那种简单粗暴的调用，两眼一睁就知道他要干什么了

-----

代码层级还是比较多的，我们先来尝试梳理几个结构体

| 结构体                                                       | 作用                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| [LocalBackend](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L26-L58) | 整个后台的处理框架，此设计类似调停者，将多个杂七杂八的东西混合在一起<br>其存储了各种杂七杂八的东西，但具体的实现逻辑又不属于他<br>例如endpoints，netmap这种关键数据，他只做保存并传递给其他用户 |
| [wgengine.Engine](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/wgengine.go#L91-L137) | 应该算是核心操作，最后看到的Reconfig也是他<br>[Reconfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L299-L378) 启动WireGuard协议的网口，根据netMap更新生成对应的配置<br>[SetStatusCallback](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L271-L298) 监听本地endpoints的配置更新，并回调[c.UpdateEndpoints](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L289) 方法 |
| [controlclient.Client](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/control/controlclient/auto.go#L103-L130) | 与服务器交互的操作，用于更新netMap<br/>当本地 wgengine 更新本地endpoints时，触发更新后触发[c.UpdateEndpoints](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L289) 方法，后经过一系列操作，回调到LocalBackend初始化的 [c.SetStatusFunc](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L202-L269) 更新netMap。<br>当netMap更新后，触发[b.stateMachine](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L268) 更新状态，同时根据具体状态调用到了[b.authReconfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/ipn/local.go#L678) 操作<br>后调用到[wgengine.Engine.Reconfig](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/userspace.go#L299-L378) 操作，更新监听状态 |

这么一看突然感觉好简单，主要就是各种回调绕的头疼。

其核心内容：

#### endpoint部分

endpoint部分主要考虑获取部分，我们获取方式其实就是[updateNetInfo](######updateNetInfo)。

简单来说就是创建 Conn（[userspaceEngine.magicConn.pconn](https://github.com/tailscale/tailscale/blob/b364a871bfc0b8bbff7cdb4bdaf201ff731fee9d/wgengine/magicsock/magicsock.go#L47)）时去做NAT测试

1. 使用该Conn往STUN（4个derp）服务器发包。
2. 并设置相对应的 onPackage回调监听。
   - 解析回包的ip+port信息
     - 当前实现不考虑NAT4（ip或Port变动），若是NAT4则标记`MappingVariesByDestIP=true`
   - 像第一个返回的ip+port发包，探测是否能通。

并将本机监听的所有端口，与上层返回的第一个ip+port信息保留添加到endpoint中。

#### 打洞操作

打洞操作很简单，或者基本是没有打洞操作，当前看实现，感觉仅NAT1才能正常通信（暂时没看到与服务器的通信，后续可以看看与服务器通信的消息体，判断是否有打洞操作），其发包逻辑如下：

1. 获取所有的节点信息（netMap）
2. 建立WireGuard协议的虚拟网卡
   - 此实现支持多endpoint
3. WireGuard在发包时，遍历所有endpoint，并同时对这些数据发包

实现是极其的简单，不知道后续是否有其他操作用来增强打洞。

-----

此处猜测，未来若是实现NAT2,3,4该如何实现。

- 首先我们已经知道了与服务器通信的结构体`controlclient.Client`，后续看起是否有NAT包的通知
- 例如告知服务器，我们即将对xxx节点发出请求，请对方节点也往我的endpoints发包。当打通后保留该链接。
  - 不一定ok，得看Wireguard协议如何将发往该网卡的请求转发到对端endpoints上。
  - （猜测）当前的WireGuard可能是将请求导到某个进程中，进程随机一个端口往对端endpoints发信，当触发Rekey操作时，再随机一个端口发信，实现不同链接的密码协商与无缝切换。
    - 若是真是上述实现，那估计支持NAT2、NAT3协议十分困难，打通率就极低了。







-----

## 新版本

[新版本 git](https://github.com/tailscale/tailscale/tree/7c1d6e35a5863d58f3727af07dea0578fca87030)

基于上述逻辑，我们快速看新版本实现，直接跳到 [b.e.SetStatusCallback](https://github.com/tailscale/tailscale/blob/7c1d6e35a5863d58f3727af07dea0578fca87030/ipn/ipnlocal/local.go#L417) 

可以看到，他封装到了 [b.setWgengineStatus](https://github.com/tailscale/tailscale/blob/7c1d6e35a5863d58f3727af07dea0578fca87030/ipn/ipnlocal/local.go#L1478-L1517)中

```go
// setWgengineStatus is the callback by the wireguard engine whenever it posts a new status.
// This updates the endpoints both in the backend and in the control client.
func (b *LocalBackend) setWgengineStatus(s *wgengine.Status, err error) {
	if err != nil {
		b.logf("wgengine status error: %v", err)
		b.broadcastStatusChanged()
		return
	}
	if s == nil {
		b.logf("[unexpected] non-error wgengine update with status=nil: %v", s)
		b.broadcastStatusChanged()
		return
	}

	b.mu.Lock()
	if s.AsOf.Before(b.lastStatusTime) {
		// Don't process a status update that is older than the one we have
		// already processed. (corp#2579)
		b.mu.Unlock()
		return
	}
	b.lastStatusTime = s.AsOf
	es := b.parseWgStatusLocked(s)
	cc := b.cc
	b.engineStatus = es
	needUpdateEndpoints := !endpointsEqual(s.LocalAddrs, b.endpoints)
	if needUpdateEndpoints {
		b.endpoints = append([]tailcfg.Endpoint{}, s.LocalAddrs...)
	}
	b.mu.Unlock()

	if cc != nil {
		if needUpdateEndpoints {
			cc.UpdateEndpoints(s.LocalAddrs)
		}
		b.stateMachine()
	}
	b.broadcastStatusChanged()
	b.send(ipn.Notify{Engine: &es})
}
```

其主体逻辑还是没有变，当触发更新后，调用 `cc.UpdateEndpoints(s.LocalAddrs)`

调用cc(controlclient.Client) 的Direct去更新操作（此处拆分成了接口）





