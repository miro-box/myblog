---
# ==================== 必填（3 项）====================
title: "20G 的硬盘被 Docker 吃干净了，我把清理这件事理顺了"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-05-22T10:46:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从磁盘告警到定位到 Docker 占了多少，再把镜像、容器、卷和构建缓存一层层清掉，顺带说说哪些不能乱删。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Docker"
    - "磁盘清理"
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

那天早上是被监控机器人的 Telegram 消息震醒的。

`[WARN] rootfs usage 92%`，我那台 20G 硬盘的小机器。前一天晚上看还是 78%，一夜之间涨了十几个点。

登上去 `df -h` 一看，`/` 确实快满了。但奇怪的是，`du -sh /var/lib/docker` 只有 9 个多 G，和我印象里的数字差不多。真正占地方的东西藏在哪儿了。

这次排查让我把 Docker 的磁盘占用彻底搞清楚了一遍，记下来。

## 先搞清楚它到底占了多少

```bash
docker system df -v
```

这个命令比 `docker system df` 详细得多，它会把镜像、容器、本地卷、构建缓存四类分开列，每一类还列出具体的条目和大小。

我第一次跑出来的结果是这样的：

```text
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          42        9         18.6GB    13.2GB (71%)
Containers      11        8         210MB     180MB (85%)
Local Volumes   17        6         3.1GB     1.4GB (45%)
Build Cache     88        0         2.4GB     2.4GB
```

十八个 G 的镜像，只有九个是活跃的。这就是问题所在。

我这两年在同一台机器上试过太多东西，什么 GitLab、Drone、MinIO、各种数据库版本，装完觉得不好用就 `docker compose down` 了，容器没了，镜像还躺在那儿。每个都几百兆，攒起来就是十几个 G。

## 镜像怎么清

最直接的是清掉那些没有标签的悬空镜像：

```bash
docker image prune
```

它只会删掉 `<none>:<none>` 那种，也就是构建过程中产生的中间层，或者被新版本顶掉标签的旧镜像。这个操作是安全的，因为没有任何容器在用它们。

如果想连"有标签但没有容器使用"的一起删：

```bash
docker image prune -a
```

这个就要小心了。它会问你确认，确认之后把所有没被容器引用的镜像全删掉。我当时脑子一热跑了这个，结果把我准备好的 `mariadb:10.11` 也删了。虽然能重新拉，但那台机器的网络拉大镜像很慢，花了十几分钟。

后来我的做法是先看清单再决定：

```bash
docker image ls --filter "dangling=false" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
```

按创建时间排序，心里有个数，再挑着删。

单个删：

```bash
docker image rm <IMAGE_ID>
```

如果提示被容器引用，先看是哪个容器：

```bash
docker ps -a --filter ancestor=<IMAGE_ID>
```

## 容器和它的可写层

`docker ps -a` 里那些 `Exited` 状态的容器，很多人以为删了容器就干净了，其实容器本身的可写层也占空间。

```bash
docker container prune
```

这个只删已停止的容器。有几点要提醒。

容器删了，它的可写层就没了。如果你在容器里手动改过什么文件、装过什么包，没写进镜像也没挂载出来，那部分就彻底丢了。我之前有个容器，为了图省事直接在里面 `apt install` 了个工具，后来 prune 一跑，第二天发现功能没了，又得重来一遍。

所以正确做法是，要么写进 Dockerfile，要么挂载出来，别指望容器的可写层能长期保存东西。

## 数据卷是最需要小心的一类

```bash
docker volume prune
```

这个命令删的是"没有被任何容器引用"的卷。听起来很安全，实际上有个陷阱。

我那次跑完之后，发现一个早就停掉的测试容器的数据卷被删了。虽然那个容器本来也没用了，但里面存着我早期的一些实验数据。删掉之后想找回来是不可能了。

所以我的建议是，跑之前先列出来看看：

```bash
docker volume ls --filter "dangling=true"
```

确认这些名字你都不认识、也不想要，再执行 prune。

更稳的做法是一个一个删：

```bash
docker volume rm <VOLUME_NAME>
```

麻烦，但至少你知道自己删了什么。

还有一种情况要注意。如果卷的名字是 Compose 自动生成的（形如 `项目名_卷名`），你 `docker compose down` 的时候不加 `-v`，卷是会保留的。加了 `-v` 就会连卷一起删。这个 `-v` 我在文档里看到过好几次，但真正记住是在一次误操作之后。

## 构建缓存：最容易被忽略的大头

这个是我这次排查才发现的大户。

```bash
docker builder prune
```

它会删掉 BuildKit 的缓存。现在的 Docker 默认用 BuildKit，每次 `docker build` 都会把中间层缓存下来，下次构建能复用。这个机制很好，但缓存不会自己过期，越攒越多。

我那次看到 2.4G，基本上都是几个月前折腾某个项目留下的。

想连所有缓存一起清：

```bash
docker builder prune -a
```

`-a` 是 all，包括那些还在被引用的缓存。清完之后下次构建会慢一些，但空间能立刻回来。

还有个带时间过滤的用法，我觉得挺实用：

```bash
docker builder prune --filter "until=168h"
```

只删七天以前的。这样常用的缓存还能留着，老的自然淘汰。

## 一键清理，以及为什么我不推荐

网上到处都写着这条：

```bash
docker system prune -a --volumes
```

它会把停止的容器、没用的网络、所有没被引用的镜像、所有没被引用的卷、所有构建缓存，一次性全清掉。

确实爽，我那次跑完从 92% 降到了 51%。

但我不推荐把它当成日常操作。原因有三个。

它不问你就删卷。数据卷里可能有你还没意识到重要的东西。

它把镜像全清了。下次起服务要重新拉，如果网络不好，等于给自己挖坑。

它不区分环境。你在开发机上跑和在跑着线上服务的机器上跑，风险完全不一样。我有一次在生产机上顺手跑了，把一个还没启动但准备切换的旧版本镜像删了，回滚的时候抓瞎。

## 我现在的固定动作

经过这次，我给自己定了一套流程，每个月做一次。

先看占用：

```bash
docker system df -v
```

然后按风险从低到高依次清：

```bash
docker container prune -f
docker image prune -f
docker builder prune -f --filter "until=336h"
```

这三条都是只删"明确没用"的东西，相对安全。卷我单独处理，先 `docker volume ls --filter dangling=true` 看清单，确认了再手动删。

再加上一条，给日志设上限。这个比清理更治本。Docker 默认的 json-file 驱动不限制大小，一个话多的服务能写到几个 G。我在每个 compose 文件里都加了：

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

这样单个容器最多占 30M 日志，怎么跑都撑不爆。

## 顺手发现的一个问题

清理的时候我注意到 `/var/log` 下面也有几个 G。是 journald 的日志，默认能占到磁盘的 10%。

```bash
journalctl --disk-usage
```

看到是 1.8G。我改了 `/etc/systemd/journald.conf`：

```ini
SystemMaxUse=200M
```

然后 `systemctl restart systemd-journald`，空间立刻回来了。

这个问题和 Docker 没关系，但它们是同一类问题，都是"某个东西默认不限制自己，跑久了就把盘吃满"。清理只是补救，设上限才是根治。

## 现在的状态

清完之后稳定在 55% 左右，跑了两个月没再告警。

我也顺手在监控里加了一条，磁盘超过 80% 就推消息。这次是被 92% 才叫醒的，有点晚。早点知道，处理起来从容得多。

回头看，这件事本身没什么技术含量，真正花时间的是搞清楚哪些能删、哪些不能。Docker 把很多东西藏起来了，`system df -v` 这个命令就是那把钥匙。知道东西在哪儿，才谈得上管理。
