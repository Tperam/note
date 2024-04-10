# Wireguard

我在看tailscaled的过程中遇到了比较大的困难。不是很理解大部分的代码含义，在看的过程中找不到关键点。所以此处开其具体底层实现（tailscale宣传的优势就是使用了最新的WireGuard协议）

官网：https://www.wireguard.com/

白皮书：https://www.wireguard.com/papers/wireguard.pdf

我们从官网看看他究竟是什么？干了什么？有什么作用？规范了哪些东西。

### 可以说是官网翻译了

虽然写出来没啥意义，但感觉写出来才算学了.

官网首页就讲到了，他是更快、更简单、更现代的VPN。他的目标是比IPsec更快、更简单、更轻、更有用。

然后介绍了他的目标，部署起来像是SSH，一个VPN连接只需要交换公钥。后续WireGuard在转发时不需要处理任何操作，仅需要把加密过后消息包发送即可。

并且列出了其支持的加解密算法

- [ChaCha20](http://cr.yp.to/chacha.html) for symmetric encryption, authenticated with [Poly1305](http://cr.yp.to/mac.html), using [RFC7539's AEAD construction](https://tools.ietf.org/html/rfc7539)
- [Curve25519](http://cr.yp.to/ecdh.html) for ECDH
- [BLAKE2s](https://blake2.net/) for hashing and keyed hashing, described in [RFC7693](https://tools.ietf.org/html/rfc7693)
- [SipHash24](https://131002.net/siphash/) for hashtable keys
- [HKDF](https://eprint.iacr.org/2010/264) for key derivation, as described in [RFC5869](https://tools.ietf.org/html/rfc5869)

并且由于代码极小，相比于OpenVPN、OpenSSL、Swan、IPsec等源码更容易review，由于代码量的减少，更容易发现其漏洞。

在其Conceputal Overview部分，也简单引导了用户，让有不同目标的用户可以去不同的位置看不同的东西。

1. 如果指向简单了解WireGuard，将会引导用户去[安装](https://www.wireguard.com/install/)，并引导用户快速开始[the quickstart instructions](https://www.wireguard.com/quickstart/)
2. 如果想稍微了解一点WireGuard，则可查看[protocol](https://www.wireguard.com/protocol/)
3. 如果想更深入一点，则可以看[白皮书](https://www.wireguard.com/papers/wireguard.pdf)
4. 给新平台适配[cross-platform notes](https://www.wireguard.com/xplatform/).

通常在这里，我们就可以先从1开始了（因为咱其实啥也不明白）

#### 使用教程

简单看了一下用户引导（里面是个视频，很清晰，很直白）

就是两台机子配置俩虚拟网卡

```shell
ip link add dev wg0 type wireguard
```

并添加虚拟IP（此处随便设置，两台机子不能相同）

```shell
ip address add dev wg0 10.0.0.1/24
```

创建privatekey+publickey

```shell
wg genkey | tee privatekey | wg pubkey > publickey
```

wg导入私钥

```shel
wg set wg0 private-key ./privatekey
```

拉起wg

```shell
ip link set wg0 up 
```

打印出两台机子的信息

```shell
# wg
 public key: xxxx
 private key: xxxx
 listening port: 51820
```

将打印出的信息的Public key，在对方节点中导入

```shell
wg set wg0 peer 对端pubkey allowed-ips 10.0.0.2/32 endpoint 对端ip:51820
```

此时，如果配置没错，双端就通了

可以尝试互相Ping。

-----

上面就是简单的使用方式，我们可以看到啊，其实使用起来很简单，逻辑也很简单。WireGuard就是帮我们创建了一个虚拟网卡，并且建立了路由`allowed-ips`。

我们在本机上往10.0.0.2发送消息的时候都会通过提供的endpoint将数据包发送到对方服务器上。然后对方又以他的10.0.0.2建立五元组，实现链接。

其传输协议也在首页中声明：

> **WireGuard securely encapsulates IP packets over UDP.**
>
> WireGuard 使用UDP封装IP包

其首页也描述了：

> **WireGuard associates tunnel IP addresses with public keys and remote endpoints. When the interface sends a packet to a peer, it does the following:**
>
> 1. This packet is meant for 192.168.30.8. Which peer is that? Let me look... Okay, it's for peer `ABCDEFGH`. (Or if it's not for any configured peer, drop the packet.)
> 2. Encrypt entire IP packet using peer `ABCDEFGH`'s public key.
> 3. What is the remote endpoint of peer `ABCDEFGH`? Let me look... Okay, the endpoint is UDP port 53133 on host 216.58.211.110.
> 4. Send encrypted bytes from step 2 over the Internet to 216.58.211.110:53133 using UDP.
>
> WireGaurd 使用 public keys + remote endpoints 与对端关联。当本机接口发送一个包到对端时，他做了以下操作
>
> 1. 判断包目标地址的ip，根据ip判断是哪个节点的，此处找到节点是`ABCDEFGH`。（没找到则废弃）
> 2. 使用`ABCDEFGH`的公钥对IP包加密
> 3. 找到`ABCDEFGH`的endpoint的ip:port
> 4. 使用UDP往`ABCDEFGH`的endpoint的ip:port发包



#### NAT and Firewall Traversal Persistence

NAT与Firewall的持久性（或者说keepalive、保活）

在默认情况下，两个节点建立连接后WireGuard只有在传输数据时才会发包（换句话说，在默认情况下他不会一直发心跳包）。

但这在NAT或Firewall下可能会有问题。因为在NAT/firewall下需要通过持续的发包来保证NAT/firewall的映射。

持续发包这个操作也可以称为`persistent keepalives`。这在WireGuard中是一个选项（`PersistentKeepalive = 25`）。当该选项开启后，每隔一定时间后将会发送一次心跳包到endpoint的服务器中。

至于值为什么是25，因为其认为对于各种防火墙，合理的间隔时间为25s。





