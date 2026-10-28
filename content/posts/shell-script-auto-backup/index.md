---
# ==================== 必填（3 项）====================
title: "写了十几版之后，我的备份脚本终于靠谱了"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-03-05T11:30:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从最简单的 tar 命令，到带锁、带校验、带告警、带异地同步的版本，中间踩过的坑都写在这儿了。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "脚本开发"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Shell"
    - "备份"
    - "Crontab"
    - "自动化"

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

我最早的那个备份脚本只有一行：

```bash
tar -czf /backup/site-$(date +%F).tar.gz /srv/www
```

放在 crontab 里，每天跑一次。跑了三个月，我从来没打开看过。

后来有一次我要恢复一个误删的文件，才发现那个目录里堆了九十多个压缩包，最大的一个只有 12 字节。

原因是 `/srv/www` 下面有个目录权限不对，`tar` 读不了，直接失败。但因为命令在 crontab 里，报错输出到邮件，而我没配邮件，所以什么都没看到。

九十天的备份，全是空的。

从那之后，我把这个脚本重写了十几遍，加了一堆东西。这篇记录一下最终的样子，以及每一处为什么要那么写。

## 最基础的要求

一个好的备份脚本，至少要满足这几条。

跑失败的时候要能知道。不能像我第一次那样，默默失败九十天。

备份文件本身要能验证。不能只看退出码，得实际检查文件大小和内容完整性。

不能并发跑。如果上一次还没跑完，下一次又启动，两个进程同时写同一个文件，结果就是坏的。

过期的东西要清理。不然磁盘会被占满，最后连带把系统搞挂。

异地要有一份。本机的备份防不了磁盘坏和机器丢。

## 脚本

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ---------- 配置 ----------
BACKUP_ROOT="/backup"
SOURCE_DIRS=("/srv/www" "/srv/git" "/etc/nginx")
KEEP_DAYS=14
LOG_FILE="/var/log/backup.log"
LOCK_FILE="/var/run/backup.lock"
REMOTE="remote:mybackup"
TG_TOKEN=""
TG_CHAT=""

# ---------- 工具函数 ----------
log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

fail() {
    log "ERROR: $*"
    notify "备份失败: $*"
    exit 1
}

notify() {
    [[ -z "$TG_TOKEN" ]] && return 0
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT}" \
        -d "text=$1" >/dev/null || true
}

cleanup() {
    local code=$?
    if [[ $code -ne 0 ]]; then
        log "脚本异常退出，退出码 $code"
    fi
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# ---------- 主流程 ----------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "上一次备份还在运行，本次跳过"
    exit 0
fi

DATE=$(date '+%F_%H%M')
ARCHIVE="${BACKUP_ROOT}/backup-${DATE}.tar.gz"

mkdir -p "$BACKUP_ROOT"

log "开始备份"

tar -czf "$ARCHIVE" \
    --exclude='*/cache/*' \
    --exclude='*/node_modules/*' \
    --exclude='*.log' \
    "${SOURCE_DIRS[@]}" 2>>"$LOG_FILE" || fail "tar 打包失败"

# 校验
[[ -s "$ARCHIVE" ]] || fail "备份文件为空"

SIZE=$(stat -c %s "$ARCHIVE")
if [[ $SIZE -lt 1048576 ]]; then
    fail "备份文件异常小: ${SIZE} 字节"
fi

# 完整性校验
gzip -t "$ARCHIVE" || fail "压缩包损坏"

log "备份完成，大小 $(numfmt --to=iec "$SIZE")"

# 清理过期
find "$BACKUP_ROOT" -name 'backup-*.tar.gz' -type f -mtime +"$KEEP_DAYS" -delete
log "已清理 ${KEEP_DAYS} 天前的备份"

# 异地同步
if command -v rclone >/dev/null 2>&1; then
    rclone sync "$BACKUP_ROOT" "$REMOTE" --max-age 24h 2>>"$LOG_FILE" \
        || log "WARN: 异地同步失败"
    log "异地同步完成"
fi

notify "备份完成: $(basename "$ARCHIVE")"
```

## 逐段解释

`set -Eeuo pipefail` 这四个选项，每一个都有用。

`-e` 让任何命令返回非零就退出。`-u` 让引用未定义变量时报错。`-o pipefail` 让管道里任何一个环节失败都能被捕获。`-E` 让 ERR trap 能被子 shell 继承。

`IFS=$'\n\t'` 是改字段分隔符。默认是空格、制表、换行。如果某个文件名里有空格，不加这个的话，`for f in $files` 会把一个文件名拆成两个。改成只认换行和制表，能避免大部分问题。

不过要注意，改 IFS 之后，`"$@"` 这种引用是安全的，但 `$*` 的行为会变。所以尽量用 `"$@"`。

## 锁

```bash
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0
```

`exec 9>` 是把文件描述符 9 指向这个锁文件。`flock -n` 尝试加锁，`-n` 是非阻塞，拿不到锁就立刻返回失败。

这个锁的作用是防止两个实例同时跑。如果没有它，cron 设的间隔比备份耗时短的时候，就会出现多个进程同时写同一个 tar 文件，结果一定是坏的。

为什么用文件描述符而不是 `flock -n /path/to/lock command` 这种写法？因为后者在命令结束之后会自动释放，但如果脚本中途被 kill -9，锁文件会留下，虽然不影响下次加锁（flock 的锁是内核管理的，进程死了自动释放），但用 fd 的方式更清晰，而且 trap 里能统一清理。

## 校验

```bash
[[ -s "$ARCHIVE" ]] || fail "备份文件为空"
```

`-s` 是文件存在且大小大于零。

```bash
gzip -t "$ARCHIVE"
```

这个会完整解压一遍检查 CRC，不输出内容。对于几百兆的文件，大概花几秒。值得。

```bash
[[ $SIZE -lt 1048576 ]]
```

这个阈值是拍脑袋定的。我的站点正常备份在几百兆，如果小于一兆，说明肯定有问题。

这个值要根据你的实际情况调。太小了起不到检查作用，太大了会误报。

## 清理

```bash
find "$BACKUP_ROOT" -name 'backup-*.tar.gz' -type f -mtime +14 -delete
```

`-mtime +14` 是修改时间超过十四天。注意 `+14` 是大于十四天，也就是第十五天开始删。

有个细节，`-mtime` 是按二十四小时算的，不是按自然日。所以如果备份是每天同一时间跑，这个判断是准的。

## 异地同步

```bash
rclone sync "$BACKUP_ROOT" "$REMOTE" --max-age 24h
```

`sync` 会让目标端和源端一致，包括删除。这一点要注意，如果本地文件被误删了，云上的也会被删。

想要更安全，用 `copy` 而不是 `sync`：

```bash
rclone copy "$BACKUP_ROOT" "$REMOTE" --max-age 24h
```

`copy` 只添加和更新，不删除。这样云上会越攒越多，需要另外配生命周期规则来清理。

我选了 `sync`，因为云上的生命周期规则更难调。但我加了对象存储的版本控制，就算被同步删除，历史版本还在。

`--max-age 24h` 只同步一天内的新文件，避免每次都全量比对。文件多了之后，这个参数能省很多时间。

## 告警

我用的是 Telegram Bot，因为它免费、稳定、API 简单。

```bash
notify "备份完成: $(basename "$ARCHIVE")"
```

成功也发一条。有人觉得成功不用通知，但我觉得正好相反。如果只有失败才通知，你就不知道"没收到通知"到底是成功了还是脚本根本没跑。

每天收到一条"备份完成"，心里踏实。

`|| true` 是让通知失败不影响主流程。告警本身挂了不应该导致备份失败。

## cron 的写法

```bash
sudo tee /etc/cron.d/backup <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

15 3 * * * root /usr/local/bin/backup.sh >> /var/log/backup-cron.log 2>&1
EOF
```

`cron.d` 的格式比 `crontab -e` 多一个用户字段，就是那个 `root`。少了这个字段，cron 不会执行，也不报错。

`SHELL` 和 `PATH` 这两行最好显式写。cron 的环境变量非常精简，很多命令找不到。

脚本里的 `>> /var/log/backup-cron.log` 是双保险。脚本自己会写 `LOG_FILE`，但万一脚本在写日志之前就挂了，cron 的 stderr 能兜住。

## 日志轮转

`/var/log/backup.log` 会一直涨，得配 logrotate。

```bash
sudo tee /etc/logrotate.d/backup <<'EOF'
/var/log/backup.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    copytruncate
}
EOF
```

`copytruncate` 是复制一份然后清空原文件，而不是改名。因为脚本一直在往这个文件写，改名之后文件描述符还指向旧的，会写到已经轮转的文件里。

## 几个我踩过的坑

有一次备份跑到一半，机器重启了，tar 文件是截断的。但脚本没有检查，第二天 cron 又跑了一次，生成了新的。旧的那个截断文件一直躺在目录里，直到过期被删。

后来我加了 `gzip -t` 检查，但那只检查新的那个。旧文件坏了还是不知道。

再后来我加了个每周一次的巡检，遍历所有备份文件，跑 `gzip -t`，有坏的就告警。

还有一次，`rclone` 同步的时候网络断了，同步失败，但脚本只记了 WARN 没退出。第二天我看云上的备份，少了三天。

现在我把异地同步的失败也升级成了告警，至少能知道。

## 定期演练

这一点最重要，也最容易被忽略。

我现在的习惯是每季度做一次恢复演练。随便挑一个备份文件，解压到临时目录，对比一下文件数量和关键文件的大小。

```bash
mkdir -p /tmp/restore-test
tar -xzf /backup/backup-2026-03-04_031500.tar.gz -C /tmp/restore-test
find /tmp/restore-test -type f | wc -l
diff -r /tmp/restore-test/srv/www /srv/www | head
```

如果 diff 没有输出，说明恢复出来的内容和现在的完全一致。

这一步花十分钟，但它能证明你的备份是真的有用的。

## 现在

这套脚本跑了快一年，中间成功恢复过两次。

一次是我误删了 nginx 的配置，一次是数据库写坏了一个表。

两次都在半小时内解决。那种"还好有备份"的感觉，是之前九十天空备份给不了我的。

备份这件事，最难的从来不是写脚本，是坚持验证。脚本写完就扔在那儿，跟没写差不多。
