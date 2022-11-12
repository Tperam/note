### 部署方式

#### 官方方式部署

> https://github.com/kubernetes/dashboard/blob/master/docs/user/installation.md

部署方式

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.2.0/aio/deploy/recommended.yaml
```





现在发现需要证书才能远程访问。。。。

#### 获取镜像配置

> https://www.servicemesher.com/blog/general-kubernetes-dashboard/

获取配置，自己修改

```shell
wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.2.0/aio/deploy/recommended.yaml
```



#### 使用官方非安全的方式进行部署

```shell
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/alternative.yaml
```



### 运行方式

运行后通过 

```shell
kubectl proxy --address=0.0.0.0 --accept-hosts='^*$'
```

登录时需要 token or kubconfig。这是k8s中的认证相关，暂时不清楚是啥玩意，看不明白。

我们以 token 访问

获取token name

```shell
kubectl get secret -n=kube-system
```

查出一堆值，从中随便挑选一个

这里使用 `default-token-x7ftw`

```shell
kubectl describe secret -n=kube-system default-token-x7ftw
```

