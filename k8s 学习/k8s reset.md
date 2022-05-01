工作节点

```shell
sudo rm -rf /etc/kubernetes/*
sudo kubeadm reset -f
```

Master节点

```shell
sudo rm -rf /etc/kubernetes/*
sudo rm -rf ~/.kube/8
sudo rm -rf /var/lib/etcd/*
sudo kubeadm reset -f
```

