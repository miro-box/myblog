---
# ==================== 必填（3 项）====================
title: "家里那台小主机没有公网 IP，我用 Cloudflare Tunnel 把它挂上了网"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-02-29T19:44:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "宽带没有公网 IP、端口也封了，用 cloudflared 把内网服务安全地发布出去，顺便聊聊它和 frp 的区别。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "架构部署"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Cloudflare"
    - "内网穿透"
    - "Tunnel"
    - "家庭网络"

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

搬进新租的房子之后，第一件让我难受的事就是宽带没有公网 IP。

装机师傅上门那天我特意问了，他说现在都这样，上面统一做的 NAT，想开端口得另外找客服申请，而且就算申请下来也是动态的，重启光猫就换一个。我试着在路由器上拨号看了一下，WAN 口拿到的是 `100.64.x.x`，运营商级 NAT 的内网地址，彻底没戏。

问题是我家里有台常年开着的小主机，跑着几个自己写的小服务。一个是用来看照片的相册，一个是给家里人用的备忘录，还有一个是给小孩做的手工课视频站。以前在旧房子那边有公网 IP，路由器上做个端口映射，出门在外随时能打开。现在全断了。

## 试过的几种方案

先说被排除的。

花生壳那类内网穿透我最早试过，免费版带宽小得可怜，而且域名是一长串随机字符，发给家里人他们根本记不住。付费版按年收费，我看了一眼价格，不如直接买台有公网 IP 的 VPS。

frp 我用了差不多一年。自己在香港买了台 1 核 1G 的小机器当跳板，家里跑 frpc，外面跑 frps。能用，但有几个麻烦。跳板机的带宽是个硬瓶颈，我买的那台是 30M 峰值，实际晚上跑起来经常掉到 5M 以下，看个视频就卡。而且这台机器我得自己维护，系统更新、证书续期、被扫了还得上去看看，一年下来也是一笔精力。

后来在 V2EX 上看到有人提 Cloudflare Tunnel，我一开始以为是那种要企业套餐的付费功能，点进去看了才知道，免费版也能用，而且不限流量。这个就值得试了。

## 它到底是怎么工作的

原理说起来很简单。

`cloudflared` 这个程序装在你的内网机器上，它主动往外连 Cloudflare 的边缘节点，建立一条长连接。这条连接是出站的，所以你不需要有公网 IP，也不需要动路由器上的任何设置。外面的人访问你的域名，请求先到 Cloudflare，Cloudflare 顺着这条已经建好的隧道把请求送进来，你的机器响应之后再原路返回。

因为隧道是 `cloudflared` 主动发起的，中间不存在任何入站端口，家里的防火墙和运营商的封禁都不受影响。

还有个好处是，你不需要在路由器上开任何端口。以前做端口映射的时候，我总担心哪天路由器固件有漏洞被人扫到，现在这条路直接堵死了。

## 装起来

我的小主机是 Debian 12，直接加官方源装最省事。

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install cloudflared
```

装完 `cloudflared --version` 能出版本号就行。

接下来登录。这一步会给你一个很长的链接，你得复制到浏览器里打开：

```bash
cloudflared tunnel login
```

浏览器里会让你选一个域名授权。我的域名在 Cloudflare 上托管，选它，然后它会自动在你的 DNS 里加一条 `cert.pem` 用的授权。授权文件落在 `~/.cloudflared/cert.pem`。

注意这个 cert 是按域名授权的，一个域名一个文件。如果你有多个域名都要用，得分别登录一次。

## 创建隧道和配置

```bash
cloudflared tunnel create homelab
```

它会生成一个 UUID，并且在 `~/.cloudflared/` 下面放一个同名的 json 文件，里面是隧道的凭据。这个文件是密钥，别传 GitHub 上去。

然后写配置文件，位置在 `~/.cloudflared/config.yml`：

```yaml
tunnel: homelab
credentials-file: /home/mingyue/.cloudflared/8f3c1a2b-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json

ingress:
  - hostname: photo.mibase.top
    service: http://127.0.0.1:8081
  - hostname: note.mibase.top
    service: http://127.0.0.1:8082
  - hostname: craft.mibase.top
    service: http://127.0.0.1:8083
  - service: http_status:404
```

`ingress` 是从上往下匹配的，最后那条兜底必须写，不然配置检查会报错。

还有一个细节，如果你内网的服务绑的是 `0.0.0.0`，用 `127.0.0.1` 也没问题。但如果服务只监听 IPv6，就得写成 `http://[::1]:8081`。

## 把 DNS 指过去

```bash
cloudflared tunnel route dns homelab photo.mibase.top
cloudflared tunnel route dns homelab note.mibase.top
cloudflared tunnel route dns homelab craft.mibase.top
```

它会自动在 Cloudflare 里加 CNAME，指向 `<UUID>.cfargotunnel.com`，并且是橙云状态，也就是走代理。

这三条加完，DNS 那块就不用手动动了。

## 跑成服务

前台跑着测试没问题之后，换成 systemd 托管：

```bash
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

然后看状态：

```bash
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f
```

日志里能看到四条连接建起来的信息。Cloudflare 默认会建四条，冗余用的，一条断了另外几条顶上，切换的时候用户基本无感。

## 访问控制和登录验证

隧道跑通之后，第一个冒出来的念头是：这玩意儿是不是谁都能访问。

是的，默认就是公开的。所以我立刻去配了 Cloudflare Access。

在 Zero Trust 后台里，Access 下面的 Applications，新建一个 Self-hosted 应用。域名填 `note.mibase.top`，然后建一条策略，Action 选 Allow，Include 里选 Emails，把我自己和家里人的邮箱填进去。

配完之后再访问，会先跳到一个 Cloudflare 的登录页，输入邮箱收验证码，通过了才放行。免费版给五十个用户，够用了。

给小孩看的视频站我没加验证，那个本来就是想分享给亲戚的，加了反而麻烦。

## 顺手做的一件事

既然流量都过 Cloudflare 了，缓存规则也可以顺手配上。视频站的封面图我设了一年的 Edge TTL，这样重复访问基本不消耗回源带宽。

这个和博客那边是同一套思路，静态的东西缓存长一点，动态的别缓存。

## 和 frp 比到底差在哪

用了一个多月，我的感受是这样的。

带宽上 Cloudflare 明显强。它是全球任播，国内访问会落到就近的节点，实际测下来晚上也能跑满我家的上行。frp 那台跳板机受限于单机带宽，这点没法比。

省心程度上也是 Cloudflare 好。跳板机不用自己维护，证书它帮你签，系统补丁不用管，被打也不用管。这一点对我这种懒得折腾的人来说很重要。

但也不是没代价。

延迟会比直连高一些，毕竟多绕了一层。我在家用局域网访问，走的是本地地址，没影响；在外面访问大概多二十毫秒，日常用感觉不出来，但如果你要跑远程桌面，那点延迟是能感觉到的。

另外就是把一部分控制权交出去了。域名、证书、访问日志都在 Cloudflare 那边。真要哪天它改政策或者涨价，迁移的成本不算低。所以我一直保留着 frp 的配置没删，算是个备份方案。

还有一点，免费版对 WebSocket 的支持是有的，但长连接有时候会被掐。我那个相册里的实时同步功能就偶尔断，后来改成轮询才稳定下来。

## 遇到的两个坑

一个是 `cloudflared` 的内存占用。这东西跑久了会慢慢涨，我有一次看它吃了 400 多兆。后来加了个定时重启，每天凌晨重启一次，问题就没了。官方 issue 里也有人反馈过，看起来还没彻底修。

另一个是回源协议。我的服务是 http，如果 `service` 写成 `https://127.0.0.1:8081`，会报 TLS 握手失败。改成 `http://` 就好。这个错我当时找了半天，因为日志里只写了个 502，没提 TLS。

## 现在的情况

三个服务稳定跑了一个多月，家里人也习惯了直接输域名访问，不再问我"那个链接是多少"。

回头看，这件事最舒服的地方不是技术多新，而是它把一件需要长期维护的事情变成了不用管的事情。以前跑 frp，我每个月至少要看一眼那台跳板机，现在这块彻底从我待办里消失了。
