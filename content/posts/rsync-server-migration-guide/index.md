---
# ==================== 必填（3 项）====================
title: "把一百多 G 的网站数据搬到新服务器，中间没停过服务"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-09-29T02:00:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "两轮 rsync 加一次短暂切换，把迁移拆成可以回滚的步骤，顺带处理权限、硬链接和断点续传。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "rsync"
    - "服务器迁移"
    - "Linux"

# ==================== 封面图（用不到就保持注释）====================
# 方式 A（推荐）：图片和文章放在同一文件夹（Page Bundle），文件名 cover.jpg
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

那台老 VPS 跑了三年，配置早就跟不上了。1 核 2G，40G 硬盘，用到了 78%。新买的机器是 2 核 4G，80G 盘，价格还便宜一点。

换机器这件事，我拖了两个月才动手。不是因为难，是因为怕。上面跑着博客、两个小站、一个数据库、一堆容器，任何一个环节出错都是麻烦。

后来定了个策略，把整个过程拆成几段，每一段都可以单独验证，出问题能退回去。这才敢开始。

## 先盘点

动手之前先把老机器上有什么理清楚。

```bash
du -sh /srv/* | sort -h
```

```text
12G     /srv/docker
38G     /srv/www
  4G     /srv/backup
  2G     /srv/git
```

`/srv/www` 占了三十八个 G，主要是几个站点的图片和历史备份。`/srv/docker` 是镜像和卷。

再看系统层面：

```bash
crontab -l
systemctl list-unit-files --state=enabled
```

定时任务有五个，启用的服务有十一个。这些都要在新机器上重建。

```bash
dpkg --get-selections > /tmp/packages.txt
```

把装的软件包列表存下来，新机器上可以照着装。

## 新机器的准备

先把基础环境搭起来。

```bash
apt update && apt upgrade -y
apt install -y rsync nginx mariadb-server docker.io docker-compose-plugin \
  fail2ban ufw git curl htop tmux
```

然后是用户和权限。老机器上有个 `deploy` 用户，新机器也要建：

```bash
useradd -m -s /bin/bash deploy
usermod -aG sudo deploy
```

这一步要提前做，因为 rsync 同步的时候如果目标用户不存在，属主会变成数字，后面还得用 `chown` 改。

## rsync 的参数

全量这一轮，我用的命令是这样：

```bash
rsync -avzHAX --numeric-ids --delete \
  --exclude='*.log' \
  --exclude='.cache' \
  -e "ssh -p 2222" \
  /srv/ deploy@new-host:/srv/
```

一个个说。

`-a` 是 archive，等于 `-rlptgoD`，递归、保留权限、保留时间、保留属主属组、保留设备文件。这一项基本是必加的。

`-v` 显示进度，`-z` 压缩传输。压缩对于文本类文件有效，对已经压缩过的图片视频没效果，反而浪费 CPU。我这次因为大部分是图片，`-z` 其实没帮上什么忙，但也没坏处。

`-H` 保留硬链接。这个很重要，如果你用 rsnapshot 或者类似工具做备份，硬链接丢了体积会翻好几倍。

`-A` 保留 ACL，`-X` 保留扩展属性。如果你的文件有 SELinux 标签或者设置了 ACL，必须加这两个。

`--numeric-ids` 让 rsync 用数字 ID 而不是用户名来匹配属主。跨机器同步的时候，如果两边的用户名不一样，不加这个会按名字找，找不到就跳过。加了之后，即使 uid 不同也能保留。

`--delete` 删除目标端多出来的文件。这个参数要小心，它会让目标端和源端完全一致。这一轮我加了，因为新机器上什么都没有。但如果目标端有东西你不想要它删，就得去掉。

`--exclude` 排除日志和缓存。日志没必要同步，新机器会自己产生。

`-e "ssh -p 2222"` 是因为我把 SSH 端口改成了 2222。默认的话不用写。

## 先来一轮全量

第一次同步要把三十多个 G 传过去，按我那台机器的带宽，大概跑了四十分钟。

```bash
time rsync -avzHAX --numeric-ids --delete \
  --exclude='*.log' --exclude='.cache' \
  -e "ssh -p 2222" \
  /srv/ deploy@new-host:/srv/
```

跑的时候建议用 `tmux` 或者 `screen` 挂着，万一 SSH 断了，rsync 会中断。虽然可以用 `--partial` 续传，但重跑一次也不费事。

实际上我建议加上 `--partial` 和 `--progress`：

```bash
rsync -avzHAX --numeric-ids --delete --partial --progress \
  ...
```

`--partial` 保留中断的临时文件，下次同步可以续。`--progress` 显示每个文件的进度和总进度。

## 再补一轮增量

全量跑完之后，老机器上的数据还在变，数据库在写，日志在滚。所以要再跑一次增量。

这一轮会快很多，因为 rsync 的算法只传变化的部分。

```bash
rsync -avzHAX --numeric-ids --delete \
  --exclude='*.log' --exclude='.cache' \
  -e "ssh -p 2222" \
  /srv/ deploy@new-host:/srv/
```

这一轮跑了六分钟。

## 数据库怎么办

直接 rsync 数据库的数据文件是不行的，因为文件在写入的过程中，你复制出来的可能是不一致的。

有两种做法。

一种是在迁移窗口里停掉数据库，然后 rsync 一次。这样最安全，但会有停机。

另一种是用 `mariadb-dump` 导出，然后在新机器上导入。这个不需要停库，但导入的时间取决于数据量。

我的库不大，不到两个 G，选了导出导入这条。

```bash
mariadb-dump --all-databases --single-transaction --routines --triggers \
  -u root -p > /tmp/all-db.sql
```

然后在老机器上直接通过 ssh 管道到新机器：

```bash
cat /tmp/all-db.sql | ssh -p 2222 deploy@new-host "mariadb -u root -p"
```

或者先传文件再导入，看你的网络情况。

`--single-transaction` 保证导出的是一致性快照。前提是表都是 InnoDB，如果有 MyISAM 就得锁表。

## 权限和属主

同步完之后，检查一下属主对不对。

```bash
ssh deploy@new-host "ls -ln /srv/www"
```

`-n` 是显示数字 ID 而不是名字。如果显示的是 `1000 1000` 而不是 `deploy deploy`，说明 uid 对不上。

这种情况用 `--numeric-ids` 之后会发生，因为新机器上的 `deploy` 用户可能是 1001。

解决办法有两个。一是把新机器上的 `deploy` 改成和老机器一样的 uid，二是同步完之后统一 `chown`。

我选了统一 chown，因为改 uid 可能影响其他已经存在的文件。

```bash
ssh deploy@new-host "sudo chown -R deploy:deploy /srv/www /srv/git"
```

nginx 要读的文件，组设成 `www-data`：

```bash
ssh deploy@new-host "sudo chgrp -R www-data /srv/www && sudo chmod -R g+rX /srv/www"
```

`chmod g+rX` 里的大写 `X` 有特殊含义，它只给目录和已经有执行位的文件加执行权限。用小写 `x` 会给所有文件都加上执行位，那就不对了。

## 服务配置

把老机器上的配置文件同步过来，然后逐项改。

```bash
rsync -avz -e "ssh -p 2222" /etc/nginx/ deploy@new-host:/tmp/nginx-config/
```

先放到临时目录，人工看一遍再放到 `/etc/nginx`。直接覆盖有风险，因为两台机器的环境可能不一样。

重点检查这几处。

`server_name` 里的域名。这个不用改，因为 DNS 还没切。

`proxy_pass` 里的地址。如果老机器上是 `127.0.0.1:8080`，新机器上也是，那就没问题。但如果涉及容器名或者别的机器，要核对。

SSL 证书的路径。证书文件也要同步过去。

数据库的连接配置。新机器的密码可能不一样。

## 切换

前面几步做完，新机器上应该已经能通过 IP 访问了。先用 hosts 文件绑定测试：

```bash
# 本地 /etc/hosts
1.2.3.4  blog.mibase.top
```

浏览器访问，确认页面正常、样式正常、数据库有数据、图片能加载。

确认没问题之后，进入切换窗口。

先停掉老机器上的写入。把 nginx 停掉，让所有请求失败，这样就不会有新数据产生。

```bash
ssh old-host "sudo systemctl stop nginx"
```

然后最后一次增量同步，这次加上数据库：

```bash
rsync -avzHAX --numeric-ids --delete \
  --exclude='*.log' \
  -e "ssh -p 2222" \
  /srv/ deploy@new-host:/srv/
```

再导出一次数据库，导入新机器。

然后改 DNS。把 A 记录指向新 IP。

DNS 生效需要时间，取决于 TTL。我提前一天把 TTL 从 3600 改成了 300，这样切换的时候五分钟就能生效。

DNS 切换的过程中，有一部分用户还在访问老机器，有一部分到了新机器。这段时间老机器的 nginx 是停的，所以那部分用户会看到错误页。这是不可避免的，只能尽量缩短窗口。

## 回滚的预案

切换之前，我把老机器的 nginx 配置备份了，也记下了怎么恢复。

如果新机器有问题，回滚就是把 DNS 改回去，然后启动老机器的 nginx。

```bash
ssh old-host "sudo systemctl start nginx"
```

因为老机器的数据只是停止更新了几个小时，没有删除，所以回滚是无损的。

这个预案让我在切换的时候心里有底。知道能退回去，才敢往前走。

## 切换之后

DNS 生效之后，观察了两天。

```bash
tail -f /var/log/nginx/access.log
```

看有没有异常的状态码。看数据库的连接数。看磁盘的使用情况。

有几个小问题。

一个是时区。新机器默认是 UTC，日志时间对不上。改成 Asia/Shanghai：

```bash
sudo timedatectl set-timezone Asia/Shanghai
```

一个是 Docker 的存储路径。新机器默认在 `/var/lib/docker`，我改到了 `/srv/docker`，因为 `/srv` 那块盘更大。

```bash
sudo systemctl stop docker
sudo mkdir -p /srv/docker
sudo rsync -aHAX /var/lib/docker/ /srv/docker/
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/srv/docker"
}
EOF
sudo systemctl start docker
```

还有一个是防火墙。老机器上用的是 iptables 的直接规则，新机器我换成了 ufw，规则要重写一遍。

## 老机器的处理

确认新机器稳定之后，老机器不要立刻退。

我保留了两周。这两周里如果发现有什么东西忘了迁，还能上去找。

两周之后，把老机器上的数据打包下载到本地，然后才退掉。

```bash
ssh old-host "sudo tar -czf - /srv" > old-srv-backup.tar.gz
```

这个备份我留了三个月，确认没用了才删。

## 一点总结

整个迁移从准备到完成，花了大概一周，其中真正的切换窗口只有半小时。

花时间最多的是准备阶段。盘点、装环境、同步数据、验证配置，这些都是一步一步来的，每一步做完都能停下来检查。

我觉得迁移这件事，最重要的不是技术，是心态。不要想着一次搞定，把它拆成能验证的小步骤，每一步都有回滚的方案。

还有一点，永远不要在周五下午做这种事。
