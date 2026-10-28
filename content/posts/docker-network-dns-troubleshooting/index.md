---
# ==================== 必填（3 项）====================
title: "两个容器明明在同一个宿主机上，就是互相连不上"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-07-29T02:54:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "一次容器之间按名字连不上的排查，从默认 bridge 没有 DNS 讲到自定义网络，以及 embedded DNS 那些容易踩的细节。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Docker"
    - "网络排障"
    - "DNS"
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

有段时间我在搭一个小的内部工具，前端是一个 PHP 的容器，后端是一个 Redis 容器。两个都在同一台机器上，端口也都正常开着。

但 PHP 那边一连 Redis 就报错，`Connection refused`，或者更奇怪一点，`php_network_getaddresses: getaddrinfo failed`。

我当时的第一反应是，两个容器不是都在 `172.17.0.x` 这个网段吗，怎么可能连不上。

这个想法本身就是错的。花了小半个晚上才想明白问题出在哪，记一下。

## 先看清楚默认的 bridge 网络

我当时的启动命令大概是这样的：

```bash
docker run -d --name redis redis:7
docker run -d --name web -p 8080:80 php:8.2-apache
```

两条命令都没指定 `--network`，所以它们都跑在默认的 `bridge` 网络上。

`docker network inspect bridge` 看一眼：

```bash
docker network inspect bridge --format '{{json .Containers}}' | jq
```

两个容器确实都在里面，IP 分别是 `172.17.0.2` 和 `172.17.0.3`。

那我先进 web 容器里试一下：

```bash
docker exec -it web bash
ping 172.17.0.3
```

通。说明二层是通的，两个容器确实能互相访问。

```bash
ping redis
```

`ping: bad address 'redis'`

到这里问题就很清楚了。IP 能通，名字解析不了。

## 默认 bridge 没有内置 DNS

这是 Docker 里一个非常容易踩的点。

在默认的 `bridge` 网络上，Docker 是不提供自动服务发现的。容器之间只能通过 IP 通信，不能通过容器名。你想让 `redis` 这个名字能解析，得自己用 `--link`，而这个参数早就被标记成废弃了，官方文档里明确说不建议用。

那为什么我印象里"容器名可以互相访问"呢。

因为自定义网络可以。

只要你自己建一个 bridge 网络，Docker 就会给它启用一个内置的 DNS 服务器，所有接入这个网络的容器都会自动注册自己的名字。之后容器之间直接 `ping 服务名` 就能通。

这就是关键区别。默认 bridge 是个历史包袱，为了兼容早期的行为，它没开这个功能。

## 改成自定义网络

```bash
docker network create appnet
docker run -d --name redis --network appnet redis:7
docker run -d --name web --network appnet -p 8080:80 php:8.2-apache
```

再进 web 容器：

```bash
docker exec -it web bash -c "getent hosts redis"
```

这次输出 `172.18.0.2  redis`，解析成功了。

不过这里还有个细节。`ping` 在 `php:8.2-apache` 这个镜像里可能没装，`getent hosts` 更通用一些。`curl`、`nc` 这些也未必有，排查的时候先确认工具在不在。

## 内置 DNS 是怎么回事

Docker 在每个自定义网络的容器里塞了一个 `127.0.0.11` 的 DNS 服务器。你可以看一下容器里的 `/etc/resolv.conf`：

```bash
docker exec web cat /etc/resolv.conf
```

输出大概是：

```text
nameserver 127.0.0.11
options ndots:0
```

这个 `127.0.0.11` 是 Docker 的 embedded DNS。它拦截容器内的所有 DNS 查询，先查自己维护的一张表，也就是同一网络里其他容器的名字。查不到再转发给宿主机的 DNS 或者你在 `daemon.json` 里配的上游。

`ndots:0` 这个选项也有讲究。它决定了域名里有多少个点才被当成绝对域名。设成 0 意味着任何带点的名字都先当绝对域名查，不做 search domain 的拼接。这个值能减少很多无谓的查询延迟。

## 那我当初为什么连 IP 也失败过

前面说 IP 能 ping 通，但那是后来验证的。我最初遇到的报错是 `Connection refused`，这个和 DNS 没关系，是另一个问题。

Redis 的镜像默认只监听 `127.0.0.1`。这是从 Redis 3.2 开始的默认行为，官方镜像也继承了这个配置。也就是说，就算你从外面连得上这个容器的 IP，Redis 本身也只接受本机回环的连接。

解决办法是启动的时候覆盖掉：

```bash
docker run -d --name redis --network appnet redis:7 redis-server --bind 0.0.0.0
```

或者用配置文件：

```bash
docker run -d --name redis --network appnet \
  -v ./redis.conf:/usr/local/etc/redis/redis.conf \
  redis:7 redis-server /usr/local/etc/redis/redis.conf
```

配置文件里写 `bind 0.0.0.0`，再配一个 `requirepass`，因为一旦绑到 `0.0.0.0`，同网络里任何容器都能连，得有个密码。

这里顺便说一句，`bind 0.0.0.0` 不等于把 Redis 暴露到公网。只要你没做端口映射，外面还是进不来，只有同一 Docker 网络里的容器能访问。这个边界很容易搞混。

## 名字里的下划线和连字符

还有一次，我在 Compose 里把服务名写成了 `my_redis`，然后在应用配置里写 `my_redis`，死活解析不了。

查了半天，是 Docker 的 DNS 对下划线的处理有点特殊。容器名里带下划线的时候，有些客户端库在做解析的时候会失败，因为下划线在主机名规范里本来就不是合法字符。

把服务名改成 `my-redis`，问题立刻消失。

所以我的建议是，容器名和服务名只用小写字母、数字和连字符。别用下划线，也别用大写。这个约定能省掉很多莫名其妙的解析失败。

## Compose 里的网络行为

Compose 比裸 `docker run` 好一些，它会自动为每个项目建一个网络，项目内的服务默认都接进去，名字自动能解析。

但有几个地方还是会踩。

一个是跨项目。项目 A 的容器想连项目 B 的容器，默认是连不上的，因为它们在两个不同的网络里。得建一个外部网络，两边都声明 `external: true` 接进去。

另一个是 `container_name` 和 `services` 键的区别。如果你设了 `container_name: redis`，那这个容器在网络里的别名就是 `redis`。如果你没设，Compose 生成的容器名是 `项目名-redis-1`，但它在网络里的别名同时包含 `redis` 和 `项目名-redis-1`。所以在同一个 Compose 项目里，写服务名总是能通的。

这个行为在扩容的时候会变。`docker compose up --scale web=3` 之后，三个 web 容器会共享 `web` 这个别名，DNS 返回的是一组 IP，客户端连到哪个不确定。这时候做负载均衡是它自带的，不需要额外配置。

## 一个特别隐蔽的坑：网络别名冲突

我有一次把两个不同的项目都接到了同一个外部网络里，然后两边都有一个叫 `db` 的服务。

结果就是 DNS 返回两个 IP，客户端随机连，有时候连到 A 的数据库，有时候连到 B 的。数据错乱了一整天才发现。

解决办法是给服务加显式的网络别名：

```yaml
services:
  db:
    networks:
      shared:
        aliases:
          - projectA-db
```

然后应用里就写 `projectA-db`。这样不会撞。

或者干脆别共用网络，用不同的网络隔离。这个我后来更倾向，隔离得越清楚，出问题的概率越小。

## 排查顺序

踩过这几次之后，我形成了一个固定的检查顺序。

先看容器在不在同一个网络：

```bash
docker inspect web --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
docker inspect redis --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

两个输出里得有至少一个共同的网络名。

再看容器里的 DNS 配置：

```bash
docker exec web cat /etc/resolv.conf
```

得看到 `127.0.0.11`。

再试解析：

```bash
docker exec web getent hosts redis
```

能解析出 IP 说明名字这块没问题了。

最后测连通性：

```bash
docker exec web nc -zv redis 6379
```

到这一步还不行，那就是服务本身没监听对地址，或者有防火墙规则。

这套顺序跑一遍，基本五分钟内能定位。

## 现在的习惯

我现在新起一个服务，一律先建自定义网络，绝不往默认 bridge 里塞东西。

Compose 的话，我习惯显式写一个 `networks` 段，哪怕只是默认的那个。写出来心里有数，不用去猜它自动生成了什么名字。

还有个小习惯，我在容器里排查的时候，如果发现 `ping`、`curl`、`nc` 都没有，会临时起一个 `nicolaka/netshoot` 容器接到同一个网络上：

```bash
docker run -it --rm --network appnet nicolaka/netshoot
```

这个镜像里工具很全，`dig`、`tcpdump`、`curl`、`nc` 什么都有。比自己往业务镜像里装工具干净得多。

这类网络问题，说穿了就是"默认配置不是你以为的那个"。默认 bridge 没有 DNS，Redis 默认只听回环，容器名别带下划线，这三件事记住了，能省掉一大半的排查时间。
