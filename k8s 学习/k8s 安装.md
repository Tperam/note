ubuntu 安装 k8s 方式

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

