# HaProxy

### 配置文件

##### 监控界面

| 参数        | 值                   | 解析                      |
| ----------- | -------------------- | ------------------------- |
| listen      | `admin_stats`        | 配置信息的名字            |
| bind        | `0.0.0.0:4001`       | 监控界面的访问的ip和端口  |
| mode        | `http`               | 访问协议                  |
| stats uri   | `/dbs`               | 监控画面访问的uri相对路径 |
| stats realm | `Global\ statistics` | 统计报告的格式            |
| stats auth  | `admin:abc123456`    | 登录账户信息              |



##### MyCat负载均衡设置

| 参数    | 值                                                      | 解析                     |
| ------- | ------------------------------------------------------- | ------------------------ |
| listen  | `proxy-mysql`                                           | 配置信息的名字           |
| bind    | `0.0.0.0:3306`                                          | 监控界面的访问的ip和端口 |
| mode    | `tcp`                                                   | 访问协议                 |
| balance | `roundrobin`                                            | 请求转发算法             |
| option  | `tcplog`                                                | 日志格式                 |
| server  | `mycat_1 ip:port check port 8006 weight 1 maxconn 2000` | 负载均衡服务器配置       |
| server  | `mycat_2 ip:port check port 8006 weight 1 maxconn 2000` | 负载均衡服务器配置       |
| option  | `tcpka`                                                 | 使用keepalive 检测死链   |

