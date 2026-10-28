---
# ==================== 必填（3 项）====================
title: "用了两年 Docker Compose，我把这些套路固定下来了"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-03-26T06:32:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "把博客、数据库、反代、监控这些常用服务的 compose 写法整理成模板，附上我踩过的依赖和网络坑。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Docker"
    - "Docker Compose"
    - "部署"
    - "运维"

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

刚开始用 Docker 那阵子，我特别喜欢在命令行里敲 `docker run`。参数一行能拉出去两百多个字符，`-v`、`-p`、`-e` 混在一起，看着挺有成就感。

直到有一次我为了调一个环境变量，把容器删了重建，结果忘了当初挂载的路径是哪个。数据卷还在，但容器起不来了，日志里全是找不到配置文件的报错。我在 `docker inspect` 的输出里翻了十几分钟，才从一个早已忘记的临时目录里把东西找回来。

那次之后我就老老实实用 Compose 了。现在服务器上所有的服务，都是一个个 `compose.yaml` 管着。

## 为什么是 Compose 而不是别的

有人会说，你都上 Docker 了，干嘛不上 Kubernetes。

我的答案很朴素，我就一台 2 核 4G 的机器，跑着七八个容器。K8s 的控制面自己就要吃掉一两个 G，剩下的空间还不够我塞服务。而且我一个人维护，出问题的时候需要的是能快速看懂的东西，不是一整套抽象。

Compose 的好处是，所有配置都在一个文件里，看得见摸得着。改完 `docker compose up -d`，它自己算差异，只重建变化的部分。要回滚就把文件换回去再 up 一次。

还有个被低估的点，就是文件本身就是文档。半年后我忘了某个服务是怎么配的，打开文件一看全明白了。

## 目录怎么摆

我现在的习惯是，所有服务放在 `/srv` 下面，一个服务一个目录：

```text
/srv
├── blog
│   ├── compose.yaml
│   └── data
├── db
│   ├── compose.yaml
│   ├── conf
│   └── data
├── proxy
│   ├── compose.yaml
│   ├── conf.d
│   └── certs
└── monitor
    ├── compose.yaml
    └── data
```

数据统一放在服务目录下的 `data` 子目录，然后挂载进去。这样备份的时候，把 `/srv` 整个打包就够了，不用去 `/var/lib/docker` 里翻那些名字是哈希的目录。

这一点很关键。Docker 的具名卷虽然方便，但它在文件系统里藏在 `/var/lib/docker/volumes/` 下面，备份脚本写起来很难看。用 bind mount 直接映射到自己的目录，什么都清楚。

## 一个完整的例子

拿博客举例。我的博客是 Hugo 生成的静态文件，用一个 nginx 容器托管：

```yaml
services:
  blog:
    image: nginx:1.25-alpine
    container_name: blog
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - ./public:/usr/share/nginx/html:ro
      - ./conf.d:/etc/nginx/conf.d:ro
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1/"]
      interval: 30s
      timeout: 5s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

几个地方值得说。

`ports` 我只绑了 `127.0.0.1`，不写 `0.0.0.0`。意思是这个端口只能从本机访问，外面进不来。真正对外的入口交给 nginx 反向代理，这样容器端口就不会直接暴露在公网上。这一点在我被扫过几次之后变得特别重要。

`restart: unless-stopped` 而不是 `always`。区别在于，我手动 `docker compose stop` 之后，`unless-stopped` 的容器重启机器也不会自己起来，`always` 会。调试的时候这个区别能省不少事。

`logging` 那段一定要加。Docker 默认的 json-file 日志没有大小限制，一个话多的服务跑上几个月，能把磁盘写满。我第一次被磁盘告警吵醒就是因为这个，日志文件堆到了 20 多个 G。

`healthcheck` 是给后面的 `depends_on` 用的，下面会讲。

## 数据库和依赖顺序

数据库的 compose 我一般这么写：

```yaml
services:
  mariadb:
    image: mariadb:11.2
    container_name: mariadb
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD_FILE: /run/secrets/db_root
      MARIADB_DATABASE: app
      MARIADB_USER: app
      MARIADB_PASSWORD_FILE: /run/secrets/db_app
      TZ: Asia/Shanghai
    volumes:
      - ./data:/var/lib/mysql
      - ./conf/my.cnf:/etc/mysql/conf.d/my.cnf:ro
    ports:
      - "127.0.0.1:3306:3306"
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

secrets:
  db_root:
    file: ./secrets/db_root.txt
  db_app:
    file: ./secrets/db_app.txt
```

密码用 `secrets` 而不是直接写 `environment`。这样 `docker inspect` 出来的环境变量里看不到明文，`compose.yaml` 也可以放心提交到私有仓库。文件权限设成 600 就行。

`start_period` 这个参数新手容易忽略。它是给容器一个"还在启动中，别急着判定失败"的宽限期。MariaDB 第一次初始化数据目录要花几十秒，不设这个，健康检查会一直失败，把容器标记成 unhealthy。

`healthcheck.sh` 是 MariaDB 官方镜像自带的脚本，比自己拼 `mysqladmin ping` 可靠，因为它会真的等到 InnoDB 初始化完。

应用那边要等数据库好了再起，就这么写：

```yaml
  app:
    image: myapp:latest
    depends_on:
      mariadb:
        condition: service_healthy
```

注意是 `service_healthy`，不是默认的 `service_started`。默认那个只保证容器进程起来了，不保证里面服务能连。我第一次用默认值的时候，应用每次重启都要重试好几次才连上数据库，日志里一堆 connection refused。

## 网络怎么连

Compose 默认会给项目建一个 bridge 网络，同一个文件里的服务互相用服务名就能访问。这个挺好用，但跨文件就不行了。

我有两个选择。要么把相关服务塞进同一个 compose 文件，要么建一个外部网络让它们共享。

我选了后者，因为数据库和博客的更新节奏不一样，混在一个文件里，改博客的配置会把数据库也带着重建一次，太危险。

建网络：

```bash
docker network create --driver bridge shared
```

然后每个文件里都声明：

```yaml
networks:
  shared:
    external: true
```

服务上再加一句：

```yaml
    networks:
      - shared
```

这样博客容器里直接 `ping mariadb` 就能通。

不过这里有个坑，`container_name` 和自定义网络里的服务名是两套东西。用 `container_name` 的时候，容器在网络里的别名是那个名字，不是 `services` 下的键。我一开始没注意，配置里写服务名连不上，改成 `container_name` 才对上。

我的建议是干脆别用 `container_name`，让 Compose 自己按 `项目名-服务名-序号` 生成。虽然名字长一点，但不会和别的项目冲突，扩容的时候也不会撞名。

## 反代那一层

nginx 做反向代理的容器，配置文件单独放：

```nginx
server {
    listen 80;
    server_name blog.mibase.top;

    location / {
        proxy_pass http://blog:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

`proxy_pass` 里写的是容器名，因为它在同一个 shared 网络里，Docker 的内置 DNS 会解析。

`X-Forwarded-For` 这几行别省。省了之后，nginx 的访问日志里全是反代容器的内网 IP，你想看真实访客来源就看不到了。Cloudflare 那边传过来的真实 IP 也会在这一层层里丢掉。

## 更新镜像的流程

我不用 `watchtower` 那种自动更新的东西。自动更新很爽，但它会在你睡觉的时候把一个能跑的服务换成一个跑不起来的版本。

我的流程是手动但固定：

```bash
cd /srv/db
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=50
```

拉完先看 `ps`，确认状态是 `running` 并且 `healthy`，再看日志有没有报错。有问题就 `docker compose down` 然后换回上一个 tag。

所以镜像 tag 我尽量不用 `latest`，写具体版本号。`mariadb:11.2` 比 `mariadb:latest` 可控太多了。

## 备份怎么配合

因为数据都在 `/srv/*/data` 下面，备份脚本写起来很直接：

```bash
#!/bin/bash
set -euo pipefail
ts=$(date +%F)
tar -czf /backup/srv-$ts.tar.gz -C / srv --exclude='*/cache/*'
```

不过数据库不能这么直接打包，热备份出来的文件可能是不一致的。数据库我单独用 `mariadb-dump` 导出：

```bash
docker compose exec -T mariadb mariadb-dump --all-databases --single-transaction > /backup/db-$ts.sql
```

`--single-transaction` 保证导出的是一个一致的时间点，不会因为导出过程中有人写入而错乱。

## 写在最后

Compose 这个工具本身不复杂，难的是把使用习惯固定下来。

我现在新加一个服务，基本就是复制一个已有的目录，改改镜像名和端口，十分钟能跑起来。出问题的时候也知道去哪儿看，日志在哪、数据在哪、配置在哪，都是固定的位置。

这套东西没什么高深的技术，但它让我在面对一台跑了两年、装着七八个服务的机器时，心里是有底的。这大概就是运维这件事最实际的价值。
