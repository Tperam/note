# go disruptor

这是一个基于java的disruptor开发的框架。

该框架主要应对的是多线程通讯的模块。也就对应我们golang中的channel。

其主要思想是通过通信，以一种传递的方式来共享内存。减少内存中的争夺。也就是我们的CSP（ Communicating Sequential Processes 顺序通信进程）思想。



### channel



### go disruptor

其主要思想为java的无锁化编程，可用于减少系统锁的开销。但其随之而来的是cpu的开销，因为每个在等待的线程都是通过自旋尝试获取相应的执行权。

同时 go disruptor 为分块执行的思想，比如，当来了一批数据，他会分一批给A reader，另一批给 B reader。

