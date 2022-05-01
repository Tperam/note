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
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io
```



配置Docker国内镜像&k8s启动项

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



权限组

1. 找到docker的用户组，或创建用户组

```shell
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

