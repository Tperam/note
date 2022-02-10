

读取 CPU 信息 `/proc/stat`

> 好像是一个累加值，需要将上次值减掉。

```shell
cpu_data_new_total = fog_cpu_info.processor_used_info[index].user[curr] + \
   fog_cpu_info.processor_used_info[index].nice[curr] + \
   fog_cpu_info.processor_used_info[index].system[curr] + \
   fog_cpu_info.processor_used_info[index].idle[curr] + \
   fog_cpu_info.processor_used_info[index].softirq[curr] + \
   fog_cpu_info.processor_used_info[index].iowait[curr] + \
   fog_cpu_info.processor_used_info[index].irq[curr];

cpu_data_new_usage = fog_cpu_info.processor_used_info[index].user[curr] + \
    fog_cpu_info.processor_used_info[index].nice[curr] + \
    fog_cpu_info.processor_used_info[index].system[curr] + \
    fog_cpu_info.processor_used_info[index].softirq[curr] + \
    fog_cpu_info.processor_used_info[index].iowait[curr] + \
    fog_cpu_info.processor_used_info[index].irq[curr];
```



利用率：

```
cpu_data_new_usage / cpu_data_new_total
```



| cpu指标 | 含义                         |
| :------ | :--------------------------- |
| user    | 用户态时间                   |
| nice    | 用户态时间(低优先级，nice>0) |
| system  | 内核态时间                   |
| idle    | 空闲时间                     |
| iowait  | I/O等待时间                  |
| irq     | 硬中断                       |
| softirq | 软中断                       |



第一次统计

```
cpu  726192 2232 1009504 65053312 2950 0 3461 0 0 0
cpu0 95124 314 132216 8117929 244 0 262 0 0 0
cpu1 91868 489 127528 8127781 217 0 507 0 0 0
cpu2 90377 199 125678 8131905 650 0 549 0 0 0
cpu3 87246 246 119795 8138137 729 0 950 0 0 0
cpu4 85507 207 119901 8144759 240 0 510 0 0 0
cpu5 90383 150 126246 8135294 242 0 109 0 0 0
cpu6 93754 123 130804 8126354 414 0 240 0 0 0
cpu7 91930 501 127333 8131149 211 0 332 0 0 0
```

第二次统计 （隔了10几分钟）

```
cpu  746730 2233 1038196 66892104 3019 0 3566 0 0 0
cpu0 97897 314 136061 8347179 280 0 292 0 0 0
cpu1 94466 489 131148 8357577 223 0 522 0 0 0
cpu2 93020 199 129284 8361664 655 0 562 0 0 0
cpu3 89644 246 123088 8368331 733 0 966 0 0 0
cpu4 87957 207 123288 8375009 244 0 514 0 0 0
cpu5 92880 150 129866 8365255 247 0 113 0 0 0
cpu6 96382 123 134517 8356082 417 0 247 0 0 0
cpu7 94480 501 130942 8361003 216 0 347 0 0 0
```

第三次统计（隔了1分钟）

```
cpu  747191 2233 1038848 66933933 3020 0 3566 0 0 0
cpu0 97958 314 136146 8352400 281 0 292 0 0 0
cpu1 94525 489 131228 8362805 223 0 522 0 0 0
cpu2 93080 199 129362 8366885 655 0 562 0 0 0
cpu3 89708 246 123187 8373530 733 0 966 0 0 0
cpu4 88013 207 123360 8380253 244 0 514 0 0 0
cpu5 92936 150 129944 8370492 247 0 113 0 0 0
cpu6 96430 123 134585 8361338 418 0 247 0 0 0
cpu7 94538 501 131033 8366227 216 0 347 0 0 0
```

