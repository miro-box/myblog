---
# ==================== 必填（3 项）====================
title: "同一个 Hugo 站点，Nginx 配好之后快了一倍"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-06-11T21:20:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从 gzip 到 brotli、从缓存头到 http2、从 try_files 到文件描述符，把静态博客在 Nginx 上的每一处细节都过一遍。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Nginx"
    - "Hugo"
    - "性能优化"
    - "静态博客"

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

我一开始对 Nginx 托管静态站的理解是，把 root 指过去，`try_files` 写上，就完事了。

确实能跑。但用 Lighthouse 一测，分数不高。用 `curl -w` 看各阶段耗时，发现时间都花在传输上，服务器处理只占几毫秒。

也就是说，瓶颈不在 Nginx 的逻辑，在它吐数据的方式。

这篇文章记录一下我把这些都调过一遍之后的结果，首屏从一点六秒降到八百毫秒。

## 先量一下基线

```bash
curl -o /dev/null -s -w "DNS: %{time_namelookup}s\nTCP: %{time_connect}s\nTLS: %{time_appconnect}s\nTTFB: %{time_starttransfer}s\nTotal: %{time_total}s\nSize: %{size_download} bytes\n" https://blog.mibase.top/
```

这个命令把各个阶段拆开。`TTFB` 是首字节时间，`Total` 是总时间。两者的差就是传输时间。

我改之前，TTFB 是 0.18 秒，Total 是 1.2 秒。传输花了一秒多，说明 html 本身太大。

看一下首页的大小：

```bash
curl -s -o /dev/null -w "%{size_download}\n" https://blog.mibase.top/
```

一百二十 KB。对于纯文本的 html 来说，太大了。Stack 主题的首页会列出十几篇文章，每篇带摘要，加上内联的 css，确实容易膨胀。

## 先把 gzip 打开

```nginx
gzip on;
gzip_vary on;
gzip_comp_level 6;
gzip_min_length 1024;
gzip_proxied any;
gzip_types
    text/plain
    text/css
    text/xml
    text/javascript
    application/javascript
    application/json
    application/xml
    application/rss+xml
    image/svg+xml;
```

`gzip_comp_level 6` 是个折中。1 最快但压缩率低，9 最慢但只多压几个百分点。6 是常用的平衡点，压缩一百二十 KB 的 html 大概花 3 毫秒，压到三十 KB。

`gzip_min_length 1024` 是小于一 KB 的不压。因为压缩本身有开销，小文件压了反而更大。

`gzip_vary on` 会在响应里加 `Vary: Accept-Encoding`，告诉缓存层不同编码的响应要分开存。不加这个，中间有缓存的话可能把 gzip 的内容发给不支持 gzip 的客户端。

`gzip_proxied any` 是让经过代理的请求也压缩。默认只对没有 `Via` 头的请求压。用了 Cloudflare 之后，请求都带 `Via`，不加这个就不压了。

`gzip_types` 里默认不包含 `text/html`，因为 Nginx 认为 html 一定要压，它是内置的。但别的类型要显式列出来。

## brotli 比 gzip 更好

如果 Nginx 编译的时候带了 brotli 模块，可以再上一层。

Debian 和 Ubuntu 的官方包默认不带，得用第三方源：

```bash
sudo apt install -y libbrotli1
# 用 ondrej 的 nginx 源，或者自己编译
```

装完之后：

```nginx
brotli on;
brotli_comp_level 6;
brotli_min_length 1024;
brotli_types
    text/plain
    text/css
    text/javascript
    application/javascript
    application/json
    application/xml
    image/svg+xml;
```

brotli 对文本的压缩率比 gzip 高百分之十五到二十。同样一百二十 KB 的 html，gzip 压到三十 KB，brotli 能压到二十五 KB。

但 brotli 压缩更慢，级别 11 的时候能慢十倍。级别 6 是个合理的点。

还有个细节，brotli 需要 https 才能被浏览器支持。http 下浏览器不接受 `br` 编码。

## 缓存头怎么设

静态博客的资源分成两类，一类是带指纹的，一类是不带的。

Hugo 处理过的 css、js 带指纹，比如 `main.a1b2c3d4.css`。这类可以设一年：

```nginx
location ~* \.(css|js|woff2?|ttf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, max-age=31536000, immutable";
    access_log off;
}
```

图片我用的是 Page Bundle 里的原图，文件名不带指纹。这类设短一点，一周：

```nginx
location ~* \.(jpg|jpeg|png|gif|webp|avif|svg|ico)$ {
    expires 7d;
    add_header Cache-Control "public, max-age=604800";
    access_log off;
}
```

html 最短：

```nginx
location ~* \.html$ {
    expires 10m;
    add_header Cache-Control "public, max-age=600, must-revalidate";
}
```

`must-revalidate` 让浏览器在缓存过期后必须回源确认，不能拿旧的凑合。

`access_log off` 是给静态资源的。这些请求量最大，写日志的开销不小，而且它们的日志没什么分析价值。

## http2 和 http3

http2 已经是很成熟的东西了，Nginx 从 1.9.5 开始支持。

```nginx
server {
    listen 443 ssl;
    http2 on;
    ...
}
```

注意 Nginx 1.25.1 之后语法变了。以前是 `listen 443 ssl http2;`，现在是单独一行 `http2 on;`。用老语法会报一个 deprecation 警告。

http2 的好处是多路复用。同一个连接上可以并发多个请求，不用像 http1.1 那样开六个连接。对于首页要加载几十个资源的场景，提升很明显。

http3 基于 QUIC，Nginx 从 1.25 开始有实验性支持，需要单独编译。我试过一次，配置有点麻烦，而且国内很多网络对 UDP 443 不友好。暂时没用。

## try_files 的写法

```nginx
location / {
    try_files $uri $uri/ $uri.html =404;
}
```

这个写法支持无扩展名的 URL。比如 `/p/hello-world/` 会先找目录，找不到再找 `/p/hello-world.html`。

Hugo 的默认输出是目录加 `index.html`，所以 `$uri/` 那一步就能命中。但如果你改过 `uglyURLs`，就得靠 `$uri.html`。

`=404` 是最后兜底，找不到就返回 404。如果不写这个，Nginx 会返回一个内部的 404 页面，有时候行为不一致。

还有一个优化，把 `index` 指令写明确：

```nginx
index index.html;
```

默认就是 `index.html`，但写出来能省一次查找。

## 文件描述符

这个在另一篇里详细说过，这里提一句。静态站请求量大，每个请求都要打开文件，fd 不够会报 `Too many open files`。

```nginx
worker_rlimit_nofile 65535;

events {
    worker_connections 8192;
}
```

`worker_rlimit_nofile` 是 nginx 自己能打开的文件数上限，要配合 systemd 的 `LimitNOFILE` 一起调。

## sendfile 和 tcp 参数

```nginx
sendfile on;
tcp_nopush on;
tcp_nodelay on;
```

`sendfile` 让 Nginx 用内核的零拷贝直接把文件送到 socket，不用先读到用户态再写出去。静态文件服务必开。

`tcp_nopush` 是等数据攒够一个包再发，减少小包数量。它和 `sendfile` 配合使用效果最好。

`tcp_nodelay` 是不等待，立刻发。它和 `tcp_nopush` 看起来矛盾，实际上 Nginx 会根据情况自动选择。对于 keepalive 的连接用 nopush，对于要立刻响应的用 nodelay。

## keepalive 的调整

```nginx
keepalive_timeout 30s;
keepalive_requests 1000;
```

默认 `keepalive_timeout` 是 75 秒，太长了，会占着连接不放。30 秒对静态站够用。

`keepalive_requests` 是单个连接最多处理多少请求。默认 1000，对于首页要加载几十个资源的场景，一次连接就够了。

## 一个容易忽略的点：open_file_cache

这个功能会缓存打开的文件句柄，减少 `open()` 系统调用。

```nginx
open_file_cache max=10000 inactive=30s;
open_file_cache_valid 60s;
open_file_cache_min_uses 2;
open_file_cache_errors on;
```

`max=10000` 是最多缓存一万个文件描述符。`inactive=30s` 是三十秒没被访问就释放。

`open_file_cache_min_uses 2` 是至少被访问两次才缓存。只访问一次的文件，缓存了也是浪费。

这个对静态站的效果挺明显，尤其是文章页多的时候。我用 `strace` 看过，开了之后 `openat` 调用少了很多。

不过要小心，如果你的文件经常变（比如部署的时候覆盖），缓存可能导致短时间读到旧文件。`open_file_cache_valid 60s` 是六十秒校验一次，影响不大。

## 部署时的原子替换

Hugo 构建的时候会先写到一个临时目录，然后整体替换 `public`。但如果在替换的过程中有请求进来，可能读到一半新一半旧的内容。

我的做法是构建到新目录，然后用符号链接切换：

```bash
hugo --minify --gc -d /srv/www/blog/releases/$(date +%s)
ln -sfn /srv/www/blog/releases/$(date +%s) /srv/www/blog/current
```

Nginx 的 root 指向 `/srv/www/blog/current`。

符号链接的切换是原子的，Nginx 打开文件的时候会跟随链接，所以不会有中间状态。

这个做法还有个好处，回滚就是把链接指回上一个目录，一秒搞定。

## 改完之后的效果

```bash
curl -o /dev/null -s -w "TTFB: %{time_starttransfer}s\nTotal: %{time_total}s\nSize: %{size_download}\n" https://blog.mibase.top/
```

TTFB 0.09 秒，Total 0.28 秒，Size 28 KB。

从一点二秒到零点二八秒。Lighthouse 移动端从 62 分到 96 分。

## 哪些改动最有用

如果只能做三件事，我会选这三件。

开 gzip，或者 brotli。这个改动最小，收益最大，html 从一百二十 KB 降到三十 KB。

给静态资源设长缓存。第二次访问的时候，浏览器直接用本地的，一个请求都不发。

用 http2。首页要加载几十个资源，多路复用省掉的连接开销很可观。

剩下的 `sendfile`、`open_file_cache` 这些，是锦上添花。做不做差别不大，但既然配置一次就能长期生效，顺手做了也没什么坏处。

## 最后

静态博客的性能优化，本质上是在做两件事。让传输的数据更少，让重复的请求更少。

Nginx 提供了足够多的手段，但大部分默认值不是为静态站调的。花一个小时把这些配置过一遍，之后每一次访问都会受益。
