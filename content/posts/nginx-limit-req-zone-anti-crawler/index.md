---
# ==================== 必填（3 项）====================
title: "带宽一夜之间跑了 40G，原来是有人在爬我的站"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-04-27T03:28:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "用 limit_req_zone 和 limit_conn_zone 给 nginx 加限流，从漏桶算法讲到 burst 和 nodelay 到底怎么配。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Nginx"
    - "限流"
    - "反爬虫"
    - "漏桶算法"

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

四月的某天，云厂商发来一条流量预警，说我这个月的出网流量已经用了 80%。

我看了一眼统计，那天从凌晨到早上八点，跑了四十多个 G。平时一整天也就两三个 G。

第一反应是被人盗链了。查了一下 nginx 的 access log，确实有几个 IP 在疯狂请求图片。

但仔细一看，不对。它们请求的不只是图片，还有每一篇文章的 html，每个都带着不同的 UA，请求间隔很均匀，大概两百毫秒一次。这不是盗链，是有人在整站爬。

## 先看清楚规模

```bash
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20
```

前五名每个都有一万多次请求。再看它们的 UA：

```bash
grep '1.2.3.4' /var/log/nginx/access.log | awk -F'"' '{print $6}' | sort | uniq -c
```

全是同一个 UA，一个很老的 Chrome 标识，而且请求头里没有 `Accept-Language`，没有 `Referer`。正常浏览器不会这样。

这就是典型的爬虫，可能是某个做镜像站的在收集内容，也可能是训练数据。

## 能做的事有几种

最直接的是封 IP。但爬虫往往有一批 IP，封一个换一个。

另一个办法是在 Cloudflare 那边开 Bot Fight Mode。免费版有这个功能，能挡掉一部分低级爬虫。但它有时候会误伤正常的搜索引擎，而且对模拟得很像的爬虫没效果。

再一个就是在 nginx 层面做限流。这个是治本的，不管对方换多少 IP，只要单个 IP 的请求频率超过阈值，就限速或者拒绝。

我选了限流，Bot Fight Mode 也顺手开着，两个一起用。

## limit_req_zone 是怎么回事

nginx 的限流模块叫 `ngx_http_limit_req_module`，核心是漏桶算法。

先说漏桶是什么意思。

想象一个桶，桶底有个洞，水以固定的速度往外漏。你往桶里倒水，如果倒得比漏得快，水就会积起来。桶满了之后，再倒就溢出去了。

对应到 nginx，请求就是水，桶的容量是 `burst`，漏水速度是 `rate`。请求速率超过 `rate` 之后，会先在桶里排队，桶满了就拒绝，返回 503 或者你指定的状态码。

这个算法有个特点，它允许短时间的突发。比如你设了 `rate=10r/s`，`burst=20`，那么一个瞬间来 25 个请求，前 10 个立刻处理，后面 15 个排队，第 26 个开始拒绝。

这个特性对正常用户很友好，因为人浏览网页本来就是一阵一阵的。

## 配置

先在 `http` 块里定义 zone：

```nginx
limit_req_zone $binary_remote_addr zone=perip:10m rate=5r/s;
```

`$binary_remote_addr` 是客户端 IP 的二进制形式，比 `$remote_addr` 省空间。`zone=perip:10m` 是给这个 zone 起个名字，分配 10M 内存。

10M 大概能存十六万个 IP 的状态。对于个人站绰绰有余。

`rate=5r/s` 是每秒五个请求。这个值要看你的站。我的站页面不多，一个正常用户浏览的时候，一秒最多也就两三个请求（html 加 css 加 js 加几张图）。设成 5 是个合理的上限。

注意 `rate` 的单位。写 `5r/s` 是每秒五个，写 `5r/m` 是每分钟五个。这两个差别很大，别写错。

然后在 `server` 或者 `location` 里用：

```nginx
server {
    listen 443 ssl http2;
    server_name blog.mibase.top;

    location / {
        limit_req zone=perip burst=10 nodelay;
        limit_req_status 429;

        try_files $uri $uri/ =404;
    }
}
```

`burst=10` 是桶的容量，允许十个请求排队。

`nodelay` 这个参数很关键。不加它，排队的请求会按 rate 慢慢放行，用户会感觉页面加载被拖慢了。加了之后，桶里的请求立刻处理，只是超过桶容量的才拒绝。

`limit_req_status 429` 是自定义拒绝时的状态码。默认是 503，但 503 表示服务不可用，429 表示请求过多，语义上 429 更准确。有些爬虫看到 503 会重试，看到 429 会退避。

## limit_conn_zone 管并发

`limit_req` 管的是速率，`limit_conn` 管的是同时打开的连接数。

这两个要一起用。因为有的爬虫很聪明，它把请求间隔拉长到刚好不被限速，但同时开几十个连接。

```nginx
limit_conn_zone $binary_remote_addr zone=conn_perip:10m;

server {
    limit_conn conn_perip 20;
    limit_conn_status 429;
}
```

单个 IP 最多二十个并发连接。正常浏览器对一个站同时开六个连接就够了（HTTP/1.1 的限制），HTTP/2 会多一点，但也不会到二十。

## 白名单

搜索引擎的爬虫不能限。

```nginx
geo $limit {
    default 1;
    66.249.64.0/19 0;
    40.77.167.0/24 0;
    157.55.39.0/24 0;
    207.46.13.0/24 0;
    127.0.0.1/32 0;
}

map $limit $limit_key {
    0 "";
    1 $binary_remote_addr;
}

limit_req_zone $limit_key zone=perip:10m rate=5r/s;
```

`geo` 模块按 IP 段匹配，匹配到的设成 0。`map` 把 0 转成空字符串，空字符串在 `limit_req_zone` 里表示不参与限流。

这个写法比在 `location` 里写一堆 `if` 要干净得多，而且性能更好，因为 `geo` 和 `map` 都是编译成哈希表查找。

白名单的 IP 段要定期核对。Google 和 Bing 都公布了官方列表，而且会变。我一般是每个月看一次。

## 给不同路径设不同阈值

静态资源可以放宽，因为一个页面会带很多张图。动态接口要收紧。

```nginx
limit_req_zone $limit_key zone=static:10m rate=30r/s;
limit_req_zone $limit_key zone=dynamic:10m rate=3r/s;

location ~* \.(css|js|jpg|jpeg|png|webp|svg|woff2)$ {
    limit_req zone=static burst=50 nodelay;
    expires 1y;
}

location /api/ {
    limit_req zone=dynamic burst=5 nodelay;
    limit_req_status 429;
}
```

这样正常浏览页面不会因为图片多被误伤，而接口那边被刷的时候能立刻挡住。

## 观察限流的效果

nginx 的日志里默认不记录限流信息。想统计，得在 `log_format` 里加变量。

```nginx
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for" '
                'req_limit=$limit_req_status conn_limit=$limit_conn_status';
```

然后统计：

```bash
awk '$NF ~ /req_limit=REJECTED/ {print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```

能看到哪些 IP 被拒得最多。

配完当天，日志里被拒的请求有两万多次，来自三十多个 IP。流量从四十 G 降到了正常水平。

## 几个容易踩的坑

`limit_req_zone` 只能写在 `http` 块里，写在 `server` 里会报错。这个我一开始搞错了，`nginx -t` 直接不通过。

`burst` 设太大等于没限流。因为桶的容量就是允许的突发量，设成一千，对方一次来一千个请求也能过。我的经验是，正常页面需要的资源数加一点余量，二三十就够了。

`nodelay` 不加的话，虽然请求不会被拒，但会被延迟处理，用户会觉得网站变慢。这个体验比直接返回 429 更糟。

用了 Cloudflare 的话，一定要先配 `real_ip`，否则 `$binary_remote_addr` 拿到的是 Cloudflare 的节点 IP，限流会误伤所有用户。这个坑我在 fail2ban 那篇里也提过，是同一个问题。

还有，`limit_req` 是有状态的，它的计数器存在共享内存里。如果你有多台 nginx 做负载均衡，每台的计数是独立的，实际允许的速率是单台的倍数。这种情况得在更上层做限流，或者用 Redis 存共享计数。

## 最后的手段

限流只能减缓，挡不住真正执着的爬虫。

我在限流之后又加了一层，针对那些明显是爬虫的请求，直接返回 403：

```nginx
map $http_user_agent $bad_bot {
    default 0;
    ""      1;
    "~*python-requests" 1;
    "~*scrapy"          1;
    "~*curl/7"          1;
    "~*Go-http-client"  1;
}

server {
    if ($bad_bot) {
        return 403;
    }
}
```

这个写法比较粗暴，会误伤一些用 curl 的正常用户。但我的站是给人看的，不是给脚本用的，我觉得可以接受。

`if` 在 nginx 里是不推荐用的，因为它在 `location` 里的行为有陷阱。但放在 `server` 级别做这种简单的判断，是官方文档里明确说可以用的场景。

## 现在的状态

这套配置跑了几个月，流量稳定在每天两个 G 左右，没有再出现异常。

偶尔还是会有爬虫来，但它们被限速之后，爬完整个站要很久，大多数爬到一半就放弃了。

回头看，这件事的本质是，我的站没有任何成本地暴露在公网上，谁都能来拿。限流是在给它加一个成本，让无差别抓取变得不划算。

这个思路可以用在很多地方。API 也好，下载站也好，只要能定义"正常使用的频率"，就能用同样的方法保护自己。
