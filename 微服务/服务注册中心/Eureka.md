#### 基础

- Eureka Server
  - 提供服务注册和发现
- Service Provider
  - 服务提供方，将滋生服务注册到Eureka Server
- Service Consumer
  - 服务消费方，从 Eureka Server 中获取注册服务列表。
  - 最终通过直连的方式，去访问 Service Provider



#### 自我保护机制

这里，主要讲的是一种极端情况

当某个Service Provider 已经注册了，并且也已经被部分 Service Consumer 连接了。在这种情况下， Service Provider 突然与 Eureka Server 的网络不通了。

根据服务注册中心的理论，正常情况下 Eureka Server 会认为该服务已经挂掉，会从列表中删除，并且同步下发到所有的 client 中。

接下来就是根据 client 操作决定是否剔除掉该 Service Provider。



在 Eureka 中，会有client决定是否剔除掉该服务。