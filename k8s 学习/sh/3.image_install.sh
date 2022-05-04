#!/bin/bash

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