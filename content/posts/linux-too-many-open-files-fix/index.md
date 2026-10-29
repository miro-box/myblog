---
# ==================== 必填（3 项）====================
title: "凌晨两点收到 502 告警，最后查出来是文件描述符不够用"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-02-23T17:56:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从 nginx 报 Too many open files 开始，一路查到 ulimit、systemd 的 LimitNOFILE 和 worker_connections 三处限制。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Linux"
    - "Nginx"
    - "系统调优"
    - "排错"

# ==================== 封面图（用不到就保持注释）====================
# 方式 A（推荐）：图片和文章放同一文件夹（Page Bundle），文件名 cover.webp
image: "cover.webp"
# 方式 B：图片放在 static/images/ 下
# image: "/images/cover.webp"

# ==================== 可选（不需要就整行删掉）====================
toc: true                                      # 显示文章目录：true / false（短文可关）
# math: true                                   # 需要写数学公式时打开
# license: ""                                  # 单篇版权声明，留空=用站点默认
# lastmod:                                     # 最后修改时间。例：2026-10-23T21:00:00+08:00
# weight: 1                                    # 排序权重，数字越小越靠前（置顶用）
hidden: false                                  # true=不出现在首页/列表，但链接仍可访问
comments: false                                 # 是否开启评论：true / false
---

手机在枕头边上震了两下。我摸起来看了一眼，是监控发的，`blog.mibase.top 返回 502`。

当时是凌晨两点十分。我第一反应是想装死，第二天早上再说。但那台机器上还挂着别的东西，万一是一起挂了，拖到早上就麻烦。

爬起来开电脑，连上去看。

## 现象

```bash
systemctl status nginx
```

状态是 `active (running)`，但错误日志里一直在刷：

```text
2025/02/23 02:08:41 [alert] 8123#8123: *55123 open() "/var/log/nginx/access.log" failed (24: Too many open files)
2025/02/23 02:08:41 [crit] 8123#8123: *55124 open() "/srv/www/blog/public/index.html" failed (24: Too many open files)
```

`Too many open files`，这个报错我见过，但一直以为离自己很远。

## 什么是文件描述符

Linux 里一切皆文件。不只是磁盘上的文件，网络连接、管道、设备、socket，在内核眼里都是一个文件，用一个整数来标识，叫文件描述符，简称 fd。

每个进程能同时打开多少个 fd，是有上限的。这个上限来自三个地方，一层压一层。

最外面那层是内核的全局上限，`/proc/sys/fs/file-max`，一般很大，几十万，通常不会撞到。

往里一层是用户级限制，`ulimit -n`，这个是每个登录会话的限制。

最里面是进程自己的限制，从父进程继承，可以用 `prlimit` 查看。

nginx 作为服务跑，它继承的是 systemd 给它的限制，而不是我 SSH 登录之后的 `ulimit`。这一点很关键，后面会说。

## 先看当前值

```bash
# 当前会话
ulimit -n

# nginx 主进程的实际限制
sudo cat /proc/$(pgrep -o nginx)/limits | grep 'open files'

# 系统全局
cat /proc/sys/fs/file-max

# 系统当前用了多少
cat /proc/sys/fs/file-nr
```

我那次查出来，nginx 的限制是 `1024`。

1024 这个数字是老系统的默认值，现在看着确实小。nginx 每个连接要占两个 fd，一个给客户端，一个给上游。1024 意味着理论上最多五百个并发连接，实际还要留一些给日志文件、监听 socket，能用的更少。

我那个站平时并发不高，但那天晚上有人在爬，连接数上去了，直接撞到天花板。

## 改系统级限制

`/etc/security/limits.conf` 是老办法：

```text
*    soft nofile 65535
*    hard nofile 65535
```

这个文件只对通过 PAM 登录的会话生效，也就是 SSH 登录、`su` 这些。对 systemd 服务不一定管用，因为 systemd 启动服务的时候不走 PAM 的 limits 那一套。

所以还得改 systemd 的配置。

`/etc/systemd/system.conf` 或者针对单个服务写 override：

```bash
sudo mkdir -p /etc/systemd/system/nginx.service.d
sudo tee /etc/systemd/system/nginx.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=65535
EOF
```

然后：

```bash
sudo systemctl daemon-reload
sudo systemctl restart nginx
```

验证：

```bash
sudo cat /proc/$(pgrep -o nginx)/limits | grep 'open files'
```

应该显示 `65535`。

## 还有一层：systemd 自己的默认值

Debian 12 和 Ubuntu 22.04 之后，systemd 有个 `DefaultLimitNOFILE` 的默认值，是 `1024:524288`。意思是软限制 1024，硬限制 524288。

也就是说，如果你不显式设置，服务拿到的软限制还是 1024，硬限制虽然是 524288，但进程不会自己去把它调高。

这就是为什么很多人改了 `limits.conf` 之后发现没效果。服务是通过 systemd 起的，不走 PAM。

`/etc/systemd/system.conf` 里可以全局改：

```ini
[Manager]
DefaultLimitNOFILE=65535
```

改完 `daemon-reload`，然后重启所有服务才生效。我一般不改全局，只给需要的服务单独写 override，影响面小一点。

## nginx 自己的配置也要改

系统限制放开了，nginx 的配置里还有一个上限。

```nginx
events {
    worker_connections 1024;
}
```

这个值决定了单个 worker 能同时处理多少个连接。

worker 的数量是 `worker_processes`，一般设成 CPU 核数或者 `auto`。总的并发能力大致是 `worker_processes × worker_connections`。

我把这两个都调了：

```nginx
worker_processes auto;

events {
    worker_connections 8192;
    multi_accept on;
    use epoll;
}
```

`multi_accept on` 让一个 worker 一次接受多个新连接，高并发下能减少系统调用。

`use epoll` 在 Linux 上是默认值，写出来只是为了明确。BSD 系才需要 `kqueue`。

注意，`worker_connections` 不能超过 `LimitNOFILE`。如果系统限制是 1024，你写 8192 也没用，nginx 启动的时候会警告，实际还是被卡在 1024。

## 一个容易忽略的点：日志文件

nginx 每个 worker 都要打开 access.log 和 error.log。如果开了很多虚拟主机，每个都有自己的日志文件，这个数字会累积。

我那次有七个站点，每个两套日志，加上主配置的，一共十五个文件。乘以 worker 数，就是几十个 fd。虽然不多，但在接近上限的时候，这就是压死骆驼的最后一根稻草。

解决办法是减少日志文件数量，或者用 `access_log off` 关掉不需要的。我把几个不重要的站的 access log 关了，只留 error log。

## 排查当时到底谁在占

改配置之前，我想先确认一下是不是真的连接数暴涨。

```bash
ss -s
```

输出里有个 `TCP: 1234 (estab 890, closed 210, orphaned 0, timewait 130)`。890 个 established，对于那个站来说确实异常。

再看是谁：

```bash
ss -tn state established '( sport = :443 )' | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head
```

有一个 IP 占了三百多个连接。看 User-Agent，是一个很老的爬虫标识，明显是伪造的。

临时封掉：

```bash
sudo iptables -I INPUT -s <IP> -j DROP
```

连接数立刻下来了。但这只是止血，根本问题还在。

## 后来做的几件事

最直接的是给 nginx 加连接数限制：

```nginx
limit_conn_zone $binary_remote_addr zone=addr:10m;

server {
    limit_conn addr 20;
    limit_conn_status 429;
}
```

单个 IP 最多二十个并发连接，超了直接 429。这个比事后封 IP 有效得多。

另一个是 keepalive 的超时。默认 `keepalive_timeout 75s`，意味着一个空闲连接要占着 fd 七十五秒。我改成 20 秒：

```nginx
keepalive_timeout 20s;
keepalive_requests 100;
```

`keepalive_requests` 是单个连接最多处理多少个请求，到了就关。默认是 1000，对于被爬的情况，调小能让连接更快轮换出去。

最后是把 `LimitNOFILE` 写进了所有需要高并发的服务，不只是 nginx。MariaDB、Redis 这些也都有各自的连接数上限，同样受这个限制。

## 怎么验证改对了

改完之后，我用 `ab` 压了一下：

```bash
ab -n 5000 -c 200 https://blog.mibase.top/
```

`-c 200` 是两百个并发。跑的时候盯着 fd 数量：

```bash
watch -n 1 'ls /proc/$(pgrep -o nginx)/fd | wc -l'
```

这个数字应该随着并发上去，压测结束后回落到一个稳定的值，不报错就说明改对了。

如果还是报 `Too many open files`，那就是某一层的限制没改到位，按 `ulimit` → systemd override → nginx 配置这个顺序再检查一遍。

## 一点延伸

这个限制不只在 nginx 上有。

MySQL 的 `open_files_limit`、Redis 的 `maxclients`、Java 应用的 socket 数量，最后都会落到这个 fd 上限上。

还有一个容易被忽略的，就是 Docker 容器。容器里的进程继承的是宿主机的限制，但如果你在 compose 里没设，拿到的可能是 Docker daemon 的默认值。可以在 compose 里显式指定：

```yaml
services:
  app:
    ulimits:
      nofile:
        soft: 65535
        hard: 65535
```

这个写法比在容器里改 `/etc/security/limits.conf` 靠谱，因为容器里那个文件经常不生效。

## 现在

那天晚上折腾到快四点。改完配置，压测通过，才回去睡。

现在这台机器的 `LimitNOFILE` 是 65535，nginx 的 `worker_connections` 是 8192。跑了几个月，没再出过这个问题。

回头看，这个故障本身不复杂，但它的排查过程逼着我把 Linux 的资源限制体系理了一遍。fd 上限、ulimit、PAM、systemd、cgroup，这几层的关系搞清楚之后，很多类似的问题都能举一反三。

运维这件事，最怕的不是不懂，是以为自己懂。
