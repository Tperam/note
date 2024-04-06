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

我们通过全局搜索`/localapia/v0` （因为没搜到`/localapi/v0/status`，所以想尝试删除，看看能不能匹配到前半段部分）搜索到此部分，[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/ipn/localapi/localapi.go#L75-L143) 其中注册了许多Handler方法。

我们回溯到源头，其实在tailscaled.go文件中进行的调用[代码](https://github.com/tailscale/tailscale/blob/ec87e219ae8828f74448c74a7026016a8b037a19/cmd/tailscaled/tailscaled.go#L487)

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



#### prefs

#### watch-ipn-bus

#### login-interactive

#### start























## 代码层级

