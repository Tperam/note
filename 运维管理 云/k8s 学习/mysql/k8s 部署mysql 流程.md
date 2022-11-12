1. 编写mysql配置文件 *.cnf

2. 编写启动文件  mysql.yaml

   - 其中包含两个类型

     - Service
     - Deployment

   - Deployment中包含

     - 目录的挂载

     - ```shell
       volumeMounts:
       - name: mysql-data-volume
       mountPath: /opt/mysql/data
       - name: mysql-log-volume
       mountPath: /opt/mysql/logs
       - name: mysql-config-volume
       mountPath: /etc/mysql/conf.d/
       ```

     - 心跳检测

       ```shell
       livenessProbe:
           initialDelaySeconds: 30
           periodSeconds: 10
           timeoutSeconds: 5
           successThreshold: 1
           failureThreshold: 3
           exec:
           	command: ["mysqladmin", "-uroot", "-p${MYSQL_ROOT_PASSWORD}", "ping"]
       readinessProbe:  
           initialDelaySeconds: 10
           periodSeconds: 10
           timeoutSeconds: 5
           successThreshold: 1
           failureThreshold: 3
           exec:
           	command: ["mysqladmin", "-uroot", "-p${MYSQL_ROOT_PASSWORD}", "ping"]
       ```

       此处有坑， ${MYSQL_ROOT_PASSWORD} 无法将之前设置的环境变量导入，导致启动的mysql报错

       ```shell
       [Note] Access denied for user 'root'@'localhost' (using password: YES)
       ```

       