参考

> https://baijiahao.baidu.com/s?id=1709427910908845097&wfr=spider&for=pc
>
> 此文主要细讲了Next-key Lock相关，用于理解锁粒度问题

mysql 中

事务有4个

- Read Uncommitted
- Read Committed
- Reperatable Read
- Serializable



Read Uncommitted：在不同事务下，可读到互相未提交的数据

Read Committed：在不同事务下，可读到对方已经提交的数据

Reperatable Read: 在不同事务下，别的事务修改的数据不会影响到当前事务的查询（加锁查询除外）

Serializable：让事务序列化处理。



#### 避免死锁

避免死锁的方式

- 协定调用顺序

在同一张表里，一个事务可能会对多行进行操作，在这时候就有可能会出现死锁问题，例如

- A -> B 转账
- B -> A 转账

按照正常逻辑，将上面两个操作放在事务中，可能会出现

那么我们不如将需要操作的ID提取出来，并将操作的ID以升序排序后进行查询

例如，在执行修改前执行

```sql
BEGIN;
SELECT * FROM user_balance WHERE id = 'A' FOR UPDATE;
SELECT * FROM user_balance WHERE id = 'B' FOR UPDATE;
-- 各种操作...
COMMIT;
```

该顺序必须全局唯一，不能在同一张表中，一下用A列，一下用B列



