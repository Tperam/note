# Wireguard

我在看tailscaled的过程中遇到了比较大的困难。不是很理解大部分的代码含义，在看的过程中找不到关键点。所以此处开其具体底层实现（tailscale宣传的优势就是使用了最新的WireGuard协议）

官网：https://www.wireguard.com/

白皮书：https://www.wireguard.com/papers/wireguard.pdf

我们从官网看看他究竟是什么？干了什么？有什么作用？规范了哪些东西。

### 可以说是官网翻译了

虽然写出来没啥意义，但感觉写出来才算学了.

官网首页就讲到了，他是更快、更简单、更现代的VPN。他的目标是比IPsec更快、更简单、更轻、更有用。

然后介绍了他的目标，部署起来像是SSH，一个VPN连接只需要交换公钥。后续WireGuard在转发时不需要处理任何操作，仅需要把加密过后消息包发送即可。

并且列出了其支持的加解密算法或说是WireGuard的引用的实现或理论

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
> When the interface receives a packet, this happens:
>
> 1. I just got a packet from UDP port 7361 on host 98.139.183.24. Let's decrypt it!
> 2. It decrypted and authenticated properly for peer `LMNOPQRS`. Okay, let's remember that peer `LMNOPQRS`'s most recent Internet endpoint is 98.139.183.24:7361 using UDP.
> 3. Once decrypted, the plain-text packet is from 192.168.43.89. Is peer `LMNOPQRS` allowed to be sending us packets as 192.168.43.89?
> 4. If so, accept the packet on the interface. If not, drop it.
>
> 
>
> WireGaurd 使用 public keys + remote endpoints 与对端关联。当本机接口发送一个包到对端时，他做了以下操作
>
> 1. 判断包目标地址的ip，根据ip判断是哪个节点的，此处找到节点是`ABCDEFGH`。（没找到则废弃）
> 2. 使用`ABCDEFGH`的公钥对IP包加密
> 3. 找到`ABCDEFGH`的endpoint的ip:port
> 4. 使用UDP往`ABCDEFGH`的endpoint的ip:port发包
>
> 当接口收到包时，将会发生：
>
> 1. 从98.139.183.24:7361收到了UDP包，我们对其解码
> 2. 通过解码认证，他是节点`LMNOPQRS`。我们记住对端的endpoint（98.139.183.24:7361）
> 3. 一次解码后，明文数据包时来自192.168.43.89，然后判断`LMNOPQRS`是否允许从192.168.43.89给我们发送包？
> 4. 如果可以，则接受包。如果不可以则丢弃

看到这里，我们其实已经了解整个wireguard的运作流程了



#### Cryptokey Routing

WireGuard里面有个概念叫做 Cryptokey Routing。

翻译过来就是密钥路由。

其含义就是我们在创建wireguard协议网口的时候，给对端节点（peer）填写了AllowIPS。这是一个ip段，你可以写入10.0.0.0/8。这样写将会使所有访问10.0.0.0/8的请求都走该peer。
例如 udp包：dst 10.55.33.1 dport 8888，他也将访问该peer，（使用其设置的PublicKey对数据编码后发到配置的endpoint中）。  
当该udp包发过来后，对端节点（peer）的wg使用私钥对其解码，得到dst 10.55.33.1，将会与当前路由进行判断（是否有该路由或网卡），若没有，则将丢弃包。若有，则把该IP与Port转发过去处理。



#### NAT and Firewall Traversal Persistence

NAT与Firewall的持久性（或者说keepalive、保活）

在默认情况下，两个节点建立连接后WireGuard只有在传输数据时才会发包（换句话说，在默认情况下他不会一直发心跳包）。

但这在NAT或Firewall下可能会有问题。因为在NAT/firewall下需要通过持续的发包来保证NAT/firewall的映射。

持续发包这个操作也可以称为`persistent keepalives`。这在WireGuard中是一个选项（`PersistentKeepalive = 25`）。当该选项开启后，每隔一定时间后将会发送一次心跳包到endpoint的服务器中。

至于值为什么是25，因为其认为对于各种防火墙，合理的间隔时间为25s。



### protocol

https://www.wireguard.com/protocol/

上面介绍了最简单的原理，以及实现方式，接下来我们稍微看下protocol，看看看不看得懂。

好吧，具体没怎么看懂，但感觉可能是以下含义：

- 为了安全考虑，有一个简单的handshake操作，用于建立密钥对，用于后续的数据传输。并且这个handshake操作在每几分钟就会发生一次。
  - 就是从原先的pubkey+privatekey，转换成新的pubkey+privatekey
    - 每个privatekey都是短暂的，用此来实现数据的安全性
  - 我之前也想实现类似这个功能的库，但是没什么思路，总感觉会影响中途传输的包。
- 这里描述了，这个handshake是基于时间的，不是基于传输数据包的数据的，因为这样设计，能更优雅的处理丢包。
  - （这里其实就开始蒙了，因为不知道怎么基于数据传输包实现密钥交换，并且如果基于数据传输包来改变handshake，在丢包的情况下会发生什么）



反正吧，文中说上述的交换密钥操作，将会在以下情况触发（或者是说handshake碰到的情况将会做某些操作）：

- 进行handshake初始化。当响应超过`REKEY_TIMEOUT + jitter`的时间后，将会重新尝试 。
  - `REKEY_TIMEOUT`应该是参数，`jitter`是0~333ms的随机数。
- 如果正在进行handshake，并且也收到peer的回应。但由于我们`KEEPALIVE`时间要到了，必须要发送一条消息出去时，我们将发送一个空包出去（保持链接活性）
- 如果我们发包给peer，但peer没有在`KEEPALIVE + REKEY_TIMEOUT`ms内回复我们，我们将重新初始化。
- 如果没有新的keys进行交换，所有临时session与PrivateKey将在`REJECT_AFTER_TIME * 3`ms后清零。
- 如果使用相同的公钥发送了`REKEY_AFTER_MESSAGES`包后，也会触发handshake
- 发送包后，如果发送者是handshake的发起者，则将在`REKEY_AFTER_TIME`后，重新发起handshake。如果他handshake的接收者，则将不做任何操作。
  - 这里我的理解是，其表示永远都是最初发起handshake那端发起rekey的请求。
- 在接收包后，如果接收者是handshake的发起者，则将在`REKEY_AFTER_TIME - KEEPALIVE_TIMEOUT - REKEY_TIMEOUT`ms 后发起新的handshake
- handshake在`REKEY_TIMEOUT`ms中只发起一次，这是强制的速率限定
- 如果session数量大于`REJECT_AFTER_MESSAGES`或者key时间老于`REJECT_AFTER_TIME`ms，则将丢弃该包
- 在初始化新的handshake并且尝试了`REKEY_ATTEMPT_TIME`ms后，将终止再次尝试，清除所有发送队列。如果数据包明确排队等待发送，则重置此计时器。（后面这句没跟上，不知道啥意思）

当握手完成后（发送者到接收者，接收者回复发送者），然后发送者可以发送加密的会话数据包，但接收者不行。接收者必须等待新的session，直到他从发送者收到一个加密的会话数据包。为了提供密钥确认。因此，直到接收者接收到第一个新的加密session包之前，它必须将要发的包排到队列中，或使用老的session。所以，发送者在接收到接收者的回复后，如果没有需要立即发送的包，则应该发一个空包来确认链接。

-----

简单的Protocol流程就是这样，感觉不如直接google翻译官网Protocol，这里也就是我的理解展现。