
shell 可通过 flock 进行上锁，flock有两种上锁方式

1. flock 进行上锁并执行一条命令
2. 在脚本内部进行手动上锁解锁（如果当前进程结束，也将自动释放锁）

方式一：
```shell
flock -e /root/a.lock -c echo "hi" >> /root/t.log
```

方式二：
```shell
echo "start to mount the dev"
LOCK_FILE=/root/a.lock # lock file， 上锁文件不同则不会互斥
exec 99> "${LOCK_FILE}" # 表示创建文件描述符99，指向锁文件，此处值不同也会互斥，
flock -e 99 # 上锁
...
flock -u 99 # 解锁
```

