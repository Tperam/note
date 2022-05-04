#!/bin/bash


# k8s_install.sh password
echo $1 | sudo apt-get update 

# 安装依赖
sudo apt-get install -y ca-certificates curl software-properties-common apt-transport-https curl

curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -

sudo tee /etc/apt/sources.list.d/kubernetes.list <<EOF 
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF

sudo apt update

sudo apt install -y kubelet kubeadm kubectl

# 关闭swap
sudo sed -i 's/\/swapfile/#&/' /etc/fstab

sudo reboot 