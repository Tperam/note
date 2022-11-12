# Mysql 数据归档

## 简介

我们从**PXC**集群中将数据归档到 Percona 的 Toku 引擎中。

利用到 Percona的归档工具 **pt-archiver**

### 归档操作

```shell
pt-archiver \
--source h=192.168.0.1,P=3306,u=backup_user,p='password',D=test,t=c1 \
--dest h=192.168.2,P=3306,u=backup_user,p='password',D=test,t=c1_2008 \
--charset=UTF8 --where 'insert_time < "2020-08-01"'
--progress 10000 --limit=10000 --txn-size 
--bulk-delete --bulk-insert --statistics
```

- `--source` 源
- `--dest` 目标
- `--progress` 每多少条显示信息
- ` --bulk-delete` 源库删除数据
- `--limit` 每多少条数据归档一次
- `--statistics` 打印统计信息

