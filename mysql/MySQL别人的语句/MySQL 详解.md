# MySQL

## 本地文件

### 逻辑库文件结构

**Schema**

| 文件后缀名     | 描述                                                         |
| -------------- | ------------------------------------------------------------ |
| OPT            | 逻辑库的描述文件，用来记录数据库使用的字符集和字符集排序规则 |
| FRM            | 数据表的定义文件，包含数据表的结构信息，字段信息，索引信息   |
| MYD `(MyISAM)` | MyISAM 引擎的数据文件                                        |
| MYI `(MyISAM)` | MyISAM 引擎的索引文件                                        |
| IBD `(InnoDB)` | InnoDB 的索引文件和数据文件                                  |
| isl            | 表分区的路径                                                 |

### 数据目录的其他文件

| 文件名         | 描述                   |
| -------------- | ---------------------- |
| auto.cnf       | 保存的是MysQL的UUID值  |
| grastate.dat   | 保存的是PXC的同步信息  |
| gvwstate.dat   | 保存的是PXC集群的信息  |
| err            | 错误日志文件           |
| pid            | 进程id文件             |
| ib_buffer_pool | InnoDB缓存文件         |
| ib_logfile     | InnoDB事务日志（redo） |
| ibdata         | InnoDB共享表空间文件   |
| logbin         | 日志文件               |
| index          | 日志索引文件           |
| ibtmp          | 临时表空间文件         |
| pem            | 数据加密解密           |
| sock           | 套接字文件             |

-----

## 数据内容

### 数据碎片化问题

- 向数据表写入数据，数据文件的体积会增大，但是删除数据的时候数据文件体积并不会减小，数据被删除后留下的空白，被称作碎片

#### 碎片整理

在做碎片之前，需要防止当前操作写入binlog日志，所以我们去mysql 配置文件中注释一下两行

- `#log_bin`
- `#log_slave_updates`

碎片整理语句

```MYSQL
ALTER TABLE student ENGINE=InnoDB;
```

