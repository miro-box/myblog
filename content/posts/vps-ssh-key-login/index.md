---
# ==================== 必填（3 项）====================
title: "每天几千次爆破登录，我把 SSH 彻底加固了一遍"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-08-18T00:33:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从禁用 root、改端口到密钥登录和 fail2ban，一步步把 VPS 的 SSH 入口收紧，附带一份改坏了怎么救的预案。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Linux"
    - "SSH"
    - "安全"
    - "fail2ban"

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

新买的 VPS，装完系统第一次登录，我习惯先看一眼日志。

```bash
journalctl -u ssh --since "1 hour ago" | grep -c "Failed password"
```

三百多次。这才开机一个小时。

再看来源，全世界各地，用户名从 `root` 到 `admin` 到 `oracle` 到 `test`，全都是自动化脚本在扫。

这些尝试基本不可能成功，因为我的密码是随机生成的。但看着这些日志还是不舒服，而且它们会占带宽、占 CPU、把日志撑大。

所以每台新机器，我都会花半小时把 SSH 加固一遍。

## 先建一个普通用户

root 直接登录是最危险的。一旦密码泄露，攻击者拿到的是最高权限。

建一个普通用户：

```bash
adduser mingyue
usermod -aG sudo mingyue
```

Debian 和 Ubuntu 上 `sudo` 组有 sudo 权限。CentOS 上是 `wheel` 组。

然后测试这个用户能不能登录、能不能 sudo。这一步很重要，因为后面要禁用 root，万一普通用户有问题，就进不去了。

## 密钥登录

密码再复杂，也不如密钥。

原理是非对称加密。你本地有一对密钥，私钥自己留着，公钥放到服务器上。登录的时候，服务器用公钥验证你手里的私钥，验证通过就放行。整个过程私钥不会离开你的机器。

生成密钥：

```bash
ssh-keygen -t ed25519 -C "mingyue@laptop"
```

`-t ed25519` 是算法。ed25519 比 rsa 更短、更快、更安全。现在的 OpenSSH 都支持。

如果你的客户端特别老，不支持 ed25519，那就用 `-t rsa -b 4096`。

`-C` 是注释，一般写邮箱或者用途，方便识别。这个不影响功能。

生成过程中会问你要不要设密码。这个密码是保护私钥文件的，不是登录密码。

设了之后，每次用这个私钥都要输一遍。可以用 `ssh-agent` 缓存，输一次管一段时间。

我的建议是设一个。私钥文件如果泄露了，有这个密码还能挡一层。

## 把公钥放到服务器

最方便的是 `ssh-copy-id`：

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub mingyue@服务器IP
```

它会让你输一次密码，然后把公钥追加到服务器的 `~/.ssh/authorized_keys` 里。

如果没有这个命令（Windows 的某些环境），可以手动：

```bash
cat ~/.ssh/id_ed25519.pub
```

复制输出的内容，然后登录服务器：

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "粘贴的公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

权限必须对。`.ssh` 是 700，`authorized_keys` 是 600。权限不对，SSH 会拒绝使用这个文件，而且报错信息很含糊，只说什么 "bad permissions"。

这个坑我踩过，当时找了好久。

## 测试

新开一个终端，不要关掉当前这个。

```bash
ssh -i ~/.ssh/id_ed25519 mingyue@服务器IP
```

如果不需要输密码就进去了，说明密钥配好了。

如果还要输密码，说明公钥没生效。检查 `authorized_keys` 的内容和权限，还有 `/etc/ssh/sshd_config` 里的 `PubkeyAuthentication` 是不是 `yes`。

## 禁用密码登录

确认密钥能用之后，再改配置。

```bash
sudo nano /etc/ssh/sshd_config
```

找到这几行，改成：

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

注意 `KbdInteractiveAuthentication` 是新版的写法。老版本叫 `ChallengeResponseAuthentication`，Debian 12 用的是新的。

只改 `PasswordAuthentication` 不够，因为有些 PAM 配置会让键盘交互式认证绕过这个开关。两个都关掉才彻底。

改完先检查语法：

```bash
sudo sshd -t
```

没有输出就是没问题。

然后重启：

```bash
sudo systemctl restart ssh
```

Debian 12 的服务名是 `ssh`，不是 `sshd`。CentOS 上是 `sshd`。

**重启之前一定要保持当前会话开着。** 万一配置错了，你还能从这个会话里改回来。

## 禁用 root 登录

```text
PermitRootLogin no
```

这个也要小心。如果你还没确认普通用户能 sudo，禁用 root 之后可能就进不去了。

保险的做法是先确认：

```bash
ssh mingyue@服务器IP
sudo whoami
```

能输出 `root` 就说明 sudo 是好的。

然后再改 `PermitRootLogin`。

## 改端口

22 端口是扫描器的重点目标。改成一个高位端口，能过滤掉绝大部分自动化扫描。

```text
Port 2222
```

选端口的时候，避开常用的服务端口。2222 是常用的 SSH 替代端口，扫描器也会扫，但频率比 22 低得多。用一些不常见的端口效果更好，比如 50222。

改完还要改防火墙：

```bash
sudo ufw allow 2222/tcp
sudo ufw delete allow 22/tcp
sudo ufw reload
```

如果你用的是云服务器，安全组也要改。

## 本地配置别名

每次都敲端口和用户名太麻烦。本地 `~/.ssh/config`：

```text
Host blog
    HostName blog.mibase.top
    User mingyue
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

之后 `ssh blog` 就行。

`ServerAliveInterval 60` 是每六十秒发一个心跳包，防止连接因为空闲被断开。`ServerAliveCountMax 3` 是连续三次没响应就断开。

这两个参数在网络不稳定的环境下很有用，能避免那种"看着连着但已经死了"的情况。

## fail2ban

改端口和密钥登录已经能挡掉大部分了，但总有些执着的扫描器会继续尝试。fail2ban 能让它们付出代价。

```bash
sudo apt install fail2ban
```

配置不要改 `jail.conf`，改 `jail.local`：

```bash
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

在文件末尾加：

```ini
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
backend  = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port    = 2222
logpath = %(sshd_log)s
```

`backend = systemd` 是因为 Debian 12 默认没有 `/var/log/auth.log`，日志都在 journald 里。用 `systemd` 后端让 fail2ban 通过 `journalctl` 读。

`maxretry = 3` 是三次失败就封。`bantime = 1h` 是封一小时。

启动：

```bash
sudo systemctl enable --now fail2ban
```

看状态：

```bash
sudo fail2ban-client status sshd
```

输出里能看到当前封了多少个 IP，以及被封的列表。

## 更进一步

上面这些做完，安全性已经不错了。如果还想再收紧，有几件事可以做。

**限制登录用户**：

```text
AllowUsers mingyue
```

只有这个用户能登录，别的都被拒绝。

**限制登录来源 IP**：

```text
Match Address 1.2.3.4/32
    PermitRootLogin yes
```

这个可以给特定 IP 开特例。我一般不用，因为我的 IP 是动态的。

**关掉 X11 转发**：

```text
X11Forwarding no
```

除非你真的需要图形界面转发，否则关掉能减少攻击面。

**限制认证尝试次数**：

```text
MaxAuthTries 3
LoginGraceTime 30
```

`LoginGraceTime` 是登录的超时时间，默认是 120 秒。改成 30 秒，减少连接占用的时间。

**只监听特定地址**：

如果你的机器有多个 IP，可以只在一个上面监听：

```text
ListenAddress 1.2.3.4
```

## 改坏了怎么救

这一步最重要。

如果配置改错，SSH 连不上，你还有几条路。

**保留的会话**。这是最简单的。改之前开着的那个会话，只要没关，就还能用。从这个会话里把配置改回去。

**VNC 控制台**。云服务器都提供这个功能，在网页上直接连到机器的显示器。用它登录进去修复。

**救援模式**。大多数云厂商有"救援模式"，会把机器重启到一个临时的系统，你可以挂载原来的磁盘修复配置。

**重新装系统**。最坏的情况，如果数据有备份，重装也很快。

我的习惯是，改 SSH 之前一定做三件事。备份配置文件，开一个新会话测试，确认云控制台能进。

这三件事花不了几分钟，但能在出事的时候救命。

## 现在的状态

我这台机器改完之后，每天的失败登录从几千次降到几乎为零。

fail2ban 的日志里，每天封几十个 IP，都是那种扫到 2222 端口然后试几个密码的。

有一次我看了一眼封禁列表，来自俄罗斯、巴西、印度、越南，全世界都有。这就是公网的真实环境。

安全这件事，没有一劳永逸。但把这些基础做好，就已经比绝大多数服务器安全了。大部分攻击都是广撒网，只要你的门槛比别人高一点，它们就换目标了。
