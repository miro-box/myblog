---
# ==================== 必填（3 项）====================
title: "再也不用 scp 传文件了，push 一下博客就上线"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-12-12T04:58:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "用服务器上的裸仓库加 post-receive 钩子，把本地 push 直接变成线上部署，顺便解决了权限和工作区的问题。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "架构部署"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Git"
    - "自动化部署"
    - "运维"
    - "Hugo"

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

以前写博客的流程是这样的。

本地写完，`hugo` 构建，然后用 FileZilla 把 `public` 目录拖到服务器上。拖的时候还不能直接覆盖，得先删掉旧的，再传新的，不然会残留一堆已经删掉的文章。

有几次传了一半网断了，网站变成了半新半旧的状态，首页能打开，点进去文章 404。还有一次拖错了目录，把 `public` 传到了上一级，整站挂了半小时。

后来我改用 rsync，好一些，但还是要手动敲命令。再后来加了 `--delete`，又差点把服务器上别的目录删了。

这种手动流程，出问题是迟早的。

## 换个思路

其实我要的事情很简单。本地 `git push` 之后，服务器上自动更新网站。

Git 本身就能做这件事。服务器上建一个裸仓库，配置一个 `post-receive` 钩子，每次收到 push 就执行一段脚本。脚本里做的事情就是把代码检出到工作目录，然后构建。

这个方案的好处是不依赖任何外部服务。不用 GitHub Actions，不用 Jenkins，不用装一堆东西。一台有 git 的机器就能跑。

## 服务器上建裸仓库

登录服务器：

```bash
ssh blog
```

建目录：

```bash
sudo mkdir -p /srv/git/blog.git
sudo chown -R git:git /srv/git
```

这里我专门建了个 `git` 用户，不用 root，也不用我自己的账号。原因后面说。

初始化裸仓库：

```bash
sudo -u git git init --bare /srv/git/blog.git
```

`--bare` 的意思是只有 git 数据，没有工作区。你不能在这个目录里直接看到文件，它是纯粹用来接收 push 的。

## 建一个工作目录

网站的实际文件要放在另一个地方，比如 `/srv/www/blog`：

```bash
sudo mkdir -p /srv/www/blog
sudo chown -R git:git /srv/www/blog
```

注意属主是 `git`，因为钩子是以 `git` 用户的身份跑的。如果属主是 root，钩子里的写操作会失败。

## 写钩子

钩子的位置是固定的：

```bash
sudo -u git nano /srv/git/blog.git/hooks/post-receive
```

内容：

```bash
#!/bin/bash
set -euo pipefail

WORK=/srv/www/blog
GIT_DIR=/srv/git/blog.git

while read oldrev newrev refname; do
  if [ "$refname" = "refs/heads/main" ]; then
    echo "==> 部署 main 分支到 $WORK"
    git --work-tree="$WORK" --git-dir="$GIT_DIR" checkout -f main
    cd "$WORK"
    hugo --minify --gc
    echo "==> 部署完成"
  fi
done
```

给执行权限：

```bash
sudo chmod +x /srv/git/blog.git/hooks/post-receive
```

`while read oldrev newrev refname` 这一段是标准写法。push 的时候 git 会把每个被更新的引用通过标准输入传给你，格式是三列。只处理 `main` 分支，别的分支推上来不触发部署。

`checkout -f` 里的 `-f` 很重要。它会强制覆盖工作区里的文件，不管有没有本地修改。不加这个，第二次部署就会因为文件冲突失败。

`hugo --minify --gc` 是构建。`--minify` 压缩 html、css、js，`--gc` 清理掉不再引用的缓存资源。这两个参数在 Hugo 0.115 之后都还在用。

## 本地配置远程

```bash
git remote add deploy ssh://git@blog.mibase.top/srv/git/blog.git
```

或者用 scp 风格的写法：

```bash
git remote add deploy git@blog.mibase.top:/srv/git/blog.git
```

两种都行，前者更明确一点。

然后：

```bash
git push deploy main
```

第一次推的时候，终端里应该能看到钩子输出的那几行。

## 权限这块是最大的坑

我一开始用的是自己的账号，没建 `git` 用户。结果钩子跑起来各种 Permission denied。

原因是 SSH 登录的用户和钩子执行脚本的用户必须是同一个，而且这个用户要对工作目录有写权限，对 nginx 的目录也要有读权限。

后来我理清了：

`git` 用户拥有裸仓库和工作目录。nginx 以 `www-data` 身份跑，需要有读权限。所以我把工作目录的组设成 `www-data`，权限给到 750：

```bash
sudo chown -R git:www-data /srv/www/blog
sudo chmod -R 750 /srv/www/blog
sudo usermod -aG www-data git
```

这样 `git` 用户能写，`www-data` 能读，别人进不来。

还有一个 SELinux 的问题。如果你用的是 CentOS 或者 RHEL，默认的 SELinux 策略会阻止 nginx 读 `/srv` 下面的文件。得打标签：

```bash
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/www/blog(/.*)?"
sudo restorecon -Rv /srv/www/blog
```

Debian 和 Ubuntu 没这个烦恼。

## 只给 git 用户最小权限

用 `git` 用户有个额外的好处，就是可以限制它能做的事。

编辑 `/etc/passwd`，把这个用户的 shell 从 `/bin/bash` 改成 `/usr/bin/git-shell`：

```text
git:x:998:998::/srv/git:/usr/bin/git-shell
```

`git-shell` 是一个受限的 shell，只允许 git 相关的命令，别的命令一律拒绝。这样就算有人拿到了这个账号的私钥，也登不进交互式的 shell，只能在 git 协议里操作。

这个设置很值得做。我之前的机器被人扫过 SSH 密码，虽然没成功，但那之后我就把能限制的地方都限制了。

## nginx 那边

配置里 root 指到工作目录的 public：

```nginx
server {
    listen 443 ssl http2;
    server_name blog.mibase.top;

    root /srv/www/blog/public;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Hugo 构建完之后，静态文件在 `public` 子目录里，所以 root 要指到那一层。

## 增量构建的问题

如果博客文章多了，每次全量构建会比较慢。Hugo 支持增量：

```bash
hugo --minify --gc --buildDrafts=false
```

不过增量构建有它自己的问题，改了模板或者配置之后，有时候不会重新生成所有页面，导致部分页面还是旧的。我的经验是，日常发文用增量，改主题或者配置的时候手动跑一次全量。

Hugo 0.123 之后引入了一个 `--renderToMemory` 的选项，构建更快，但对大站内存要求高。我这种几十篇文章的站感觉不出差别。

## 多个站点的做法

后来我又加了一个笔记站，用的是同一套方案。

裸仓库和钩子都是独立的，互不干扰。唯一要改的是钩子里的路径和构建命令。

我把钩子的公共部分抽成了一个脚本，放在 `/srv/git/deploy.sh`，两个钩子都去调它，传不同的参数：

```bash
#!/bin/bash
set -euo pipefail
WORK=$1
BRANCH=${2:-main}

while read oldrev newrev refname; do
  if [ "$refname" = "refs/heads/$BRANCH" ]; then
    git --work-tree="$WORK" --git-dir="$GIT_DIR" checkout -f "$BRANCH"
    cd "$WORK"
    hugo --minify --gc
  fi
done
```

`GIT_DIR` 是 git 在执行钩子时自动设的环境变量，不用自己传。

## 出问题怎么回滚

这个方案有个小遗憾，它没有版本回退的功能。工作目录里永远是 main 分支的最新内容。

要回滚的话，有两个办法。

一个是在本地 revert 一个 commit，再 push 一次。这个最干净，历史是线性的。

另一个是直接在服务器上操作：

```bash
cd /srv/www/blog
git log --oneline -5
git checkout <COMMIT_ID> -- .
hugo --minify --gc
```

但这样工作目录会和裸仓库脱节，下次 push 的时候 `checkout -f` 会把你的手动修改全冲掉。所以我一般用第一种。

## 什么时候该换个方案

这套方案适合个人博客，不适合团队协作。

如果有多个人一起维护，你可能会想要在 push 之后跑测试、跑 lint、生成预览链接。这些用 GitHub Actions 或者 Gitea 的 CI 会方便很多。

还有一种是构建时间很长的站。我见过有人 Hugo 站有几千篇文章，全量构建要三分钟。这种情况下每次 push 都要等三分钟，体验不好，得考虑缓存或者增量。

我现在的站只有几十篇，构建三秒，用这套方案正合适。

## 现在的感受

最大的变化是心理上的。

以前想写点东西，会先想到"还得传文件"，这个念头本身就会让人拖延。现在打开编辑器就写，写完 push，完事。中间那一步消失了，写东西的阻力小了很多。

这种小工具的收益，往往不在技术本身，而在它把你从一件烦人的事情里解放出来。省下的那几分钟不重要，重要的是你不再因为烦而逃避。
