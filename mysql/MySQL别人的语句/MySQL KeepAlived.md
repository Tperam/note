# KeepAlived

### 安装准备工作

- 开启防火墙的 VRRP 协议

### 配置文件

```json
vrrp_instance VI_1 { // 配置信息名称
	state MASTER // 状态 主
	interface ens33 // 网卡名称
	virtual_router_id 51 // 虚拟路由标识 0-255之间
	priority 100 // 优先级
	advert_int 1 // 心跳检测 单位是 s
	authentication { // 心跳检测的账户名和密码
		auth_type PASS 
		auth_pass 123456
	}
	virtual_ipaddress { // 虚拟 ip 地址
		192.168.99.133
	}
	
}
```





