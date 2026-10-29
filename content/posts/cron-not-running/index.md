---
title: "脚本手动跑得好好的，放进 crontab 就是不动"
date: 2026-10-25T19:57:00+08:00
draft: false

description: "一个备份脚本在终端里一切正常，丢给 cron 之后连个响声都没有。记录 PATH、百分号、日志去哪了这几个坑，还有 cron.d 里文件名的小脾气。"
slug: "cron-not-running"
categories:
    - "服务器运维"
tags:
    - "Linux"
    - "cron"
    - "Shell"
    - "排障"

image: "cover.webp"

toc: true
hidden: false
comments: false
---

先说结论的话，这篇其实没什么高深的东西，全是 cron 的基本脾气。但我是真的被它折腾了一个周末，所以还是想写下来，哪天再遇到能少走点弯路。

事情的起因是我想给自己那台小服务器做个像样的备份。之前的做法是想起来了就手动 `pg_dump` 一下，然后 scp 回家里的电脑，这种"想起来了"的备份，说实话跟没有差不多。上个月有一次手滑把一个库里的表 drop 了，翻了半天发现最近一次备份是四十多天前的，才下决心搞个自动的。

## 脚本本身

思路很简单：每天凌晨导出一份数据库，压缩，用 rclone 传到一个对象存储的桶里，本地只留最近七天的。

我把它放在 `/home/zhou/bin/backup.sh`，大概长这样：

```bash
#!/bin/bash
set -e

DIR=/home/zhou/backup
NAME=pg-$(date +%Y%m%d-%H%M).sql.gz

mkdir -p "$DIR"
pg_dump -U zhou -h 127.0.0.1 mydb | gzip > "$DIR/$NAME"
rclone copy "$DIR/$NAME" mybucket:backup/pg/
find "$DIR" -name 'pg-*.sql.gz' -mtime +7 -delete

echo "$(date) done $NAME"
```

pg 的密码放在 `~/.pgpass` 里，rclone 的配置在 `~/.config/rclone/rclone.conf`，这两个都是我手动配好的，没毛病。

手动跑：

```bash
bash /home/zhou/bin/backup.sh
```

几秒钟之后输出一行 `Sat Oct 24 23:41:07 CST 2026 done pg-20261024-2341.sql.gz`，登上对象存储的网页后台一看，文件也确实在那儿。

好，脚本没问题。接下来丢给 cron。

## 然后什么都没发生

```bash
crontab -e
```

加了一行：

```text
30 3 * * * /home/zhou/bin/backup.sh
```

这里先吐槽一下，我最开始忘了给脚本加执行权限，不过这个比较明显，第二天看不到文件之后我很快就想到了，`chmod +x` 一下就行。

加完权限之后我没有等到第二天凌晨，而是把时间改成了"两分钟之后"来测试，一边盯着一边等。

两分钟过去了，桶里没有新文件，本地 backup 目录里也没有。

`crontab -l` 看了一眼，条目确实在。`systemctl status cron` 也是 active (running)。

到这里我有点懵，因为按我的理解，要么执行成功要么应该有个报错，而眼前是什么都没有，不成功也不失败，像是掉进了黑洞。

## cron 到底有没有跑它

后来我想明白了，第一步其实不该猜，应该先确认 cron 有没有真的去执行那一行。

Debian 12 默认不装 rsyslog 了，所以老教程里说的 `/var/log/syslog` 在我这儿根本不存在。cron 的日志要去 journal 里找：

```bash
journalctl -u cron --since "10 minutes ago" --no-pager
```

```text
Oct 25 10:12:01 vps CRON[48213]: (zhou) CMD (/home/zhou/bin/backup.sh)
Oct 25 10:12:01 vps CRON[48212]: (CRON) info (No MTA installed, discarding output)
```

这两行信息量其实很大。

第一行说明 cron 确实在 10:12 把命令拉起来了，所以调度这块没问题，不是 cron 服务的毛病，也不是时间写错了。

第二行是关键：`No MTA installed, discarding output`。cron 有个设定，任务如果有任何标准输出或者标准错误，它会尝试用邮件发给任务所属用户。我这台机器没装邮件服务，所以所有的输出，不管是成功的提示还是报错，都被它丢掉了。

也就是说脚本其实可能报错了，只是我完全看不到。

这个设计我是能理解的，毕竟 cron 诞生的年代，每台机器都有本地邮件系统。但放到今天，一个没装 MTA 的小 VPS 上，这等于默认静音。

## 先让它说话

解决办法很土：把输出重定向到一个文件里。

```text
30 3 * * * /home/zhou/bin/backup.sh >> /home/zhou/backup/cron.log 2>&1
```

再等一次。这次文件里有东西了：

```text
/home/zhou/bin/backup.sh: line 9: rclone: command not found
```

终于。

顺带发现一个事，因为我脚本里写了 `set -e`，rclone 失败之后脚本直接退出了，所以后面的 find 清理也没执行，最后那句 `echo done` 当然也没有。pg_dump 倒是成功了，本地目录里其实有那个 `.sql.gz`，只是我之前没注意到，因为我是直接去桶里看的。

## PATH 的问题

`rclone: command not found`，可我在终端里明明能用。

`which rclone` 一下：

```text
/usr/local/bin/rclone
```

它装在 `/usr/local/bin`。而 cron 启动任务的时候，环境变量非常干净，PATH 默认只有 `/usr/bin:/bin`，没有 `/usr/local/bin`，更别说我在 `.bashrc` 里加的那些乱七八糟的路径了。cron 也不会去读 `.bashrc` 或者 `.profile`，因为它根本不是个登录 shell，甚至默认连 bash 都不是，用的是 `/bin/sh`。

可以自己验证一下 cron 里的环境到底长什么样，加一行：

```text
* * * * * env > /tmp/cronenv.txt
```

一分钟后看 `/tmp/cronenv.txt`：

```text
SHELL=/bin/sh
PWD=/home/zhou
LOGNAME=zhou
HOME=/home/zhou
PATH=/usr/bin:/bin
```

就这么几行。测完记得把这条删掉，不然它每分钟写一次，我就忘过一回，两天之后才想起来。

解决办法有三种，我都试了：

1. 脚本里用绝对路径，`/usr/local/bin/rclone copy ...`
2. 脚本开头自己设 `export PATH=/usr/local/bin:/usr/bin:/bin`
3. 在 crontab 文件最上面写一行 `PATH=/usr/local/bin:/usr/bin:/bin`

我最后选了第三种加第一种，crontab 顶上写 PATH，脚本里涉及的关键命令也不偷懒。倒不是不信任 PATH，而是想着过两年我自己都忘了这个脚本是靠 crontab 里那一行才能跑的，换台机器或者换个用户，又会掉进同一个坑。脚本自己带着依赖，心里踏实些。

顺手把 `SHELL=/bin/bash` 也写进了 crontab 顶部，因为我脚本里偶尔会用到一些 bash 才有的写法，万一以后直接在 crontab 行里写命令，不想再踩 `sh` 的坑。

## 百分号，一个更阴险的东西

PATH 改好之后，我以为这事结束了。结果它又给了我一个惊喜。

我想让日志文件按日期分开，就把重定向那段改成了：

```text
30 3 * * * /home/zhou/bin/backup.sh >> /home/zhou/backup/cron-$(date +%Y%m%d).log 2>&1
```

然后这一条又不动了，而且这次连 cron.log 都没有新东西。journal 里是：

```text
CRON[51002]: (zhou) CMD (/home/zhou/bin/backup.sh >> /home/zhou/backup/cron-$(date +)
```

对，命令在 `+` 那里被截断了，后面的 `%Y%m%d)...` 没了。

这是 cron 的一个老规矩：crontab 里，没有被转义的 `%` 会被当成换行符，第一个 `%` 之前的部分是命令，之后的部分会被当作标准输入喂给这个命令。所以上面这行实际被切成了命令 `... $(date +`，当然 shell 会报语法错误（括号没闭合），这个错误本来该通过邮件发出来，但是——前面说过了，我没装 MTA。

解决办法是转义：

```text
30 3 * * * /home/zhou/bin/backup.sh >> /home/zhou/backup/cron-$(date +\%Y\%m\%d).log 2>&1
```

每个 `%` 前面加反斜杠。

其实我脚本里的 `date +%Y%m%d-%H%M` 一直没事，是因为那是在脚本文件里，不是在 crontab 里，cron 不会去解析脚本内容。这个区别我之前是模模糊糊知道的，真撞上了才算记住。

更省事的做法是干脆别在 crontab 行里写这种东西，把日志重定向的逻辑放进脚本里，crontab 只留一个干净的路径，这样以后也不会再因为一个百分号被坑。我后来就改成了这样，在脚本开头加了：

```bash
exec >> "/home/zhou/backup/cron-$(date +%Y%m%d).log" 2>&1
```

`exec` 不带命令的时候，作用是把当前 shell 之后所有的输出都重定向过去。这样脚本里随便 echo，都会进日志。

## 还有一件我没踩但是差点踩的事

查资料的过程中看到别人提到，如果不是放在用户的 crontab 里，而是想放在 `/etc/cron.d/` 或者 `/etc/cron.daily/` 里，还有另外几个规矩，我当时想着要不要换成这种方式，所以顺便试了一下。

`/etc/cron.daily/` 这种目录是靠 `run-parts` 来跑的。Debian 上的 run-parts 对文件名有要求，只接受字母、数字、下划线和连字符，带点号的会被直接跳过。所以我把脚本命名成 `backup.sh` 放进 `/etc/cron.daily/` 之后，它永远不会被执行，连个提示都没有。改名成 `backup` 才行。

可以用 `run-parts --test /etc/cron.daily` 来看哪些文件会被执行，我的 `backup.sh` 确实没出现在列表里。

`/etc/cron.d/` 又不一样，那里面放的是 crontab 格式的文件，和用户 crontab 的区别是时间后面要多写一个用户名：

```text
30 3 * * * zhou /home/zhou/bin/backup.sh
```

忘了写用户名的话，cron 会把脚本路径当成用户名，然后报个莫名其妙的错。文件名也是同样不能带点号。另外这类文件要求属主是 root，权限不能让其他人可写，文件结尾要有换行。

我最后还是没用这两个地方，就用的用户自己的 crontab。理由很朴素：备份是我自己一个人的事，放在自己用户下，出了问题 `crontab -l` 一眼就能看到，不用去 `/etc` 里翻。

## 最终的样子

crontab：

```text
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

30 3 * * * /home/zhou/bin/backup.sh
```

脚本：

```bash
#!/bin/bash
set -eu -o pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

DIR=/home/zhou/backup
exec >> "$DIR/cron-$(date +%Y%m%d).log" 2>&1

NAME=pg-$(date +%Y%m%d-%H%M).sql.gz

mkdir -p "$DIR"
pg_dump -U zhou -h 127.0.0.1 mydb | gzip > "$DIR/$NAME"
/usr/local/bin/rclone copy "$DIR/$NAME" mybucket:backup/pg/
find "$DIR" -name 'pg-*.sql.gz' -mtime +7 -delete
find "$DIR" -name 'cron-*.log' -mtime +30 -delete

echo "$(date) done $NAME"
```

这里我还加了 `pipefail`，是因为中途发现一个很不好的事：`pg_dump ... | gzip > file` 这个管道，如果 pg_dump 失败了，gzip 照样成功退出，整条命令的返回值是最后一个的，也就是 0。结果会得到一个 20 字节的空压缩包，脚本还以为一切正常，并且把这个空文件传到桶里去。没有 `pipefail` 的话，你的备份可能一直是空的，而你完全不知道。

我是故意把 pg 的密码改错了测了一次才发现这个的。改错之后脚本打出 `done`，桶里多了一个 20 字节的文件。当时看着那个文件，背后有点发凉。

## 最后补一个监控

日志写进文件了，但没人会每天去看日志。我又加了个很粗糙的东西：脚本最后一行成功之后，对 Uptime Kuma 的一个 push 地址 curl 一下。

```bash
curl -fsS -m 10 "https://kuma.example.com/api/push/xxxxxxxx?status=up&msg=ok" >/dev/null
```

Kuma 那边设成 26 小时没收到心跳就报警。这样不管是 cron 没触发、脚本中途失败、还是机器直接挂了，我都会收到一条通知。比起让脚本失败时去发邮件，反向地"没成功就报警"可靠得多，因为失败的方式太多了，很难每一种都覆盖到，但成功只有一种。

昨天夜里它第一次完整自己跑完了。早上起来我手机上没有任何通知，打开桶看了一眼，有个三点三十一分的文件，大小 3.2M。

挺好。就是这几个 cron 的坑，都不大，凑在一起够恶心的。