---
# ==================== 必填（3 项）====================
title: "博客被人刷了一晚上，我用 fail2ban 把这事收了个尾"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-08-30T23:33:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "一次被 CC 打的经历，从看日志到写 jail，把 nginx 和 ssh 两边都接进 fail2ban，还顺手调了 nftables 后端。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "安全"
    - "Fail2ban"
    - "Nginx"
    - "防火墙"

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

那天早上起来，博客打不开了。

浏览器转圈，转了很久之后给了一个 502。我一边刷牙一边用手机连上去看，`uptime` 显示 load average 是 34。

我那台机器是 1 核 2G，正常负载在 0.1 左右。34 这个数字意味着有东西在疯狂占 CPU。

## 先看是什么在打

```bash
ss -tn state established '( sport = :443 )' | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head
```

输出里有一批 IP，每个都有几百个连接。再看 nginx 的访问日志：

```bash
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20
```

排名第一的 IP 在十分钟里请求了三万多次。

```bash
grep '1.2.3.4' /var/log/nginx/access.log | tail -5
```

请求的路径全是 `/search?q=<随机字符串>`，User-Agent 是一个老掉牙的浏览器标识。典型的 CC 攻击，拿一个搜索页反复刷，因为这个页面每次都查数据库，最耗资源。

## 临时的止血

先把那个 IP 拉黑，让机器能喘口气：

```bash
iptables -I INPUT -s 1.2.3.4 -j DROP
```

立刻见效，负载从 34 掉到 2。但十分钟后，另一个 IP 开始用同样的方式打。

这就说明手动拉黑没用，攻击方手里有一批 IP，封一个换一个。

## 那就上 fail2ban

fail2ban 的思路很简单。它盯着日志文件，按你写的规则匹配失败记录，同一个 IP 在时间窗口里超过阈值就调用防火墙把它封一段时间。

装：

```bash
apt update
apt install fail2ban -y
```

Debian 12 装完默认就是启用的，但里面除了 `sshd` 那个 jail，别的都没开。

配置不要改 `/etc/fail2ban/jail.conf`，那个文件在升级的时候会被覆盖。新建一个 `jail.local`：

```bash
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

## 先把 SSH 那边接上

虽然这次的攻击是打 HTTP，但 SSH 那边的爆破一直没停过。顺手一起处理。

`jail.local` 里找 `[sshd]` 段，或者干脆在文件末尾新加：

```ini
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
```

`backend = systemd` 这个设置值得说一下。Debian 12 默认没有 `/var/log/auth.log` 了，认证日志都进了 journald。用 `systemd` 这个 backend，fail2ban 会通过 `journalctl` 去读，不用依赖文件存在。

我第一次配的时候没改这个，fail2ban 起不来，日志里写着 `Have not found any log file for sshd jail`。找了半天才明白。

## 再配 nginx 的 jail

这个要自己写，因为每个站的日志格式和攻击特征都不一样。

先看日志格式。我的 nginx 用的是默认的 combined，长这样：

```text
1.2.3.4 - - [30/Aug/2024:03:12:44 +0800] "GET /search?q=xxx HTTP/1.1" 200 5123 "-" "Mozilla/5.0 ..."
```

fail2ban 的 `failregex` 用正则去匹配这一行，`<HOST>` 是个占位符，会自动替换成 IP 的匹配模式。

针对这次攻击，我写了个 filter，放在 `/etc/fail2ban/filter.d/nginx-cc.conf`：

```ini
[Definition]

failregex = ^<HOST> -.*"(GET|POST|HEAD) /search\?.* HTTP/1\.[01]" 200

ignoreregex =
```

意思是，请求 `/search` 且返回 200 的，算一次。

然后在 `jail.local` 里加：

```ini
[nginx-cc]
enabled  = true
port     = http,https
filter   = nginx-cc
logpath  = /var/log/nginx/access.log
maxretry = 30
findtime = 1m
bantime  = 2h
```

`maxretry = 30` 和 `findtime = 1m` 意味着，一分钟内请求同一个路径超过三十次就封。正常用户不可能这么干，但搜索引擎的爬虫有可能。所以我还得加个白名单。

## 别把自己的爬虫封了

Google 和 Bing 的爬虫会被误伤。虽然它们一般不会一分钟请求三十次，但保险起见，还是加个 ignoreip。

先确认爬虫的真实 IP。注意不能信 User-Agent，得用反向解析：

```bash
dig +short -x 66.249.66.1
```

返回 `crawl-66-249-66-1.googlebot.com.` 就说明是真的。伪造的 UA 反解出来不会是这个域名。

把这个网段加进白名单：

```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 66.249.64.0/19 40.77.167.0/24
```

前者是 Googlebot，后者是 Bingbot。这两个网段官方都有公布，定期看一眼有没有变。

## 让 Cloudflare 的真实 IP 传进来

这一步很重要，我差点漏了。

我的博客前面挂了 Cloudflare，所以 nginx 的访问日志里，`$remote_addr` 全是 Cloudflare 的节点 IP。如果不处理，fail2ban 会去封 Cloudflare 的节点，一封就是一大片用户打不开。

要在 nginx 里先把真实 IP 还原：

```nginx
# /etc/nginx/conf.d/cloudflare-realip.conf
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 104.16.0.0/13;
# ... 其余网段省略
real_ip_header CF-Connecting-IP;
real_ip_recursive on;
```

Cloudflare 官方有个 IP 列表页面，也可以直接拉：

```bash
curl -s https://www.cloudflare.com/ips-v4
```

把这些网段全部写进 `set_real_ip_from`。配好之后 `nginx -t && nginx -s reload`，再看日志，`$remote_addr` 就是真实访客的 IP 了。

这一步做完，fail2ban 封的才是攻击者，不是 Cloudflare。

## 防火墙后端用哪个

fail2ban 支持好几种后端，iptables、nftables、firewalld。Debian 12 默认是 nftables，但 fail2ban 的默认配置可能还在用 iptables。

看当前用的是哪个：

```bash
fail2ban-client -d | grep -i banaction
```

如果是 `iptables-multiport`，而系统里其实是 nftables，封禁规则会写进 iptables 的兼容层，虽然也能生效，但 `nft list ruleset` 里看到的格式很乱，排查的时候不方便。

改一下：

```ini
[DEFAULT]
banaction = nftables-multiport
banaction_allports = nftables-allports
```

然后重启 fail2ban。

## 验证和观察

```bash
systemctl restart fail2ban
systemctl status fail2ban
```

看 jail 有没有都起来：

```bash
fail2ban-client status
```

应该能看到 `sshd` 和 `nginx-cc` 两个。

看某个 jail 的详情：

```bash
fail2ban-client status nginx-cc
```

输出里有当前封了多少个、总共封过多少个、以及封禁列表。

我配完第二天看了一下，`nginx-cc` 封了 200 多个 IP，`sshd` 封了 60 多个。负载回到了 0.2。

## 几个后续调整

`bantime` 我一开始设的 1 小时，后来改成递增。fail2ban 支持这个：

```ini
bantime.increment = true
bantime.factor   = 2
bantime.maxtime  = 4w
```

意思是第一次封 1 小时，再犯封 2 小时，再犯 4 小时，一直翻倍到四周。这个机制对那种反复来的 IP 很有效。

`bantime.increment` 需要 fail2ban 的数据库支持，默认是开着的，位置在 `/var/lib/fail2ban/fail2ban.sqlite3`。别把它删了，删了计数就归零。

还有个 `findtime` 的坑。它和 `bantime` 是独立的，`findtime` 只决定统计窗口，不影响封多久。我一开始以为 `findtime` 设长了封得久，结果不是。

## 也别忘了限流

fail2ban 是事后处理，等它反应过来，攻击流量已经打进来几十秒了。

所以我又在 nginx 里加了一层限流：

```nginx
limit_req_zone $binary_remote_addr zone=search:10m rate=10r/m;

location /search {
    limit_req zone=search burst=5 nodelay;
    limit_req_status 429;
}
```

这个是事前的，请求超过频率直接返回 429，连 PHP 都不进。两层配合起来，效果比单独用任何一个都好。

## 写在最后

这次攻击持续了大概两天，之后就没再来了。可能是对方觉得我这个站不值得，也可能是成本太高。

回过头看，最该反思的是那个搜索页。它是动态查询，没有缓存，一个请求就要连一次数据库。这种页面天生就是被刷的目标。

后来我给搜索结果加了一层 Redis 缓存，同样的查询五分钟内直接返回缓存。这个改动比 fail2ban 更治本，因为它把攻击的成本降下来了。

安全这件事，工具只是兜底。真正要做的，是让被攻击的那个点变得不那么值钱。
