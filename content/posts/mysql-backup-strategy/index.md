---
# ==================== 必填（3 项）====================
title: "数据库备份这件事，我从手动导出做到全自动"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-03-20T03:45:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从小站的 mysqldump 讲到全量加增量的组合，包括一致性、压缩加密、异地存放和真正能恢复的验证方法。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "MySQL"
    - "MariaDB"
    - "备份"
    - "Shell"

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

我一直觉得备份是件很枯燥的事。

直到有一次，我在服务器上执行了一条 `DELETE FROM comments WHERE id > 100`，本来想删测试数据，结果忘了自己不在测试库。

那条语句跑完，生产库少了两千多条评论。

我坐在那儿愣了大概十秒钟，然后想起来，昨天晚上的备份还在。

从那次之后，我对备份的态度完全变了。

## 备份到底要解决什么问题

先说清楚，备份不是"把数据复制一份"这么简单。

它要能应对几种不同的场景。

误删数据，需要恢复到删除前的某个时间点。

磁盘损坏，需要换台机器把服务重新拉起来。

程序 bug 写坏了数据，需要回滚到某个版本。

被勒索软件加密，需要有离线副本。

这几种场景对备份的要求不一样。误删需要时间点密集，磁盘损坏需要副本在别的机器上，勒索需要副本不可写。

所以一个靠谱的方案，至少要有三个特征。定期自动跑，副本存在别的地方，而且真的能恢复。

最后一条最容易被忽略。很多人备份跑了半年，真要恢复的时候才发现文件是空的。

## 最基础的 mysqldump

小站用这个就够了。

```bash
mysqldump \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  --events \
  --default-character-set=utf8mb4 \
  -u root -p \
  myapp > /backup/myapp-$(date +%F).sql
```

几个参数都值得说一下。

`--single-transaction` 是关键。它在 InnoDB 上开一个一致性快照，导出过程中不会锁表，业务可以继续写。导出来的数据是开始那一刻的状态，不会出现前后不一致。

注意这个参数只对 InnoDB 有效。如果你的表还有 MyISAM，那就得用 `--lock-tables`，会锁表，业务会卡。

`--quick` 让 mysqldump 一行一行往客户端发，而不是全部读进内存。大表不加这个，很容易把内存撑爆。

`--routines --triggers --events` 这三个，默认是不导出的。不加上，恢复之后存储过程、触发器、定时任务全都没了。我第一次恢复的时候就踩了这个坑，恢复完发现定时清理任务不跑了。

`--default-character-set=utf8mb4` 防止中文乱码。如果源库是 utf8mb4，导出的时候不指定，有时候会被转成 latin1。

## 加压缩和加密

纯 sql 文件很大，压缩一下能小到十分之一：

```bash
mysqldump ... | gzip > /backup/myapp-$(date +%F).sql.gz
```

如果数据里有敏感信息，还得加密：

```bash
mysqldump ... | gzip | openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:/etc/backup.key > /backup/myapp-$(date +%F).sql.gz.enc
```

`-pbkdf2` 是让 openssl 用更安全的密钥派生方式，不加的话会有警告。

`-pass file:` 从文件读密码，比写在命令行里安全，因为命令行参数在 `ps` 里能看到。

`/etc/backup.key` 权限设成 600，只有 root 能读。

恢复的时候：

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/etc/backup.key -in backup.sql.gz.enc | gunzip | mysql -u root -p myapp
```

## 写成脚本

手动跑总会忘，得自动化。

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR=/backup/mysql
KEEP_DAYS=14
DATE=$(date +%F_%H%M)
DB=myapp

mkdir -p "$BACKUP_DIR"

mysqldump \
  --single-transaction --quick --routines --triggers --events \
  --default-character-set=utf8mb4 \
  -u root -p"$(cat /etc/mysql/backup.pass)" \
  "$DB" | gzip > "$BACKUP_DIR/${DB}-${DATE}.sql.gz"

# 校验文件不是空的
SIZE=$(stat -c %s "$BACKUP_DIR/${DB}-${DATE}.sql.gz")
if [ "$SIZE" -lt 1024 ]; then
  echo "备份文件异常小：$SIZE 字节" >&2
  exit 1
fi

# 清理过期
find "$BACKUP_DIR" -name "${DB}-*.sql.gz" -mtime +$KEEP_DAYS -delete

echo "备份完成：${DB}-${DATE}.sql.gz ($SIZE 字节)"
```

`set -euo pipefail` 这三件套一定要加。`-e` 让任何命令失败就退出，`-u` 让未定义变量报错，`-o pipefail` 让管道里任何一个环节失败都能被捕获。

没有 `pipefail` 的时候，`mysqldump | gzip` 如果 mysqldump 失败了，整个管道还是返回成功，因为 gzip 成功了。这是很隐蔽的坑，我吃过一次，备份文件是空的，脚本还报成功。

那个 `SIZE` 校验也是必须的。空文件、截断的文件，靠退出码是发现不了的。

## 用 cron 跑

```bash
sudo tee /etc/cron.d/mysql-backup <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

30 3 * * * root /usr/local/bin/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1
EOF
```

每天凌晨三点半跑。这个时间业务量最低。

`cron.d` 的格式比 `crontab -e` 多一个用户字段，就是 `root` 那个位置。写错了会不执行，而且没有任何提示。

## 增量备份

全量备份对数据量小的站够用，但如果库有几个 G，每天全量就不太现实了。

增量有两种做法。

一种是 binlog。MySQL 的 binlog 记录了所有数据变更，配上定期全量，可以把数据恢复到任意时间点。

先确认 binlog 开着：

```sql
SHOW VARIABLES LIKE 'log_bin';
```

如果是 `ON`，那 binlog 文件在 `datadir` 下面，名字形如 `mysql-bin.000001`。

备份 binlog：

```bash
mysqlbinlog --read-from-remote-server --host=127.0.0.1 --user=repl --password=xxx \
  --raw --stop-never mysql-bin.000001
```

这个会持续拉取新的 binlog。实际用的时候一般配合 `--result-file` 和定期切换。

另一种是 `--incremental` 配合 `xtrabackup`。Percona 的工具，支持热备和增量，适合大库。不过它需要单独装，配置也复杂一些。

我这个小站没到那个量级，用的还是每天全量。库里不到一百兆，压缩完十几兆，存三十天也就四百多兆。

## 存到别的地方

本地备份只能防误删，防不了磁盘坏或者机器没了。

所以至少要有两份，一份在本机，一份在别处。

我用的是 rclone 同步到对象存储：

```bash
rclone sync /backup/mysql remote:mybackup/mysql --max-age 24h
```

`--max-age 24h` 只同步一天内的新文件，不用每次全传。

对象存储那边开了版本控制，就算本地文件被勒索软件加密了，云上的历史版本还在。

还有一个细节，云上的凭据要单独放，不要和备份放在同一台机器上。不然机器被攻破，凭据一起泄露，备份也保不住。

## 真正的考验是恢复

这一步我建议每个人都做一次。

找个测试环境，把备份文件恢复进去，看看数据对不对。

```bash
gunzip -c myapp-2025-03-19.sql.gz | mysql -u root -p testdb
```

然后：

```sql
SELECT COUNT(*) FROM comments;
SELECT MAX(created_at) FROM comments;
```

数字对得上，时间对得上，才算备份有效。

我第一次做这个演练的时候，发现恢复出来的库少了三张表。原因是那三张表是 MyISAM，`--single-transaction` 对它们无效，mysqldump 直接跳过了。后来改成全部 InnoDB 才好。

这种问题，只有真的恢复一次才能发现。

## 恢复的流程也要写下来

出事的时候人是慌的，容易漏步骤。

我把恢复流程写成了一个文档，放在 `/srv/docs/restore.md`，内容包括：

先停掉应用，防止有新的写入。

备份当前的数据库（哪怕是坏的，先留一份）。

创建新的库，导入备份。

检查表数量、行数、最新的记录时间。

确认无误之后，改应用的连接配置，启动。

最后记录这次事故的时间线和原因。

有这个文档，真出事的时候照着做就行，不用临场想。

## 现在的情况

这套东西跑了快一年，中间用上了两次。一次是我自己误删，一次是磁盘满了导致写入失败。

两次都在半小时内恢复，业务中断时间不到一小时。

备份这件事，平时感觉不到它的价值。它唯一的价值就在出事的那一刻，而那一刻你没有任何补救的机会，只能靠之前准备好的东西。

所以我现在对它的态度是，不追求多先进，但一定要简单、可靠、验证过。
