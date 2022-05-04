#!/bin/bash

# ./docker_install.sh password
echo $1 | sudo apt-get update

sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

sudo tee /etc/docker/daemon.json
<<EOF
{
        "exec-opts": ["native.cgroupdriver=systemd"],
        "registry-mirrors":[
                "https://f5r2myhq.mirror.aliyuncs.com"
        ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker 

sudo groupadd docker

sudo usermod -aG docker $USER

sudo service docker restart