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
  - 创建虚拟网卡，登陆
- downCmd
  - 关闭tailscale，关闭网卡
- statusCmd
  - 输出当前tailscale状态，可以看到IP信息，对端客户端，以及如果建立了链接，其是中转还是打洞。

此处我们先看upCmd（其中应该是也包含了loginCmd的相关操作），这个操作也是





















## 代码层级

