# Mysql表分区



## 简介

### mysql 表分区有四种模式

- Range 分区： 根据连续区间值切分数据
- List 分区：根据枚举值切分数据
- Hash 分区：对整数求模切分数据
- Key 分区：对任何数据类型球磨切分数据

### 优点

- 可以让单表存储更多的数据
- 分区表的数据更容易维护，可以通过清楚整个分区批量删除大量数据，也可以增加新的分区来支持新插入的数据。另外，还可以对一个独立分区进行优化、检查、修复等操作
- 部分查询能够从查询条件确定只落在少数分区上，速度会很快
- 分区表的数据还可以分布在不同的物理设备上，从而搞笑利用多个硬件设备
- 可以使用分区表赖避免某些特殊瓶颈，例如InnoDB单个索引的互斥访问、ext3文件系统的inode锁竞争
- 可以备份和恢复单个分区

### 缺点

- 如果分区字段中有主键或者唯一索引的列，那么所有主键列和唯一索引列都必须包含进来
- 分区表无法使用外键约束
- NULL值会使分区过滤无效
- 所有分区必须使用相同的存储引擎

-----

## 表分区



### Range

```mysql
CREATE TABLE t_range_1(
	id INT UNSIGNED,
	name VARCHAR(200) NOT NULL,
	PRIMARY KEY(`id`)
)
PARTITION BY RANGE(id)(
	PARTITION p0 VALUES LESS THAN(10000000),
	PARTITION p1 VALUES LESS THAN(20000000),
	PARTITION p2 VALUES LESS THAN(30000000),
	PARTITION p3 VALUES LESS THAN(40000000)
);
```

- 当前语句将`t_range_1`进行了分区，分成了4各区块。
  - 第一个区块存放 主键值小于 10000000
  - ...

很少使用。多数情况下都会对冷数据进行归档处理，新数据不会切分到原有分区。

#### 优化

**与不同列进行拆分**

将时间转换为整数类型。以月份进行切分 

```mysql
CREATE TABLE t_range_2(
	id INT UNSIGNED,
	name VARCHAR(200) NOT NULL,
    birthday DATE NOT NULL,
	PRIMARY KEY(`id`,`birthday`)
)
PARTITION BY RANGE(MONTH(birthday))(
	PARTITION p0 VALUES LESS THAN(3),
	PARTITION p1 VALUES LESS THAN(6),
	PARTITION p2 VALUES LESS THAN(9),
	PARTITION p3 VALUES LESS THAN(12)
);
```

不仅如此，还可以按照年龄等列进行拆分

**将表映射到不同的硬盘**

每个磁盘的写入读取速度互不干扰，所以我们将表分区映射到不同的磁盘上

```mysql
CREATE TABLE t_range_2(
	id INT UNSIGNED,
	name VARCHAR(200) NOT NULL,
    birthday DATE NOT NULL,
	PRIMARY KEY(`id`,`birthday`)
)
PARTITION BY RANGE(MONTH(birthday))(
	PARTITION p0 VALUES LESS THAN(3) DATA DIRECTORY="/mnt/p0/data",
	PARTITION p1 VALUES LESS THAN(6) DATA DIRECTORY="/mnt/p1/data",
	PARTITION p2 VALUES LESS THAN(9) DATA DIRECTORY="/mnt/p2/data",
	PARTITION p3 VALUES LESS THAN(12) DATA DIRECTORY="/mnt/p3/data"
);
```

### List

通过枚举的方式将数据进行分区

```mysql
CREATE TABLE t_list_1(
	id INT UNSIGNED,
	name VARCHAR(200) NOT NULL,
    province_id INT UNSIGNED NOT NULL,
	PRIMARY KEY(`id`,`province_id`)
)
PARTITION BY LIST(province_id)(
	PARTITION p0 VALUES IN(1,2,3,4) DATA DIRECTORY="/mnt/p0/data",
	PARTITION p1 VALUES IN(5,6,7,8) DATA DIRECTORY="/mnt/p1/data",
	PARTITION p2 VALUES IN(9,10,11,12) DATA DIRECTORY="/mnt/p2/data",
	PARTITION p3 VALUES IN(13,14,15,16) DATA DIRECTORY="/mnt/p3/data"
);
```

### Hash

通过hash运算 得到分片位置。（只能使用整数）

```mysql
CREATE TABLE t_hash_1(
	id INT UNSIGNED,
	name VARCHAR(200) NOT NULL,
	province_id INT UNSIGNED NOT NULL
)
PARTITION BY HASH(id) PARTITIONS 4(
	PARTITION p0 DATA DIRECTORY="/mnt/p0/data",
	PARTITION p1 DATA DIRECTORY="/mnt/p1/data",
	PARTITION p2 DATA DIRECTORY="/mnt/p2/data",
	PARTITION p3 DATA DIRECTORY="/mnt/p3/data"
);
```

### Key 分区

key 分区算是hash分区的加强版

- Key 分区支持任何字段类型。
- Key 分区在创建时可以不指定主键。
  - 它会默认选中数据表中非空的唯一字段作为切分字段

```mysql
CREATE TABLE t_key_1(
	id INT NOT NULL,
	name VARCHAR(200) NOT NULL,
	job VARCHAR(20) NOT NULL,
	PRIMARY KEY(id,job)
)
PARTITION BY KEY(job) PARTITION 2(
	PARTITION p0 DATA DIRECTORY="/mnt/p0/data",
	PARTITION p1 DATA DIRECTORY="/mnt/p1/data",
	PARTITION p2 DATA DIRECTORY="/mnt/p2/data",
	PARTITION p3 DATA DIRECTORY="/mnt/p3/data"
);
```

------

## 表分区的小操作

### 查询各分区行数

```mysql
SELECT 
	PARITION_NAME,TABLE_ROWS
FROM information_schema.`PARTITIONS`
WHERE
	TABLE_SCHEMA=SCHEMA() AND TABLE_NAME="tablename";
```

### 管理表分区

#### 创建表分区

```mysql
ALTER TABLE t_range_1 PARTITION BY RANGE(id)(
	PARTITION p0 VALUES LESS THAN(10000000),
	PARTITION p1 VALUES LESS THAN(20000000),
	PARTITION p2 VALUES LESS THAN(30000000),
	PARTITION p3 VALUES LESS THAN(40000000)
);
```



#### 新增表分区

```mysql
ALTER TABLE t_range_1 ADD PARTITION(
	PARTITION p4 VALUES LESS THAN (50000000) DATA DIRECTORY="/mnt/p4/data"
);
```

#### 删除原有表分区

```mysql
ALTER TABLE t_range_1 DROP PARTITION p3,p4;
```

#### 拆分原有表分区

```mysql
ALTER TABLE t_range_1 REORGANIZE PARTITION p0 INTO (
	PARTITION s0 VALUES LESS THAN (5000000) DATA DIRECTORY="/mnt/s0/data",
	PARTITION s1 VALUES LESS THAN (10000000) DATA DIRECTORY="/mnt/s1/data"
);
```

#### 表分区合并

```MYSQL
ALTER TABLE t_range_1 REORGANIZE PARTITION s0,s1 INTO (
	PARTITION p0 VALUES LESS THAN (10000000)
);
```

#### 移除表分区

数据不会丢失。

```MYSQL
ALTER TABLE t_range_1 REMOVE PARTITIONING;
```

### 子分区

- 子分区就是在已有的分区上再创建分区切分数据
- 目前只有RANGE和LIST分区可以创建子分区，而且子分区只能是HASH或者KEY分区

#### 语法1

```MYSQL
CREATE TABLE t_range_1(
	id INT UNSIGNED,
	name VARCHAR(200) NOT NULL,
	province_id INT NOT NULL,
	PRIMARY KEY(`id`,`province_id`,name)
)
PARTITION BY RANGE(province_id)
SUBPARTITION BY KEY(name) SUBPARTITIONS 4
(
	PARTITION p0 VALUES LESS THAN(10) DATA DIRECTORY="/mnt/p0/data",
	PARTITION p1 VALUES LESS THAN(20) DATA DIRECTORY="/mnt/p1/data",
	PARTITION p3 VALUES LESS THAN MAXVALUE DATA DIRECTORY="/mnt/p3/data"
);
```

#### 语法2

```MYSQL
CREATE TABLE t_range_1(
	id INT UNSIGNED,
	name VARCHAR(200) NOT NULL,
	province_id INT NOT NULL,
	PRIMARY KEY(`id`,`province_id`,name)
)
PARTITION BY RANGE(province_id) SUBPARTITION BY KEY(name)
(
	PARTITION p0 VALUES LESS THAN(10) DATA DIRECTORY="/mnt/p0/data" (SUBPARTITION s0,SUBPARITION s1),
	PARTITION p1 VALUES LESS THAN(20) DATA DIRECTORY="/mnt/p1/data"(SUBPARTITION s2,SUBPARITION s3),
	PARTITION p3 VALUES LESS THAN MAXVALUE DATA DIRECTORY="/mnt/p3/data" (SUBPARTITION s4,SUBPARITION s5)
);
```

