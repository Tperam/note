# MySQL 导入大量数据



### 导入方式

#### source

通过执行sql语句来导入数据。

```mysql
source file.sql
```

**缺点**

- 少量数据可行
  - 大于10w条使用load
  - 执行sql语句插入，mysql每次都会对其进行优化

#### load

通过对数据文本切分，导入数据。

```mysql
load data local infile 'file.name' ignore into table `tablename` 
	FIELDS TERMINATED BY ' '
	LINES TERMINATED BY '\n';
```

**缺点**

- 单线程
  - 可以通过切分数据

-----

### 导入优化

对mysql的一些设置进行更改。

| 参数                               | 值       | 解析                                         |
| ---------------------------------- | -------- | -------------------------------------------- |
| `innoodb_flush_log_at_trx_coommit` | 0        | 相当于数据库在事务提交之前就写入日志         |
| `innodb_flush_method`              | O_DIRECT | 日志数据直接写入到磁盘，而不是写到系统缓冲区 |
| `innodb_buffer_pool_size`          | 200M     | 写入缓存区，越大越好。                       |

