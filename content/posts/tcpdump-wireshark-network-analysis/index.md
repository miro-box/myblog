---
# ==================== 必填（3 项）====================
title: "一台工控机连不上外网，我用抓包找到了真正的原因"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-03-24T06:08:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从 ping 不通开始，用 tcpdump 抓包、Wireshark 分析，最后定位到一个 MTU 相关的配置问题。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "网络工程"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "tcpdump"
    - "Wireshark"
    - "网络排障"
    - "MTU"

# ==================== 封面图（用不到就保持注释）====================
# 方式 A（推荐）：图片和文章放在同一文件夹（Page Bundle），文件名 cover.webp
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

机房里有一台旧工控机，装的是 Debian，跑着一个小采集程序。

它需要把采集到的数据发到公网的一台服务器上。局域网内一切正常，能 ping 通网关，能访问内网的其他机器。但一访问公网就出问题。

现象很奇怪。`ping 8.8.8.8` 能通，延迟正常。但 `curl https://api.example.com` 就卡住，一直转圈，最后超时。

能 ping 通说明网络层是好的。curl 不行说明问题在更上层。这种"一半通一半不通"的情况，光看配置文件是找不出来的，得抓包。

## 先做基本检查

动手抓包之前，先把能排除的排掉。

```bash
ip addr show
ip route show
cat /etc/resolv.conf
```

IP 是 `192.168.10.55/24`，网关 `192.168.10.1`，路由表里有默认路由指向网关。DNS 是 `223.5.5.5`。

再看 DNS 能不能解析：

```bash
dig api.example.com
```

能解析出 IP。那问题不在 DNS。

试一下 TCP 能不能连：

```bash
nc -zv api.example.com 443
```

卡住，最后超时。

到这一步基本确定，是 TCP 握手的问题。要么是 SYN 发出去了没回来，要么是回来了但被丢了。

## 抓包

工控机上装 tcpdump：

```bash
sudo apt install tcpdump
```

开始抓：

```bash
sudo tcpdump -i eth0 -n -s 0 -w /tmp/capture.pcap 'host api.example.com'
```

参数说明。

`-i eth0` 指定网卡。用 `ip addr` 确认是哪个。

`-n` 不做 DNS 反解，避免抓包的时候卡在解析上。

`-s 0` 是抓完整的包，不截断。默认只抓 262 字节，分析 TLS 的时候不够用。

`-w` 写到文件，方便后面用 Wireshark 分析。

最后那个 `'host api.example.com'` 是过滤表达式。不加的话会抓到所有流量，文件很快变大。

抓的同时在另一个窗口跑 `nc -zv api.example.com 443`，然后 Ctrl+C 停掉抓包。

## 用 Wireshark 打开

把 pcap 文件下载到本地，用 Wireshark 打开。

我一般先用这个过滤器：

```text
tcp.flags.syn == 1
```

只看 SYN 包。能看到发了几个 SYN，有没有收到 SYN-ACK。

结果是这样：

```text
No.  Time      Source          Destination     Info
1    0.000000  192.168.10.55   203.0.113.5     443 → 52134 [SYN] Seq=0
2    1.002341  192.168.10.55   203.0.113.5     443 → 52134 [SYN] Seq=0
3    2.004891  192.168.10.55   203.0.113.5     443 → 52134 [SYN] Seq=0
```

三个 SYN，间隔一秒，没有收到任何 SYN-ACK。这是典型的"对面没收到"或者"对面收到了但回复回不来"。

## 换一个角度验证

既然 ping 能通，说明 ICMP 是双向的。那为什么 TCP 不行。

用 `traceroute` 看看路径：

```bash
traceroute -T -p 443 api.example.com
```

`-T` 是用 TCP SYN 探测，`-p 443` 指定端口。普通的 traceroute 用 UDP 或者 ICMP，可能和实际情况不一样。

结果：

```text
 1  192.168.10.1      0.5 ms
 2  100.64.0.1        3.2 ms
 3  10.0.0.1           5.8 ms
 4  * * *
 5  * * *
...
```

到第三跳之后就全是星号。但 ping 是通的，这就矛盾了。

## 想到 MTU

这里我突然想起一个可能性。

ping 的包很小，默认 56 字节，加上头部也就 84 字节。而 TLS 握手的时候，客户端会发一个 ClientHello，这个包通常有一千多字节。

如果路径上的 MTU 有问题，小包能过，大包过不去。

验证一下：

```bash
ping -M do -s 1472 8.8.8.8
```

`-M do` 是禁止分片，`-s 1472` 是数据部分 1472 字节，加上 ICMP 头部 8 字节和 IP 头部 20 字节，正好是 1500。

如果通，说明 MTU 是 1500。

如果不通，报 `Frag needed and DF set`，说明路径上的 MTU 小于 1500。

我测出来是不通，一直降到了 `-s 1400` 才通。也就是说实际的路径 MTU 在 1428 左右。

## 为什么会这样

工控机所在的那个网段，中间经过了一个 VPN 隧道。VPN 封装会增加额外的头部，导致实际可用的 MTU 变小。

正常情况这不该有问题。TCP 有路径 MTU 发现机制（PMTUD），它会探测路径上最小的 MTU，然后按那个大小发包。

但 PMTUD 依赖 ICMP 的 "Fragmentation Needed" 消息。如果中间有防火墙把这类 ICMP 消息拦了，PMTUD 就失效了。

失效之后，TCP 会用默认的 MSS 发大包，包被丢弃，但发送方不知道，就一直重传，最后超时。

这就能解释为什么 ping 通但 TCP 不通了。ping 的包小，不受影响。

## 确认

回到 Wireshark，看抓到的包里 TCP 的 MSS 值。

打开一个 SYN 包，展开 TCP 层，找 Options，里面有一项 `Maximum segment size`。

我抓到的值是 1460，这是 1500 MTU 下的标准值。

但实际路径 MTU 是 1428，那么 MSS 应该是 1388。

所以每次发出去的数据包都超过路径 MTU，被中间设备丢弃，而且没有 ICMP 反馈回来。

再看有没有重传：

```text
tcp.analysis.retransmission
```

这个过滤器能看到所有重传的包。果然有一堆。

## 解决

有两个办法。

一个是在工控机上手动把 MTU 调小：

```bash
sudo ip link set dev eth0 mtu 1400
```

立刻生效，但重启会丢。要持久化得写进网络配置。

Debian 12 用 systemd-networkd 或者 NetworkManager，看用的是哪个。

如果是 NetworkManager：

```bash
nmcli connection modify "Wired connection 1" 802-3-ethernet.mtu 1400
nmcli connection up "Wired connection 1"
```

如果是 systemd-networkd，在 `.network` 文件里加：

```ini
[Link]
MTUBytes=1400
```

另一个办法是在防火墙上放行 ICMP 的 `fragmentation-needed` 消息。这个是治本的，因为 PMTUD 恢复之后，系统会自己找到正确的 MSS。

但很多时候你控制不了中间的防火墙。所以我两个都做了，MTU 调小是兜底。

## 关于 MSS clamping

还有一个更精细的做法，叫 MSS clamping。它是在路由器上改 TCP 握手时的 MSS 值，让双方按更小的包来发。

Linux 上：

```bash
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN \
  -j TCPMSS --clamp-mss-to-pmtu
```

`--clamp-mss-to-pmtu` 会自动按当前路径的 MTU 算。也可以用 `--set-mss 1388` 写死。

这个一般配在路由器或者 VPN 网关上，因为它需要看到所有经过的 TCP 握手。

我用的是 OpenWrt 的路由器，在防火墙的自定义规则里加了这一条。加了之后，整个局域网里所有走 VPN 的设备都不会再有这个问题。

## 抓包的一些技巧

`tcpdump` 的过滤表达式很强大，用熟了能省很多时间。

只看某个端口：

```bash
tcpdump -i eth0 -n 'port 443'
```

只看某个方向：

```bash
tcpdump -i eth0 -n 'src host 192.168.10.55 and dst port 443'
```

看 HTTP 的内容（明文才有效）：

```bash
tcpdump -i eth0 -n -A 'port 80'
```

`-A` 是以 ASCII 显示内容。看 TLS 的话只能看到加密后的乱码，但能看到握手的结构。

抓包的时候加 `-c` 限制数量，避免文件太大：

```bash
tcpdump -i eth0 -n -c 1000 -w /tmp/capture.pcap
```

还有 `-tttt` 让时间戳带上日期，方便对照日志。

## Wireshark 的几个好用功能

`Statistics -> Flow Graph` 能把整个 TCP 会话画成时序图，一眼就能看出谁先发了什么、哪里断了。

`Statistics -> Conversations` 能看到每个会话的流量统计，找出谁在占带宽。

`Analyze -> Expert Information` 会把所有异常标出来，包括重传、乱序、窗口满、连接重置。这个功能新手特别友好，不用自己一条条看。

`Follow -> TCP Stream` 能把一个会话的完整内容拼出来。分析 HTTP 的时候很有用。

## 后来

MTU 调成 1400 之后，curl 立刻通了。

但这件事让我意识到，那台工控机所在的网段一直有这个隐患，只是之前跑的服务都是小包交互，没暴露出来。

后来我在路由器上加了 MSS clamping，又把整个局域网的 MTU 统一调到了 1400。虽然理论上 1500 更好，但实际用起来，1400 能避免很多莫名其妙的问题。

这个经验在后来配 Tailscale 的时候又用上了。Tailscale 的默认 MTU 是 1280，就是因为它知道自己会被封装在各种网络里，留了足够的余量。

## 一点感受

网络问题最麻烦的地方是，它不报错。

CPU 满了会有告警，磁盘满了会有告警，内存泄漏能看到曲线。但一个包被悄悄丢掉，什么都不会说。你只能看到"连不上"，然后自己去猜。

抓包是唯一能让你看到真相的手段。它不依赖任何日志，不依赖任何配置，就是实实在在地记录网卡上流过了什么。

学会用 tcpdump 和 Wireshark，是我这几年在运维上最值的一件事。
