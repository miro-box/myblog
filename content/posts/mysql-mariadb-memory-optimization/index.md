---
# ==================== 必填（3 项）====================
title: "1G 内存的小机器跑 MariaDB，我把能省的都省了"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-04-03T04:28:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从被 OOM killer 打死到稳定运行，逐个调整 innodb_buffer_pool、连接数和临时表，把 MariaDB 的内存压到 200M 以内。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "MariaDB"
    - "MySQL"
    - "性能调优"
    - "Linux"

# ==================== 封面图（用不到就保持注释）====================
# 方式 A（推荐）：图片和文章放同一文件夹（Page Bundle），文件名 cover.jpg
image: "cover.jpg"
# 方式 B：图片放在 static/images/ 下
# image: "/images/cover.jpg"

# ==================== 可选（不需要就整行删掉）====================
toc: true                                      # 显示文章目录：true / false（短文可关）
# math: true                                   # 需要写数学公式时打开
# license: ""                                  # 单篇版权声明，留空=用站点默认
# lastmod:                                     # 最后修改时间。例：2026-10-23T21:00:00+08:00
# weight: 1                                    # 排序权重，数字越小越靠前（置顶用）
hidden: false                                  # true=不出现在首页/列表，但链接仍可访问
comments: false                                 # 是否开启评论：true / false
---

手里有台很便宜的 VPS，1 核 1G，一年一百多块。上面跑着一个小论坛，用户不多，但数据库不能少。

装完 MariaDB 之后，我 `free -h` 看了一眼，可用内存只剩三百多兆。系统自己占了点，MariaDB 占了将近五百兆。

当时没太在意，觉得还能跑。结果第三天凌晨，机器挂了。

## 先看是怎么死的

```bash
journalctl -k --since "yesterday" | grep -i 'out of memory'
```

```text
Out of memory: Killed process 812 (mariadbd) total-vm:1024000kB, anon-rss:520000kB
```

OOM killer 干的。MariaDB 吃到 520M，加上系统的，超过物理内存，内核直接把它杀了。

有意思的是，杀完之后 systemd 又把它拉起来，然后继续涨，第二天再杀一次。这就是为什么我早上起来发现论坛打不开，但服务状态显示 running。

## 内存都花在哪儿了

MariaDB 的内存占用分几块，得先搞清楚再动手。

```sql
SHOW ENGINE INNODB STATUS\G
```

输出里的 `BUFFER POOL AND MEMORY` 那一段，能看到 buffer pool 的实际大小。

```sql
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_log_buffer_size';
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'tmp_table_size';
SHOW VARIABLES LIKE 'max_heap_table_size';
SHOW VARIABLES LIKE 'sort_buffer_size';
SHOW VARIABLES LIKE 'join_buffer_size';
SHOW VARIABLES LIKE 'read_buffer_size';
SHOW VARIABLES LIKE 'read_rnd_buffer_size';
```

我查出来的默认值是这样的：

```text
innodb_buffer_pool_size    134217728    (128M)
innodb_log_buffer_size     16777216     (16M)
max_connections            151
tmp_table_size             16777216     (16M)
max_heap_table_size        16777216     (16M)
sort_buffer_size           2097152      (2M)
join_buffer_size           262144       (256K)
read_buffer_size           131072       (128K)
read_rnd_buffer_size       262144       (256K)
```

看着每一项都不大，但问题是，`sort_buffer_size`、`join_buffer_size` 这些是每个连接独占的。151 个连接乘上 2M 的 sort buffer，理论上就是 300M。虽然实际不会所有连接都用到满，但这个乘数关系很吓人。

## 改配置

MariaDB 的配置我放在 `/etc/mysql/mariadb.conf.d/99-small.cnf`，这样不会被升级覆盖。

```ini
[mysqld]
# 内存相关的核心参数
innodb_buffer_pool_size = 64M
innodb_log_buffer_size = 8M
innodb_buffer_pool_instances = 1

# 连接数
max_connections = 30
max_user_connections = 25
thread_cache_size = 4
table_open_cache = 64
table_definition_cache = 256

# 每个连接的缓冲区，越小越好
sort_buffer_size = 256K
join_buffer_size = 256K
read_buffer_size = 128K
read_rnd_buffer_size = 256K
tmp_table_size = 16M
max_heap_table_size = 16M

# 日志和刷盘
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_log_file_size = 32M

# 关掉用不到的功能
performance_schema = OFF
innodb_stats_on_metadata = OFF
```

一条条说。

`innodb_buffer_pool_size` 是最大的一块。它是 InnoDB 的缓存池，索引和数据页都放里面。默认 128M 对 1G 的机器太大了，我改成 64M。这个值的经验法则是物理内存的百分之五十到七十，但在小内存机器上，得先保证系统和其他服务能活。

`innodb_buffer_pool_instances` 默认会按 buffer pool 大小自动分，分成多个实例能减少锁竞争。但在 64M 这个量级，分成多个反而浪费，因为每个实例有自己的最小页数。设成 1 就行。

`max_connections` 从 151 降到 30。这个小论坛日常在线不到十个人，三十个连接足够。这个改动省下的不是连接本身，而是每个连接的缓冲区乘数。

`thread_cache_size` 是缓存的线程数。连接断开之后线程不立刻销毁，留着给下一个连接用。设成 4 意味着常驻四个空闲线程，占的内存不多，但能减少频繁创建销毁的开销。

`performance_schema` 这个功能是用来做性能分析的，很强大，但默认开着会占不少内存，大概几十兆。小站用不上，关掉。

`innodb_flush_log_at_trx_commit = 2` 这个要谨慎。它控制事务提交时怎么刷日志。

设成 1 是最安全的，每次提交都刷盘，保证不丢数据。设成 2 是每秒刷一次，性能好很多，但极端情况下可能丢一秒的数据。设成 0 是交给操作系统，最不安全。

小论坛丢一秒的数据可以接受，我选了 2。如果你的业务涉及钱，别改这个。

`innodb_flush_method = O_DIRECT` 让 InnoDB 绕过操作系统的页缓存，直接写磁盘。这样同一份数据不会在内存里存两遍。小内存机器上这个能省下可观的空间。

## 重启之后看效果

```bash
sudo systemctl restart mariadb
free -h
```

改完 MariaDB 占了 180M 左右，比之前的 520M 小了一大截。

再看一下实际的 buffer pool：

```sql
SELECT
  POOL_SIZE * 16 / 1024 / 1024 AS buffer_pool_mb
FROM information_schema.INNODB_BUFFER_POOL_STATS;
```

确认是 64M。

## 一个更细的观察方法

`free -h` 只能看到整体，想看每个进程实际用了多少：

```bash
ps -eo pid,comm,rss,vsz --sort=-rss | head -10
```

`rss` 是实际占用的物理内存，`vsz` 是虚拟内存。看 `rss` 才有意义，`vsz` 包含了大量没有真正分配的地址空间。

还可以看 MariaDB 自己的内存统计：

```sql
SHOW STATUS LIKE 'Innodb_buffer_pool_bytes_data';
SHOW STATUS LIKE 'Innodb_buffer_pool_pages_free';
```

`pages_free` 如果一直是 0，说明 buffer pool 不够用，可以适当调大。如果有一半以上是空闲的，说明给多了。

我观察了一周，`pages_free` 稳定在 40% 左右，说明 64M 是合适的。

## swap 要不要开

这个问题争论很多。

我的看法是，小内存机器一定要开一点。不是因为 swap 能提升性能，而是因为它能在内存尖峰的时候给你一个缓冲，避免进程被直接杀掉。

我配了 1G 的 swap：

```bash
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

然后调一下 swap 的使用倾向：

```bash
sudo sysctl vm.swappiness=10
```

默认是 60，意思是内存还有富余的时候就开始往 swap 里挪。设成 10 让它尽量先用物理内存，真的不够了才用 swap。

这个值我写在 `/etc/sysctl.d/99-swap.conf` 里，重启也生效。

不过要提醒一句，如果你的 VPS 用的是机械盘或者网络存储，swap 的性能会很差，用到 swap 的时候整个系统会卡住。这种情况得权衡。

## 慢查询日志

内存调小了，可能会有些查询变慢，因为 buffer pool 小了，缓存命中率下降。

开个慢查询日志观察：

```ini
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
```

跑一周，看看有没有超过两秒的查询。有的话，先优化 SQL，加索引，比加内存便宜。

我那台机器上确实发现了两条，一条是论坛的帖子列表，没走索引，全表扫描。加了复合索引之后，从三秒降到几十毫秒。

这个收益比调参数大得多。

## 还有一个坑：临时表

`tmp_table_size` 和 `max_heap_table_size` 这两个值要设成一样。

原因是有个隐藏的行为。内存临时表的大小受这两个值里较小的那个限制。如果不一样，实际生效的是小的那个，你改大的那个没用。

我一开始只改了 `tmp_table_size`，改成 64M，结果发现没效果，因为 `max_heap_table_size` 还是 16M。

另外，临时表超过这个大小之后，会转成磁盘临时表。磁盘临时表慢很多，但至少不会把内存撑爆。所以这两个值别设太大，16M 到 32M 就够了。

## 长期观察

调完到现在跑了三个多月，没再被 OOM 杀过。

```bash
free -h
```

现在的样子：

```text
               total        used        free      shared  buff/cache   available
Mem:           979Mi       412Mi       102Mi       8.0Mi       464Mi       512Mi
Swap:          1.0Gi        12Mi       1.0Gi
```

MariaDB 稳定在 180M 左右，swap 只用了 12M，基本没动。

`available` 有 512M，说明还有余量。这个指标比 `free` 更有参考价值，因为它把可回收的缓存也算进去了。

## 一点心得

小内存机器上跑数据库，核心思路是"知道自己需要多少，然后只给这么多"。

默认配置是为通用场景设计的，它假设你有足够的内存。在 1G 的机器上，这些默认值就是灾难。

调参的顺序应该是，先降 `max_connections`，因为它带来的乘数效应最大；再降 `innodb_buffer_pool_size`，这是单项最大的一块；最后调各种 per-connection 的缓冲区。

调完之后别急着走，观察几天，看 buffer pool 的命中率和 free 页面数，再微调。

还有一点，如果你的库真的很小，比如就几兆数据，那其实可以考虑 SQLite。省掉整个数据库进程，内存占用直接降到几兆。我这个论坛是因为要用全文检索和并发写，才留着 MariaDB。
