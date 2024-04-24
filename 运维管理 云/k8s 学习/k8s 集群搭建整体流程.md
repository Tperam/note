知乎步骤

> https://zhuanlan.zhihu.com/p/46341911

1. k8s、docker安装
2. 关闭swap，以及修改docker启动命令
3. 获取镜像列表，以便从国内获取
   - 或者在运行时指定访问仓库
   - `--image-repository registry.aliyuncs.com/google_containers`
4. 初始化环境
5. 配置授权信息, 以便可以便捷访问kube-apiserver
6. 添加网络插件
7. 单节点，设置master节点也可以运行Pod（默认策略是master节点不运行）
8. 部署其他插件

### docker 安装

安装

```shell
sudo apt-get update

sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```

添加GPG

```shell
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
```



```shell
 echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```



安装Docker 引擎

```shell
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io
```



docker启动配置修改 1

```shell
sudo vim /etc/docker/daemon.json
```

```json
{
        "exec-opts": ["native.cgroupdriver=systemd"],
        "registry-mirrors":[
                "https://f5r2myhq.mirror.aliyuncs.com"
        ]
}
```

```shell
sudo systemctl daemon-reload
sudo systemctl restart docker 
```

配置方法2

````markdown
#### docker启动配置修改 2

修改docker启动命令

> https://blog.csdn.net/qq_29349143/article/details/120872330

​```shell
sudo vim /usr/lib/systemd/system/docker.service
```

找到此部分

```shell
[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
```

在ExecStart中增加`--exec-opt native.cgroupdriver=systemd` 该变成以下形式

```shell
[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd -H fd:// --exec-opt native.cgroupdriver=systemd --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
```

保存后执行命令

```shell
systemctl daemon-reload
systemctl restart docker
```

#### 
````

权限组

1. 找到docker的用户组，或创建用户组

​```shell
sudo groupadd docker
```

2. 将用户加入该group

```shell
sudo usermod -aG docker $USER
```

3. 重启服务

```shell
sudo service docker restart
```



### k8s安装

基础依赖

```shell
sudo apt-get update && sudo apt-get install -y ca-certificates curl software-properties-common apt-transport-https curl
```

添加软件包

```shell
curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
```

添加源

```shell
sudo tee /etc/apt/sources.list.d/kubernetes.list <<EOF 
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
```

更新包

```shell
sudo apt update
```

安装

```shell
sudo apt install -y kubelet kubeadm kubectl
```

### swap 配置

禁用虚拟内存

```shell
sudo vi /etc/fstab
```

注释相关代码 `swap`开头

```shell
sudo reboot
```

重启后查看是否置为0

```shell
sudo free -m 
```



### 获取镜像列表 同时安装

获取镜像列表

```shell
kubeadm config images list 
```



```shell
images=(  # 下面的镜像应该去除"k8s.gcr.io/"的前缀，版本换成上面获取到的版本
    kube-apiserver:v1.22.4
    kube-controller-manager:v1.22.4
    kube-scheduler:v1.22.4
    kube-proxy:v1.22.4
    pause:3.5
    etcd:3.5.0-0
    coredns:1.8.4
)

for imageName in ${images[@]} ; do
    docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName
    docker tag registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName k8s.gcr.io/$imageName
    docker rmi registry.cn-hangzhou.aliyuncs.com/google_containers/$imageName
done
```

### 初始化操作

#### master端

执行

```shell
sudo kubeadm init --kubernetes-version=v1.22.4 --pod-network-cidr=10.244.0.0/16
```

也可增添更多参数：

```shell
kubeadm init \
--apiserver-advertise-address=192.168.0.30 \
--image-repository registry.aliyuncs.com/google_containers \
--pod-network-cidr=10.244.0.0/16
```

#### node端

使用初始化操作后的命令，类似于：

```shell
kubeadm join 192.168.0.30:6443 --token gasjod.99h0nq573oj3wyop \
        --discovery-token-ca-cert-hash sha256:62eba9bb1264df0c60498a9ba4a16126a82a278596bb158f956fb67dd5f028f8
```



### 安装相应网络组件

此步骤必须要执行。

常见组件：

- Flannel
- Calico
- Canal

这里我们使用 Flannel

```shell
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```







## 坑

```shell
[kubelet-check] It seems like the kubelet isn't running or healthy.
[kubelet-check] The HTTP call equal to 'curl -sSL http://localhost:10248/healthz' failed with error: Get "http://localhost:10248/healthz": dial tcp 127.0.0.1:10248: connect: connection refused.
```

修复方式

[docker启动配置修改](###docker启动配置修改)



