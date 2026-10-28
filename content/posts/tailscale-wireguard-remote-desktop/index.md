---
# ==================== 必填（3 项）====================
title: "卸载了向日葵和 ToDesk，我用 Tailscale 连回了家里的电脑"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-03-10T18:25:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "基于 WireGuard 的组网方案，从装客户端到 subnet router、exit node，把家里几台设备串成一个大局域网。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "网络工程"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Tailscale"
    - "WireGuard"
    - "远程桌面"
    - "内网穿透"

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

我出门在外的时候，经常要连回出租屋里的台式机。

有时候是要跑一个本地才有的编译环境，有时候是要从家里那台机器上拷个文件，有时候纯粹是想用大屏幕看个东西。

最早用的是向日葵，免费版画质一般，而且经常提示"当前为免费通道，画质受限"。后来换了 ToDesk，好一些，但免费版有连接时长限制，一个月四十小时，用超了就得等。

更让我介意的是，这两个软件都要经过它们自己的服务器中转。我不知道我的屏幕画面在中间经过了什么，这让我不太舒服。

后来在论坛上看到有人提 Tailscale，说是基于 WireGuard 的组网工具，免费版给一百个设备。我试了一下，之后就再也没打开过那两个软件。

## 它解决的是什么问题

先说清楚它不是什么。

它不是远程桌面软件。它做的是组网，让你的设备之间能像在同一个局域网里一样互相访问。

组好网之后，你可以用任何远程桌面工具连过去，Windows 自带的 RDP、macOS 的屏幕共享、VNC、甚至 `ssh -X`。因为从系统的角度看，对面就是局域网里的另一台机器。

它也不是传统的 VPN。传统的 VPN 是星型结构，所有流量都经过中心服务器。Tailscale 是网状结构，两台设备之间尽量直连，服务器只负责协调和 NAT 穿透。

这个区别很重要。直连意味着低延迟，也意味着数据不经过第三方。

## 底层是 WireGuard

WireGuard 是这几年很火的一个 VPN 协议，已经进了 Linux 内核。它的特点是代码量小、性能好、配置简单。

Tailscale 用的是 WireGuard 做数据平面，自己做了控制平面。控制平面负责设备注册、密钥分发、NAT 穿透协调。数据平面是设备之间的 WireGuard 隧道。

所以它的流量是端到端加密的，中间没有任何人能看懂。就算是 Tailscale 自己的服务器，也只能看到谁和谁在通信，看不到内容。

这个架构比传统的 VPN 好很多，也比那些中转式的内网穿透工具好。

## 装

官网下载对应平台的安装包，一路下一步。

Windows、macOS、Linux、iOS、Android、甚至群晖和 OpenWrt 都有客户端。

Linux 上最方便的是官方脚本：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

它会自动识别发行版，配好软件源，装完就能用。

## 登录

```bash
sudo tailscale up
```

它会输出一个链接，复制到浏览器打开，用 Google、GitHub 或者微软账号登录。

登录之后，这台设备就出现在你的管理后台里了。后台地址是 `https://login.tailscale.com/admin/machines`。

每台设备会分到一个 `100.x.x.x` 的地址，这个网段是 Tailscale 专用的，叫 CGNAT 段，和公网地址不冲突。

我给每台设备都改了名字，方便识别。后台里点设备名就能改。

## 把第二台也接进来

同样的流程，装完登录同一个账号。

登录之后，两台设备之间就通了。在 A 上 `ping 100.x.x.x`（B 的地址）应该能通。

```bash
tailscale status
```

这个命令能看到所有设备的状态，包括是否直连、延迟多少。

```text
100.64.0.1   desktop-win    mingyue@  windows  -
100.64.0.2   laptop-mac     mingyue@  macOS    active; direct 192.168.1.5:41641, tx 1234 rx 5678
100.64.0.3   vps-hk         mingyue@  linux    active; relay "hkg", tx 999 rx 888
```

`direct` 表示两台设备直连，后面的地址是实际的公网 IP 和端口。`relay` 表示没能直连，走了中继，延迟会高一些。

## MagicDNS

Tailscale 有个功能叫 MagicDNS，它会给每台设备分配一个域名，形如 `设备名.你的账号名.ts.net`。

开了之后，你不需要记 IP，直接用名字访问：

```bash
ping desktop-win
ssh laptop-mac
```

这个在设备多了之后特别方便。IP 是会变的，名字不会。

在后台的 DNS 页面里开启。开启之后，Tailscale 会接管设备的 DNS 解析，把 `*.ts.net` 的查询指向自己的解析器。

这个接管可能会和你的其他 DNS 配置冲突。如果你用了 Pi-hole 或者自定义的 DNS，要注意一下。

## 远程桌面

组好网之后，远程桌面就简单了。

Windows 那边，先在系统设置里开启"远程桌面"，然后在另一台机器上：

```bash
mstsc /v:desktop-win
```

或者用 Microsoft Remote Desktop 客户端，地址填 `desktop-win` 或者 `100.64.0.1`。

macOS 那边，开启"屏幕共享"，然后：

```bash
open vnc://laptop-mac
```

Linux 上可以用 `xrdp` 或者 `gnome-remote-desktop`。

我平时用的是 Windows 自带的 RDP。画质可以调，延迟低，而且支持多显示器。比那些第三方软件流畅多了。

## subnet router：让整个局域网都通

这是我最喜欢的功能。

Tailscale 默认只让你访问装了客户端的设备。但如果你家里有一台 NAS、一台打印机、一个树莓派，不可能每台都装客户端。

subnet router 的作用是，让一台设备充当网关，把整个局域网的路由转发出去。

在家里那台常年开着的小主机上：

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

sudo tailscale up --advertise-routes=192.168.1.0/24
```

然后在后台的 Machines 页面，找到这台设备，点右边的三个点，选 "Edit route settings"，把 `192.168.1.0/24` 勾上。

之后你在外面，就能直接访问 `192.168.1.x` 下面的任何设备了。NAS、打印机、路由器管理页，全都能打开。

这个功能让我出门在外的时候，感觉像是回到了家里的局域网。

注意，`--advertise-routes` 要在 `tailscale up` 的时候传，不是单独的命令。如果之前已经 up 过了，要重新跑一次。

## exit node：把流量都走家里

这个功能更激进一点。

配了 exit node 之后，你所有设备的出网流量都会经过家里那台机器出去。相当于你人在外面，但网络出口在家里。

用处有两个。

一个是访问那些限制地区的服务。比如某些流媒体只允许家庭宽带 IP 访问。

另一个是安全性。在咖啡厅的公共 Wi-Fi 上，所有流量都走加密隧道回家，不用担心被人抓包。

配置：

```bash
sudo tailscale up --advertise-exit-node
```

然后在后台勾上 "Use as exit node"。

客户端那边选择使用这个 exit node：

```bash
sudo tailscale up --exit-node=100.64.0.1 --exit-node-allow-lan-access
```

`--exit-node-allow-lan-access` 是让本地局域网的访问不走隧道。不加的话，你连本地打印机都会绕到家里去。

Windows 和 macOS 的客户端有图形界面，在菜单里选就行。

## ACL：控制谁能访问谁

免费版也支持 ACL，用的是类似 JSON 的配置语言。

默认的 ACL 是允许所有设备互相访问。如果你只想让自己访问，别人不行，就得改。

在后台的 Access Controls 页面：

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["*:*"]
    }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "users": ["autogroup:nonroot"]
    }
  ]
}
```

`autogroup:member` 是账号下的所有成员。`autogroup:self` 是设备的所有者自己。

上面的配置意思是，所有成员可以访问所有设备的所有端口，但 SSH 只能访问自己的设备。

如果给家里人开了子账号，可以限制他们只能访问特定设备：

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["user1@"],
      "dst": ["nas:445,5000"]
    }
  ]
}
```

这样 user1 只能访问 NAS 的 SMB 和 Web 端口，别的都不行。

## 速度到底怎么样

我测过几次。

从公司连回家里，两台机器都在国内，走的是直连。延迟在二十到四十毫秒之间，取决于公司的网络质量。这个延迟下用 RDP 基本感觉不到卡。

从国外连回来，延迟会高一些，一百多毫秒。看视频还行，操作桌面会有点迟钝。

速度方面，家里的宽带上行是一百兆，实测通过 Tailscale 传输能跑到七八十兆。这个速度对于传文件来说够用了。

如果没打通直连，走中继的话，速度会降到十几兆，延迟也会高一些。所以看 `tailscale status` 里是不是 `direct` 很重要。

## 几个坑

**DNS 冲突**。开启 MagicDNS 之后，它会接管系统的 DNS。如果你有自定义的 DNS 服务（比如 Pi-hole），可能会冲突。可以在 `tailscale up` 的时候加 `--accept-dns=false` 关掉。

**Android 上的省电策略**。很多国产 ROM 会把 Tailscale 的后台进程杀掉，导致连不上。要在系统设置里给它加白名单，允许后台运行。

**子网路由不生效**。多半是没在后台勾选。`--advertise-routes` 只是宣告，还需要在管理后台批准。这一步很多人会漏。

**iOS 上的 VPN 图标常亮**。这是正常的，Tailscale 在 iOS 上是以 VPN 的形式工作的。电量消耗会比平时多一点，但不算严重。

**多网卡环境**。如果机器上有多个网卡（比如同时连了有线和无线），有时候会出现路由混乱。可以用 `--netfilter-mode=off` 关掉自动的防火墙规则，自己配。

## 免费版够不够

免费版叫 Personal，给三个用户、一百个设备。

对于个人用来说，一百个设备根本用不完。三个用户，家里人也够。

付费的 Starter 是六个美元一个月，给更多用户和高级功能（比如设备审批、日志导出）。

我觉得个人用免费版完全够。除非你是在公司里推广，需要审计日志之类的。

## 现在的状态

我现在的设备列表里，一台 Windows 台式机、一台 MacBook、一台 Linux 小主机、两部手机、还有一台香港的 VPS，全都接在里面。

出门在外的时候，随时能连回家里。VPS 上跑的服务也不用暴露公网，直接从 Tailscale 内网访问。

这套东西彻底替代了我之前用的那堆内网穿透工具。而且它是基于标准协议的，万一哪天 Tailscale 这个公司不行了，WireGuard 本身还在，可以自己搭一套。

这种不完全依赖某一家公司的感觉，挺好。
