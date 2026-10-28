---
# ==================== 必填（3 项）====================
title: "机器越来越多之后，我给每一台都挂上了探针"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-08-02T23:55:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "用 Uptime Kuma 把几台 VPS、几个站点和几个端口都监控起来，配好 Telegram 通知，还顺手接了几个 Push 类型的心跳。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Uptime Kuma"
    - "监控"
    - "Docker"
    - "Telegram"

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

我一直没有正经的监控。

出问题的时候，是我自己发现网站打不开，然后上去看。或者更糟，是朋友告诉我"你博客挂了"。

有几次是证书过期，有一次是数据库满了导致写不进去，还有一次是 nginx 的 worker 全挂了。每一次都是被动发现，中间可能已经挂了好几个小时。

后来在 NodeSeek 上看到有人推荐 Uptime Kuma，说是自托管的监控面板，界面好看，配置简单。我花了一个晚上装起来，之后就没再被"你博客挂了"这种消息尴尬过。

## 装

Docker Compose，目录 `/srv/uptime-kuma`：

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    volumes:
      - ./data:/app/data
    ports:
      - "127.0.0.1:3001:3001"
    environment:
      TZ: Asia/Shanghai
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

```bash
docker compose up -d
```

端口只绑 `127.0.0.1`，外面通过 nginx 反代进来。

## nginx 反代

Uptime Kuma 用 WebSocket 做实时更新，反代的时候要配 upgrade：

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name status.mibase.top;

    ssl_certificate     /etc/letsencrypt/live/status.mibase.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/status.mibase.top/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

`proxy_read_timeout` 设长一点。WebSocket 是长连接，如果超时太短，连接会被反复断开重连，页面上的状态会一闪一闪。

## 进去之后

打开 `https://status.mibase.top`，会让你创建管理员账号。

建完就进到主界面。左边是监控列表，右边是状态页。

上手先加一个监控。点左上角的"添加新监控"。

监控类型有十几种，HTTP、TCP、Ping、DNS、关键词、推送、证书过期，等等。

## HTTP 监控

最常用的是这个。

```text
监控类型：HTTP(s)
友好名称：博客
URL：https://blog.mibase.top
心跳间隔：60 秒
重试次数：2
请求超时：30 秒
```

`心跳间隔` 是多久检查一次。六十秒是个平衡点，太频繁会增加负担，太慢会延迟发现。

`重试次数` 是连续失败多少次才判定为故障。设成 2 意味着单次失败不算，连着两次失败才告警。这个能过滤掉偶尔的网络抖动。

还有一个"接受的状态码"，默认是 `200-299`。如果你的站会返回 304，得把它加进去。

进阶一点，可以用关键词监控。比如检查页面里有没有某个特定的字符串：

```text
监控类型：HTTP(s) - 关键词
关键词：明月小站
```

这样不只是检查服务器返回了 200，还检查内容是对的。有时候 nginx 返回了 200 但页面是空的，这种也能发现。

## 证书过期监控

这个是我觉得最实用的一个。

```text
监控类型：HTTP(s) - 关键词
URL：https://blog.mibase.top
```

其实不用单独配，Uptime Kuma 会自动检测 HTTPS 站点的证书剩余天数，显示在监控详情里。

但它默认不会因为证书快过期而告警。要单独加一个"证书过期"类型的监控：

```text
监控类型：证书过期
域名：blog.mibase.top
过期前通知天数：14
```

设成十四天，留够续期和排查的时间。

我配了这个之后，再也没遇到过证书过期。

## TCP 端口监控

有些服务没有 HTTP 接口，比如数据库、Redis、SSH。

```text
监控类型：TCP 端口
主机名：db.mibase.top
端口：3306
```

这个只检查端口能不能连上。连不上就告警。

我用它监控了 MariaDB 的 3306 和 SSH 的 2222。

## Ping 监控

检查机器本身活不活。

```text
监控类型：Ping
主机名：blog.mibase.top
```

这个用的是 ICMP。有些云厂商会禁 ICMP，那就用 TCP 端口替代。

## Docker 容器监控

Uptime Kuma 有个 Docker 类型的监控，可以检查容器是否在运行。

但有个前提，Uptime Kuma 这个容器要能访问宿主机的 Docker socket：

```yaml
    volumes:
      - ./data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

`:ro` 是只读挂载。这个很重要，因为 docker.sock 相当于宿主机的 root 权限，只读能减少风险。

不过即便如此，能访问 docker.sock 的容器仍然是很危险的。我的做法是只在监控服务器上开这个，业务服务器上不装 Uptime Kuma。

## 推送监控

这个类型有点特别，方向是反的。

其他监控是 Uptime Kuma 主动去检查目标。推送监控是目标主动向 Uptime Kuma 报告"我还活着"。

新建一个推送监控，它会给你一个 URL：

```text
https://status.mibase.top/api/push/xxxxxxxx
```

然后你在目标机器上加一个定时任务：

```bash
curl -fsS -m 10 --retry 5 -o /dev/null https://status.mibase.top/api/push/xxxxxxxx
```

如果 Uptime Kuma 在一段时间内没收到这个请求，就判定为故障。

这个特别适合备份任务。比如你的备份脚本每天跑一次，跑完就推一下。如果哪天没推，说明脚本没跑或者跑失败了。

我的备份脚本里就加了这个：

```bash
curl -fsS -m 10 --retry 5 -o /dev/null \
  "https://status.mibase.top/api/push/xxxxxxxx?status=up&msg=OK&ping="
```

## 通知

监控没有通知等于没监控。

Uptime Kuma 支持几十种通知方式，Telegram、邮件、Webhook、企业微信、钉钉，等等。

我用的是 Telegram，配置最简单。

先在 Telegram 里找 `@BotFather`，发 `/newbot`，按提示建一个 bot，拿到 token。

然后找 `@userinfobot`，发一条消息，它会告诉你你的 chat id。

在 Uptime Kuma 的设置里，通知，新建：

```text
通知类型：Telegram
Bot Token：123456:ABC-DEF...
Chat ID：123456789
```

点"测试"，如果 Telegram 里收到消息就说明配好了。

## 告警的降噪

通知配好之后，最先冒出来的问题是太吵。

网络抖一下，收到一条。服务重启，收到一条。半夜三点被吵醒，一看是误报。

Uptime Kuma 提供了几个手段。

`重试次数` 是最基础的。连续失败 N 次才告警。

还有一个"心跳间隔"的倍数，叫"重试间隔"。默认是心跳间隔的倍数，可以让重试之间隔得久一点。

另外可以在通知里设"仅在状态变化时通知"。这样故障恢复的时候会发一条，不会一直重复。

我的配置是，心跳间隔六十秒，重试两次，重试间隔六十秒。也就是说，从故障发生到告警，大概需要三分钟。这个延迟可以接受，换来的是极少的误报。

## 状态页

Uptime Kuma 可以生成一个公开的状态页，给用户看。

在设置里新建状态页，选要显示的监控，设一个路径，比如 `/status`。

然后访问 `https://status.mibase.top/status` 就能看到。

这个页面挺好看的，绿色是正常，红色是故障，还能显示最近一次的心跳延迟。

我给自己的几个站做了个公开状态页，虽然没什么人看，但自己看着舒服。

## 数据备份

Uptime Kuma 的所有配置都存在 SQLite 里，位置是 `/app/data/kuma.db`。

备份就是拷这个文件：

```bash
docker exec uptime-kuma sqlite3 /app/data/kuma.db ".backup '/app/data/backup.db'"
docker cp uptime-kuma:/app/data/backup.db ./kuma-backup-$(date +%F).db
```

注意要先 `.backup` 再拷，不能直接拷正在使用的 db 文件。

恢复就是把文件放回去，然后重启容器。

## 几个小问题

Uptime Kuma 的资源占用不大，一个监控大概占几兆内存。我有二十多个监控，整个容器占了一百多兆。

它的数据库会一直增长，因为每次心跳都记一条。跑久了文件会变大。可以在设置里开启"保留心跳数据的天数"，默认是无限。

有一次我发现监控页面加载很慢，查下来是数据库太大了。开了保留九十天之后，文件从两百多兆降到了三十多兆。

还有一个，如果你的监控目标也在同一台机器上，那机器挂了的时候，监控也跟着挂了，什么都监控不到。

所以我后来把 Uptime Kuma 放在了一台独立的机器上，监控其他所有机器。这样至少能保证监控本身是活的。

## 现在的状态

我现在的监控列表里有二十多项。

几个站点的 HTTP 可用性，几台 VPS 的 Ping，数据库和 SSH 的端口，几张证书的过期时间，还有备份任务的推送。

每天早上起来看一眼，全是绿的，心里就踏实。

这个工具最大的价值不是它能做什么高级的分析，而是它让我从"被动发现问题"变成了"主动知道状态"。这个转变看起来小，但对心态的影响很大。
