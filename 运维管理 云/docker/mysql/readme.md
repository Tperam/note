# Readme



docker 运行 Mysql

我们这里使用docekrfile的方式进行部署

> https://docs.docker.com/engine/reference/builder/

使用mysql 5.7版本



dockerfile仅仅是打一个镜像包，并将挂载路径明确，但并不对主机挂载目录进行指定（因dockerfile只是打一个镜相包，后续需要通过 docker run 来配置启动）。



直接使用官方提供的mysql:5.7 包即可。

我们需要将我们的 .cnf 进行替换



```shell
docker run  -e MYSQL_ROOT_PASSWORD=1929564872 \
-d --restart always -p 3306:3306 \
-v /opt/mysql/data:/opt/mysql/data \
-v /opt/mysql/logs:/opt/mysql/logs \
-v /opt/mysql/conf:/etc/mysql/ \
--name mysql \
mysql:5.7
```

