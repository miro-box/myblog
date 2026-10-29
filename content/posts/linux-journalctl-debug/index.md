---
# ==================== 必填（3 项）====================
title: "journalctl 用熟了之后，排查问题快了一大截"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-01-01T13:22:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从只会 journalctl -xe 到能按时间、按服务、按优先级精准过滤，顺带把日志持久化和磁盘占用也处理了。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Linux"
    - "journalctl"
    - "日志"
    - "排错"

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

刚开始用 systemd 那会儿，我对 `journalctl` 的理解就停在 `journalctl -xe` 这一个命令上。

出问题了就敲一下，刷出一大屏东西，然后肉眼从头翻。翻到中间发现前面还有线索，又得往上滚。滚着滚着忘了自己要找什么。

后来有一台机器的 nginx 每天早上六点准时挂一次，重启就好，第二天照旧。我靠翻日志翻了三天没找到原因，最后是同事提醒我，用 `--since` 把时间窗缩到五分钟。

那次之后我才认真学了这套工具。

## 它到底存在哪儿

先搞清楚一件事，journald 的日志默认是存在内存里的。

准确说是存在 `/run/log/journal/`，这是 tmpfs，重启就没了。所以很多人第一次用的时候会觉得，日志怎么只有今天的。

想让它持久化，改一下配置：

```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
```

目录一建好，journald 下次启动就会自动把日志写进 `/var/log/journal/`，同时把 `/run` 里的搬过去。

这一步很重要。我见过太多人排查"昨天晚上的故障"，结果发现日志已经被重启清掉了。

## 时间过滤是最有用的一个

`--since` 和 `--until` 支持很自然的写法：

```bash
journalctl --since "2025-01-01 13:00:00"
journalctl --since "1 hour ago"
journalctl --since yesterday --until "today 06:00"
journalctl --since "-30min"
```

我常用的组合是这样：

```bash
journalctl --since "today 05:50" --until "today 06:10" -u nginx
```

意思是看今天早上六点前后二十分钟里 nginx 的日志。那次定时挂掉的问题，就是这么定位的。日志里有一段明显的 `worker process exited on signal 9`，再往前看，是 OOM killer 干的。

这个时间窗的思路比翻全部日志有用得多，尤其是日志量大的机器。

## 按服务看

`-u` 后面跟 unit 名：

```bash
journalctl -u nginx -u php8.2-fpm
```

可以跟多个，它会把两个服务的日志按时间交错排在一起。排查"nginx 502 到底是不是 php-fpm 挂了"这种问题，这个写法特别顺手。

看某个服务的全部历史：

```bash
journalctl -u mariadb --no-pager | less
```

`--no-pager` 是让它别调用 `less`，直接输出，方便管道到 grep。

## 按优先级过滤

`-p` 参数，数字越小越严重：

```text
0  emerg
1  alert
2  crit
3  err
4  warning
5  notice
6  info
7  debug
```

```bash
journalctl -p err -b
```

这个是看本次启动以来的所有错误及以上级别。`-b` 是 `--boot` 的缩写，只显示当前这次开机之后的。

`-p` 的行为有个细节，它是"该级别及以上"，也就是 `-p err` 会显示 err、crit、alert、emerg。所以只看 err 的话，得写 `-p err..err`。

## 按启动次数

`-b` 后面可以跟数字：

```bash
journalctl -b        # 本次启动
journalctl -b -1     # 上次启动
journalctl -b -2     # 上上次
journalctl --list-boots   # 列出所有启动记录
```

`--list-boots` 的输出长这样：

```text
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -2 3f2a...                          Mon 2024-12-30 08:12:33 CST Sun 2024-12-31 22:01:09 CST
 -1 8b1c...                          Tue 2024-12-31 22:15:44 CST Wed 2025-01-01 09:33:12 CST
  0 a9d4...                          Wed 2025-01-01 09:40:02 CST Wed 2025-01-01 13:20:55 CST
```

这个表在排查"上次重启之前发生了什么"的时候特别好用。比如机器莫名其妙重启了，`journalctl -b -1 -p err` 就能看到重启前的最后几条错误。

前提是日志持久化了。没持久化的话，`-b -1` 是空的。

## 按进程和 PID

```bash
journalctl _PID=1234
journalctl _COMM=nginx
```

下划线开头的这些是 journald 的字段名。常用的几个：

`_PID` 进程号，`_UID` 用户 ID，`_GID` 组 ID，`_COMM` 命令名，`_EXE` 可执行文件路径，`_SYSTEMD_UNIT` 所属的服务。

`_COMM` 和 `-u` 的区别是，`-u` 是按 systemd 单元过滤，`_COMM` 是按进程名过滤。一个服务可能有多个进程，也可能有不属于任何单元的进程。

## 输出格式

默认的输出带颜色和缩写，人看方便，但贴到别处就乱了。

`-o` 参数可以换格式：

```bash
journalctl -o json-pretty -u nginx -n 1
journalctl -o short-iso -u nginx
journalctl -o cat -u nginx
```

`json-pretty` 能看到所有字段，调试的时候很有用。比如想看一条日志的所有元数据：

```bash
journalctl -o json-pretty -n 1 | jq .
```

会输出 `_HOSTNAME`、`_TRANSPORT`、`SYSLOG_IDENTIFIER`、`PRIORITY` 一大堆字段。了解这些字段名，你才能写出精确的过滤条件。

`short-iso` 把时间戳改成 ISO 8601 格式，带时区。给别人发日志的时候用这个，不会因为时区不同产生误解。

`cat` 只输出消息内容，没有时间戳和主机名。适合管道给别的工具处理。

## 实时跟踪

```bash
journalctl -f
journalctl -f -u nginx
journalctl -f -p warning
```

`-f` 就是 follow，类似 `tail -f`。调试的时候开一个窗口挂着，另一边操作，看日志实时滚出来。

`-f` 加 `-p warning` 这个组合我经常用，它能过滤掉大量无关的 info 级别噪音，只留下值得看一眼的东西。

## 磁盘占用和清理

```bash
journalctl --disk-usage
```

我第一次跑的时候看到 1.8G，吓一跳。

默认的上限是文件系统的百分之十，但有最小值 4G 的兜底。也就是说，如果你的盘小于 40G，日志最多能占到 4G。这在 20G 的小机器上是灾难。

改 `/etc/systemd/journald.conf`：

```ini
[Journal]
Storage=persistent
SystemMaxUse=200M
SystemMaxFileSize=50M
SystemKeepFree=1G
MaxRetentionSec=1month
```

`SystemMaxUse` 是总量上限，`SystemMaxFileSize` 是单个文件上限，`SystemKeepFree` 是至少给文件系统留多少空间，`MaxRetentionSec` 是时间上限。

改完重启：

```bash
sudo systemctl restart systemd-journald
```

立刻清理到上限：

```bash
sudo journalctl --vacuum-size=200M
sudo journalctl --vacuum-time=30d
```

这两个是手动触发的，不用等自动轮转。

## 权限这件事

普通用户默认只能看自己的日志。

```bash
journalctl
```

会输出 `No journal files were found` 或者只显示很少的内容。

要看得全，要么 `sudo`，要么把自己的用户加进 `systemd-journal` 组：

```bash
sudo usermod -aG systemd-journal $USER
```

加完要重新登录才生效。这个组是在安装 systemd 的时候建的，默认存在。

## 一个真实的排查过程

说说那次早上六点定时挂的问题，完整走一遍。

先确认现象：

```bash
journalctl -u nginx --since "today 05:55" --until "today 06:05"
```

看到 nginx 在 06:00:12 报了 `worker process exited on signal 9`，然后是 `no live upstreams`。

signal 9 是 SIGKILL，普通信号杀不掉它，只有 OOM killer 或者有人手动 `kill -9`。

看内核日志：

```bash
journalctl -k --since "today 05:55" --until "today 06:05"
```

`-k` 是 `--dmesg` 的简写，只看内核消息。果然：

```text
Out of memory: Killed process 12345 (nginx) total-vm:...
```

那就清楚了，是内存不够。问题是为什么每天早上六点。

再查那个时间点有什么在跑：

```bash
journalctl --since "today 05:58" --until "today 06:02" | grep -i cron
```

找到了，`/etc/cron.d/backup` 在 06:00 跑备份，`tar` 加 `gzip` 压缩的时候把内存吃满了。

解决办法是给备份脚本加 `nice` 和 `ionice`，再把 nginx 的 `worker_processes` 调小一点。改完第二天早上六点，一切正常。

整个过程大概十分钟。如果只会 `journalctl -xe` 从头翻，估计得翻半天。

## 几个小技巧

日志里有敏感信息的时候，`--no-hostname` 可以去掉主机名。

`journalctl -n 50` 是只看最后五十行，比 `tail -n 50` 快，因为它是从索引里直接取的。

`journalctl --verify` 可以检查日志文件的完整性。文件系统出过问题之后跑一下，能发现有没有损坏的段。

还有一个 `journalctl -u nginx -o json | jq -r 'select(.PRIORITY=="3") | .MESSAGE'`，用 jq 处理 json 格式，可以写出很复杂的过滤逻辑。日志量大的时候比 grep 好用。

## 现在

我现在的习惯是，遇到任何服务异常，第一步永远是：

```bash
journalctl -u <服务名> --since "-30min" -p warning --no-pager
```

这条命令基本能覆盖八成的场景。剩下的两成，才需要去翻更早的日志或者换过滤条件。

工具本身不复杂，关键是要知道它在哪儿、按什么维度组织。把时间、单元、优先级这三个维度用熟了，排查效率的提升是立竿见影的。
