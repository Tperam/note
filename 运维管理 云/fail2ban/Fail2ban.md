[Fail2ban](https://www.fail2ban.org/wiki/index.php/Main_Page)是一个基于iptables实现的ip屏蔽，可用于屏蔽恶意请求、恶意爬虫等。提升服务器安全。

#tls
由于有大量的爬虫对我司服务器进行爬取请求：大量机器请求空连接，并建立tls链接（单个tls消耗流量4kByte左右），导致服务器负载较高，现通过此方式解决。


当前系统基于Ubuntu。

参考[教程](https://learnku.com/server/t/36233)
### 安装
根据不同系统使用不同方式[安装](https://www.fail2ban.org/wiki/index.php/Downloads)
没有版本要求可直接通过`apt install` or `yum install` 安装

安装后，我们将会使用以下命令
- fail2ban-client
- fail2ban-regex
- ...

### 配置
fail2ban主要是根据配置文件进行禁用。其配置文件存放在`/etc/fail2ban`下
```shell
/etc/fail2ban# tree
.
├── action.d
│   ├── ...
│   └── xarf-login-attack.conf
├── fail2ban.conf
├── fail2ban.d
├── filter.d
│   ├── ...
│   └── zoneminder.conf
├── jail.conf
├── jail.d
│   └── defaults-debian.conf
├── jail.local
├── paths-arch.conf
├── paths-common.conf
├── paths-debian.conf
└── paths-opensuse.conf
```

> 对于所有支持的操作系统，fail2ban 安装在 /etc/fail2ban 路径下。其配置文件 jail.conf 在同一文件夹下。但是，如果想对配置做出改变，不应直接修改 jail.conf ，代之一份本地拷贝文件进行修改

我们暂时需要了解：
- jail.local
- filter.d 目录下的部分文件

#### jail.local
使用`.ini`格式
在jail.local中，有一个默认配置
``` ini
[DEFAULT]

# "ignoreip" 字段设置不会被禁止访问的主机地址，它可以是单 IP 地址、
# CIDR （汇聚网段）地址，甚至可以是 DNS （主机域名）。
# 若有多个条目，各条目间用空格分隔。
ignoreip = 127.0.0.1

# "bantime" 字段设置禁止访问的时间间隔，以秒为单位。
bantime  = 3600

# "findtime" 字段设置含义，在这个指定时间间隔内，
# 达到或超过  "maxretry"  次失败连接尝试，即被命中，禁止访问。
# 以秒为单位。
findtime  = 600

# "maxretry" 字段设置含义，见上个字段设置说明。
Maxretry = 3

# "enabled" 开启服务
enabled = false
```
上面默认配置如果开启，将会默认应用在所有链接上。
如果我们只想配置我们的nginx
则可以类似如下：
```ini
[nginx-image]
# 开启服务
enabled = true 
# 监听日志路径
logpath = /var/log/nginx/access.log
# filter.d 过滤规则中的文件名
filter = nginx-image
# 禁用时间 30天
bandtime = 30d
# 禁用时间递增
bantime.increment = true
# 在4h时间内搜索
findtime = 4h
# 最大尝试6次
maxretry = 6
```


#### filter.d

配置完 jail.local，我们需要配置相应的匹配规则。
详细可参考[jail.conf]([](https://manpages.debian.org/testing/fail2ban/jail.conf.5.en.html))

其有特殊字符`<HOST>`用于匹配ipv4、ipv6客户端。
- failregex 用来匹配日志行，通过其正则匹配到想要的行。
- ignoreregex 用来忽略failregex匹配上的特殊的部分
- datepattern 用来匹配时间戳
	- {DEFAULT} 默认时间模式 `%%Y-%%m-%%d %%H:%%M(?::%%S)?`
	- {DATE} 可以用作将被默认日期模式替换的正则表达式的一部分。
	- {^LN-BEG} 以时间开头
	- {UNB} 在正则表达式中禁用自动单词边界的前缀
	- {NONE} 允许在日志消息中没有日期的情况下使用
```ini
# fail2ban filter configuration for nginx

[Definition]

failregex = ^.*?\"<HOST>\".*?$

ignoreregex =

#datepattern = {^LN-BEG}

# DEV NOTES:
# Based on samples in https://github.com/fail2ban/fail2ban/pull/43/files
# Extensive search of all nginx auth failures not done yet.
#
# Author: Daniel Black
```


