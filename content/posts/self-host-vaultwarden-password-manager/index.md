---
# ==================== 必填（3 项）====================
title: "受够了密码管理器的订阅费，我自己搭了一个"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-02-11T11:20:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "用 Vaultwarden 替代官方服务端，从 Docker 部署到 HTTPS、备份和客户端接入，顺便说说自托管的取舍。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "架构部署"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Vaultwarden"
    - "密码管理"
    - "Docker"
    - "自托管"

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

我用了三年某密码管理器的付费版。

涨价那次我忍了，从每年三十多美元涨到四十多。去年又涨，我看着账单发了会儿呆，然后打开了它的定价页。

家庭版六个人，一年六十美元。我家里真正会用密码管理器的只有我和我老婆两个人。

那天晚上我就在看有没有自建的方案。Vaultwarden 是第一个跳出来的，因为它的定位很明确，就是 Bitwarden 服务端的轻量实现，用 Rust 写的，官方服务端要好几 G 内存，它几十兆就能跑。

## 它和 Bitwarden 是什么关系

先说清楚，Vaultwarden 不是 Bitwarden 的官方项目，它是一个兼容实现。

它实现了 Bitwarden 的服务端 API，所以官方的所有客户端都能连，浏览器插件、桌面端、手机 App、命令行工具，全都行。你只要在登录界面把服务器地址改成自己的域名。

它的好处是轻。官方服务端是一整套微服务，跑起来要 SQL Server 加一堆容器，没有 4G 内存根本带不动。Vaultwarden 一个二进制文件加 SQLite 就能跑，1G 的机器绰绰有余。

代价是它不是官方维护的，某些新功能会滞后。比如 Bitwarden 前阵子推的 passkey 支持，Vaultwarden 过了一段时间才跟上。不过核心的密码管理功能一直很稳。

## 部署

我用的是 Docker Compose，目录放在 `/srv/vaultwarden`。

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:1.32.7
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      DOMAIN: "https://vault.mibase.top"
      SIGNUPS_ALLOWED: "false"
      INVITATIONS_ALLOWED: "true"
      ADMIN_TOKEN: "${ADMIN_TOKEN}"
      DATABASE_URL: "/data/db.sqlite3"
      ROCKET_PORT: "80"
      TZ: "Asia/Shanghai"
    volumes:
      - ./data:/data
    ports:
      - "127.0.0.1:8088:80"
```

几个关键点。

`DOMAIN` 必须写对，而且必须是 https。它是用来生成邮件里的链接、WebAuthn 的 origin 这些东西的。写错了，注册邀请链接会指向错误的地址。

`SIGNUPS_ALLOWED: "false"` 是关掉公开注册。不关的话，任何人只要知道你的域名就能注册账号，虽然数据是隔离的，但白占你的资源，还有被滥用的风险。

关掉之后，加人要用邀请。`INVITATIONS_ALLOWED: "true"` 是开着邀请功能，你可以在管理后台生成邀请链接。

`ADMIN_TOKEN` 是管理后台的密码。这个值不要写死在 compose 文件里，用环境变量从 `.env` 文件读。生成方法：

```bash
openssl rand -base64 48
```

`ports` 只绑 `127.0.0.1`，不对外暴露。外面通过 nginx 反代进来，这样容器端口不会被直接扫到。

## nginx 反代

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name vault.mibase.top;

    ssl_certificate     /etc/letsencrypt/live/vault.mibase.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vault.mibase.top/privkey.pem;

    client_max_body_size 128M;

    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

`client_max_body_size 128M` 是给附件上传用的。Bitwarden 支持存文件附件，默认的上传限制是一兆，不改的话传大一点的附件会失败。

`Upgrade` 和 `Connection` 那两个头是给 WebSocket 用的。Bitwarden 的客户端会用 WebSocket 做实时同步，不配这个，同步会有延迟。

## 证书

```bash
sudo certbot --nginx -d vault.mibase.top
```

certbot 会自动改 nginx 配置，加上证书路径和 http 到 https 的跳转。

续期是自动的，systemd timer 会每天检查。可以手动测一下：

```bash
sudo certbot renew --dry-run
```

这个一定要测。我见过有人配完就没管，一年后证书过期，所有客户端都连不上。

## 首次使用

浏览器打开 `https://vault.mibase.top`，会看到 Bitwarden 的登录页。点"创建账户"，注册第一个账号。

注册完之后，立刻去管理后台把注册关掉。虽然前面已经在环境变量里关了，但保险起见再看一眼：

```text
https://vault.mibase.top/admin
```

输入 `ADMIN_TOKEN` 进去，找到 `SIGNUPS_ALLOWED`，确认是 false。

管理后台里还能看到用户列表、邀请、诊断信息。有个"发送测试邮件"的按钮，配了 SMTP 之后可以用来验证。

## 邮件

不配 SMTP 也能用，但有些功能会受限。比如忘记主密码的重置邮件、新设备登录的验证邮件、邀请链接的邮件发送。

我的配置：

```yaml
      SMTP_HOST: "smtp.example.com"
      SMTP_FROM: "vault@mibase.top"
      SMTP_FROM_NAME: "Vaultwarden"
      SMTP_PORT: "587"
      SMTP_SECURITY: "starttls"
      SMTP_USERNAME: "vault@mibase.top"
      SMTP_PASSWORD: "${SMTP_PASSWORD}"
```

我用的是某个邮件服务商的免费额度，一个月五百封，够用了。

有个细节，`SMTP_SECURITY` 的值是 `starttls` 或者 `force_tls`，不是 `tls`。写错了它不会报错，只是发不出去，日志里也看不太出来。

## 客户端怎么连

浏览器插件和手机 App 的登录界面，都有一个设置服务器的入口。

浏览器插件里，在登录框下面有个齿轮图标，点进去能填"自托管环境"的服务器 URL。

手机 App 上，登录页左上角有个齿轮，点进去填。

填 `https://vault.mibase.top`，不要带 `/admin` 或者别的路径。

填完之后回登录页，用刚才注册的账号登录。如果之前用过官方服务，本地已经有数据，会提示你选择"登录到另一个服务器"还是"迁移"。选迁移的话，本地数据会同步到新服务器。

## 数据在哪儿

```text
/srv/vaultwarden/data/
├── db.sqlite3
├── db.sqlite3-wal
├── db.sqlite3-shm
├── attachments/
├── sends/
├── rsa_key.pem
├── rsa_key.pub.pem
└── icon_cache/
```

`db.sqlite3` 是主数据库，所有的密码条目、用户信息都在里面。

`rsa_key.pem` 是服务端的私钥，用来签名 JWT。这个文件丢了，所有用户都得重新登录。所以备份的时候一定要带上。

`attachments` 是附件，`sends` 是临时分享的文件。

## 备份

因为用的是 SQLite，直接拷贝文件是不安全的，可能有正在写的事务。

正确的做法是用 SQLite 的备份命令：

```bash
docker exec vaultwarden sqlite3 /data/db.sqlite3 ".backup '/data/backup.sqlite3'"
```

这个命令会在数据库层面做一次一致性备份，不会因为并发写入出错。

然后打包：

```bash
tar -czf /backup/vaultwarden-$(date +%F).tar.gz \
  -C /srv/vaultwarden/data \
  --exclude='icon_cache' \
  db.sqlite3 backup.sqlite3 attachments sends rsa_key.pem
```

`icon_cache` 是网站图标缓存，没必要备份，重新访问的时候会自动下载。

我写了个脚本，每天凌晨跑一次，保留三十天，同步到对象存储。具体写法在另一篇备份的文章里。

## 恢复

这个流程一定要演练过。

```bash
docker compose down
rm -rf data/*
tar -xzf /backup/vaultwarden-2026-02-10.tar.gz -C data/
mv data/backup.sqlite3 data/db.sqlite3
docker compose up -d
```

注意要先 `down` 再恢复文件，不然容器还在跑，恢复的文件会被覆盖。

我第一次演练的时候就是忘了停容器，恢复完发现数据还是旧的，还以为是备份有问题。

## 安全上要注意的

这个服务存的是你最敏感的东西，安全得多花点心思。

`ADMIN_TOKEN` 要够长，至少四十八个字符的随机串。这个 token 泄露了，别人能改你的配置。

不要开公开注册。即使开了，也要配验证码和邮件验证，否则会被当成免费的密码库来用。

HTTPS 是必须的，不是可选项。客户端的很多功能（WebAuthn、剪贴板 API）在 http 下根本不能用。

考虑加一层 Cloudflare Access，只允许自己的邮箱访问。不过这会影响到手机 App 的连接，因为 App 不方便走浏览器登录。我自己没加，因为 Vaultwarden 本身有登录验证，风险可控。

## 用下来的感受

到现在用了四个月，手机、电脑、浏览器插件都连着，同步很稳。

速度比官方服务快，因为服务器就在国内，延迟只有几十毫秒。官方服务在国内访问有时候要绕很久。

有一个小遗憾，它没有官方的"紧急访问"功能（就是你挂了之后让别人拿到你的密码库）。社区有替代方案，但要额外配。

还有一个，自托管意味着你得自己保证它一直活着。如果服务器挂了，你又刚好需要查一个密码，那就尴尬了。所以我把重要的几个密码（邮箱、银行、主密码）另外抄了一份在纸上，放在家里。

## 值不值

一年省六十美元，折合人民币四百多。花的时间大概是一个周末。

如果只看钱，不太值。但这四个月里，我对自己的密码到底存在哪儿、怎么加密的、备份在什么地方，有了完全的掌控。这种确定感是订阅服务给不了的。

当然也有代价。服务器挂了是我的责任，数据丢了我的责任，被人攻破了也是我的责任。用别人的服务，这些责任是别人担的。

这个取舍每个人不一样。我的选择是，愿意为掌控感承担这份责任。
