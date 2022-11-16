

#### 打包已有镜像
#docker打包镜像
提交一个正在运行的镜像
```shell
docker commit mycentos myomcat
```
镜像打包
```shell
docker save -o ~/xxx.tar  <name>
```
导入镜像
```shell
docker load -i /root/xxx.tar
```
容器打包
```shell
docker export -o /root/xx.tar  <name>
```
导入容器
```shell
docker import xx.tar <name>:latest
```
