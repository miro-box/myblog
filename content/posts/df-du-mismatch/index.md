---
title: "df 说盘满了，du 加起来却只有一半，那二十多个 G 去哪了"
date: 2026-10-26T19:45:00+08:00
draft: false
 
description: "小 VPS 磁盘报警，df 和 du 对不上账。依次排除挂载遮盖、inode，最后在一个被我亲手 rm 掉却还在写的日志文件上找到了答案。"
slug: "df-du-mismatch"
categories:
    - "服务器运维"
tags:
    - "Linux"
    - "磁盘"
    - "lsof"
    - "排障"
 
image: "cover.webp"
 
toc: true
hidden: false
comments: false
---
周日晚上快十一点，手机震了一下，Uptime Kuma 的推送：Gitea 挂了，HTTP 502。

我当时躺在床上刷东西，本来想着明天再说，但是又想到这台机子上除了 Gitea 还跑着我的 RSS、一个自己写的书签服务，还有这个博客的评论后端（虽然现在评论已经关了），拖到明天总觉得心里不踏实，就爬起来开了电脑。

机器是年初在某家小厂买的，2 核 2G，40G 的系统盘，Debian 12。便宜，一年一百出头，所以我对它的期待一直很低，只要别动不动就挂就行。

## 先是个很普通的开头

ssh 上去之后第一反应当然是看 Gitea 为什么挂：

```bash
systemctl status gitea
journalctl -u gitea -n 50 --no-pager
```

日志里一堆 `no space left on device`，往 sqlite 里写不进去，起不来。

行吧，盘满了。这种事不算稀奇，小机器上日志、docker 镜像、apt 缓存，哪个都能吃掉几个 G。我顺手 `df -h`：

```text
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1        40G   38G     0 100% /
tmpfs           987M     0  987M   0% /dev/shm
```

注意这个 Avail 是 0，Used 是 38G，加起来不到 40，是因为 ext4 默认给 root 留了 5% 的保留块。这个我知道，不是问题。

问题在后面。

我习惯性地进根目录跑一下 du，找大头：

```bash
cd /
du -xh --max-depth=1 2>/dev/null | sort -h | tail
```

等了一会儿，结果：


```text
310M    ./opt
1.1G    ./usr
1.4G    ./home
2.3G    ./var/lib   （这是我后面单独看的）
5.8G    ./var
14G     .
```

整个根分区 du 出来才 14G。df 说用了 38G。

差了二十四个 G，这就不对了。

## 第一个怀疑：挂载点底下藏了东西

遇到 df 比 du 大很多的情况，我脑子里最先蹦出来的是挂载遮盖。

大概是这么回事：假如 `/data` 本来是个单独的目录，里面已经写了一堆文件，后来你又把另一块盘挂到 `/data` 上，那原来目录里的文件并没有消失，只是被新挂上去的文件系统盖住了，`ls` 看不到，`du` 也扫不到，但它们依然占着根分区的空间。

我之前真干过这事，是在另一台机子上，数据盘忘了挂，服务先起来了，往 `/data` 里写了几个 G，后来补挂了盘，那几个 G 就成了幽灵。

所以先看这台机子有哪些挂载：


```bash
findmnt -lo TARGET,SOURCE,FSTYPE | grep -v -E 'proc|sys|cgroup|tmpfs|devpts|mqueue'
```

```text
TARGET                 SOURCE         FSTYPE
/                      /dev/vda1      ext4
/boot/efi              /dev/vda15     vfat
/var/lib/docker/overlay2/....   overlay
```

除了 docker 的 overlay 就没有别的了，我这台机子压根没挂过别的盘。

不过我还是想确认一下，因为"我记得没有"这种话在运维里最不可靠。有个办法是把根分区再 bind 挂载一次，这样挂载点底下的东西就能看到：


```bash
mkdir /mnt/rootcheck
mount --bind / /mnt/rootcheck
du -xsh /mnt/rootcheck
umount /mnt/rootcheck
```

bind mount 出来的是根文件系统本身，不带子挂载，所以被遮住的内容会露出来。结果是 14G，和之前一样。

这条路排除了。

## 第二个怀疑：inode

df 有两个维度，一个是块，一个是 inode。有时候块没满但是 inode 用光了，同样报 `no space left on device`。不过这次 `df -h` 里块本身就是满的，按理说和 inode 无关，但我还是顺手看了一眼：


```bash
df -i /
```


```text
Filesystem      Inodes  IUsed   IFree IUse% Mounted on
/dev/vda1      2621440 412873 2208567   16% /
```

16%，很健康。

这里说一句题外话，我以前遇到过一次真的是 inode 耗尽的，是某个 PHP 应用的 session 目录里堆了上百万个几百字节的小文件，`df -h` 看一半空着，就是写不进去。那种情况下 `ls` 那个目录都能卡半分钟。这次不是。

## 第三个怀疑：docker

du 我加了 `-x`，意思是不跨文件系统。docker 的 overlay2 虽然在 `/var/lib/docker` 下面，但它自己的 merged 目录是 overlay 挂载，`-x` 会跳过它们，但 `/var/lib/docker/overlay2//diff` 这些层本身是普通目录，是会被统计到的。所以 docker 的镜像和层其实已经算在那个 14G 里了。

保险起见我还是问了一下 docker 自己：


```bash
docker system df
```


```text
TYPE            TOTAL   ACTIVE   SIZE      RECLAIMABLE
Images          9       6        3.2GB     1.1GB (34%)
Containers      7       6        412MB     0B
Local Volumes   5       4        1.9GB     310MB
Build Cache     0       0        0B        0B
```

加起来五六个 G，对得上，也远远凑不够那 24G。

容器的 json 日志呢？`/var/lib/docker/containers/*/*-json.log`，这个也是 docker 目录下的普通文件，du 会算。我又单独 `ls -lh` 了一遍，最大的是 Uptime Kuma 的，80 多 M。不是它。

到这里我已经折腾了二十来分钟了，有点烦。

## 想起来一件事

我坐在那儿盯着屏幕，忽然想起上个周末干过的一件事。

有个小爬虫脚本，抓一些我关注的站点的更新，用 `nohup python3 crawl.py > crawl.log 2>&1 &` 挂在后台跑。上周末我发现 crawl.log 已经长到好几个 G 了（脚本里有个 debug 输出忘了关，每抓一个页面就把整个 HTML 打一遍），我当时看了一眼，想着反正不重要，直接：

```bash
rm ~/crawl/crawl.log
```

然后就去干别的了。

没有重启脚本。

这在 Linux 下是个经典的坑，但我居然自己踩了。`rm` 删的只是目录项，也就是文件名到 inode 的那条链接。只要还有进程打开着这个文件，inode 和它的数据块就不会被释放，进程照样往里写，只是你再也在任何目录里找不到这个文件了。

所以 du 看不见它，因为 du 是顺着目录树往下走的，目录树里已经没有这个名字了。df 看得见，因为 df 问的是文件系统，文件系统知道这些块还被占着。

这就解释了为什么两边对不上。

## 验证一下

`lsof` 有个选项专门找这种东西，`+L1` 的意思是列出链接数小于 1 的已打开文件，也就是已删除但还开着的：

```bash
lsof +L1 2>/dev/null | head
```

```text
COMMAND   PID USER   FD   TYPE DEVICE   SIZE/OFF NLINK     NODE NAME
python3  1873 zhou    1w   REG  254,1 24831209472     0   915487 /home/zhou/crawl/crawl.log (deleted)
python3  1873 zhou    2w   REG  254,1 24831209472     0   915487 /home/zhou/crawl/crawl.log (deleted)
```

SIZE 那一列 24831209472，除以 1024 三次，23.1G。

就是它。后面还跟着一个很显眼的 `(deleted)`。

fd 1 和 fd 2 是标准输出和标准错误，当初重定向的时候 `2>&1` 让它们指向了同一个文件。所以同一个文件开了两次，lsof 列出两行，但占的空间只有一份，不要重复加。

一周的时间，这个脚本往一个我以为已经不存在的文件里写了二十三个 G。我现在回头想想，那个 debug 输出的量大得有点离谱，可能当时那个站点对爬虫做了什么重定向循环，脚本一直在重试。反正这是另一个问题了。

## 怎么处理

有两个办法。

最直接的是把进程杀了。进程一退出，所有 fd 关闭，内核发现这个 inode 没有任何引用，就会释放空间。


```bash
kill 1873
```

但是我这次想先试试不杀进程的做法，原因也没什么，就是想验证一下，顺便以后遇到不能随便杀的进程也有个预案。

Linux 的 `/proc//fd/` 下面有这个进程所有打开的文件描述符，每一个都是一个符号链接，即便指向的文件已经被删除，通过这个链接依然能访问到它。所以可以直接把它截断：


```bash
: > /proc/1873/fd/1
```

那个冒号是 shell 的空命令，加上重定向就是把文件截成 0 字节。也可以用 `truncate -s 0 /proc/1873/fd/1`，效果一样。

跑完之后马上 `df -h`：


```text
/dev/vda1        40G   14G   24G  38% /
```

空间一下就回来了。

这里有个要注意的点。我截断的是 fd 1，但 fd 2 指向同一个文件，同一个 inode。如果进程是用 `O_APPEND` 打开的（shell 的 `>` 重定向其实不是，它是 `O_TRUNC`，不带 append），那截断之后写入位置会回到文件末尾，也就是新的 0；但如果不是 append 模式，进程内部的文件偏移量还停在原来 23G 的位置，下一次写入的时候会从 23G 那里开始写，文件系统会产生一个稀疏文件，大小显示还是 23G，但实际块占用很小。

我这次用的是 `>`，没带 append，所以其实就是后面那种情况。我又跑了一次 `ls -l /proc/1873/fd/1`，大小显示又变回了几百兆，因为脚本还在继续写，偏移量不对，形成了空洞。实际占的磁盘块不多，所以空间没有问题，但这个文件的"表面大小"会很吓人。

说得有点绕。总之如果要长期这么做，应该用 `>>` 重定向启动脚本，这样 truncate 完了偏移量会自己跟到文件末尾。

我最后还是把那个脚本杀掉了，没打算留着它，重新启动的时候改成了：


```bash
nohup python3 crawl.py >> ~/crawl/crawl.log 2>&1 &
```

顺便把那个愚蠢的 debug 输出删了。

## Gitea 还是没起来

空间回来之后我 `systemctl restart gitea`，还是起不来，报 `database disk image is malformed`。

这个我一点都不意外，sqlite 在写到一半磁盘满了，很可能把库写坏了。

好在 Gitea 每天凌晨有个备份，是我之前随手加的 cron，用 `gitea dump` 打包到 `/home/zhou/backup/`。去看了一下，昨天凌晨的包是正常的，3.1M。


```bash
systemctl stop gitea
cp /var/lib/gitea/data/gitea.db /var/lib/gitea/data/gitea.db.broken
sqlite3 /var/lib/gitea/data/gitea.db "PRAGMA integrity_check;"
```

输出了一大堆 `*** in database main ***` 和 `Page xxx: btree page is out of order` 之类的，确实坏了。

我先试了一下 `.recover`：


```bash
sqlite3 gitea.db.broken ".recover" | sqlite3 gitea.db.recovered
```

恢复出来的库能打开，`integrity_check` 也是 ok。但我不太敢直接用它，因为 `.recover` 对丢失的页面是尽力而为，我没法确认有没有悄悄丢了行。最后还是选了稳一点的做法，用昨天的备份还原，然后把昨天备份之后的提交让自己的几个仓库重新 push 一遍（仓库本身是文件系统里的 git 目录，不在 sqlite 里，没有损坏，只是 issue、评论这些元数据可能丢了一天的内容）。

查了一下，实际上我昨天到今天没有开过 issue，所以什么都没丢。运气。

十二点过十分的时候 Gitea 重新能打开了。

## 之后加的两样东西

这事之后我加了两样东西，都不复杂。

第一个是磁盘告警。Uptime Kuma 能做 push 类型的监控，我就写了个很短的脚本放在 cron 里，每五分钟跑一次，用量超过 85% 就不推送心跳，Kuma 那边超时就会告警：


```bash
#!/bin/bash
used=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if [ "$used" -lt 85 ]; then
    curl -fsS -m 10 "https://kuma.example.com/api/push/xxxxxxxx?status=up&msg=${used}%25" >/dev/null
fi
```

之前我只监控了服务能不能访问，等到服务挂了磁盘早就满了。这次从报警到发现原因其实还算快，但本来可以更早的，一周前它就开始涨了。

第二个是给后台脚本一个正经的归宿。以后这类东西一律写成 systemd 的 service，日志交给 journald，journald 本身有大小限制（`SystemMaxUse`），不用我再操心。`nohup` 加重定向这种做法，我以前觉得方便，现在觉得它方便的地方恰好就是它危险的地方，因为它没有任何人替你管那个文件。

## 顺便记一下以后的排查顺序

下次再遇到 df 和 du 对不上，我大概按这个顺序来：

1. `lsof +L1`，最快，一条命令，十有八九是它
2. `df -i`，看是不是 inode
3. bind mount 一下根，看挂载遮盖
4. 再去翻 docker、日志这些

我这次顺序反了，先去查了挂载和 docker，最后才想起来 lsof。其实如果当时多想一秒，就应该先怀疑"有没有什么东西在往已经没有名字的地方写"，毕竟 du 看不到的东西，本质上就只有那么几类。

另外那个被我 rm 掉的 crawl.log，名字至今还躺在我 shell 的 history 里，`rm ~/crawl/crawl.log` 那一行，我现在每次 ctrl+r 都能看到它，像个纪念碑。