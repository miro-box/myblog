---
# ==================== 必填（3 项）====================
title: "断网之后命令跑到一半没了，我开始认真用 tmux"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-07-12T21:29:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从一次编译到一半断线说起，把 tmux 的会话、窗口、面板讲清楚，再配上 zsh 和一堆顺手的配置。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "折腾日常"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "tmux"
    - "zsh"
    - "Linux"
    - "效率工具"

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

有一次我在服务器上编译一个东西，跑了快四十分钟。中间我去泡了杯茶，回来发现 SSH 断了。

笔记本进了休眠，网络断了。重新连上去，编译进程没了，得从头再来。

那次之后我才开始认真用 tmux。之前也装过，但一直停留在"知道有这么个东西"的阶段，没真正用起来。

## 它解决什么问题

简单说，tmux 让你的终端会话脱离 SSH 连接存在。

平时你 SSH 上去，开一个 shell，这个 shell 是挂在那条 SSH 连接上的。连接断了，shell 就收到 SIGHUP，进程跟着退出。

tmux 的做法是，先起一个服务端进程（daemon），你的 shell 跑在这个 daemon 下面。SSH 连接只是"附着"到这个 daemon 上。连接断了，daemon 还在，里面的进程继续跑。下次连上去，重新 attach 就能看到之前的样子。

这个概念叫"会话持久化"。它解决的不只是断线问题，还有多任务并行、窗口切换、远程协作。

## 装

```bash
sudo apt install tmux
```

版本检查：

```bash
tmux -V
```

3.x 之后的版本支持的东西比较全。Debian 12 自带的是 3.3a，够用。

## 三个概念

tmux 的结构分三层。

会话（session）是最外层的，一个会话可以理解成一个工作空间。比如一个会话做前端，一个会话做后端。

窗口（window）在会话里面，相当于浏览器的标签页。一个窗口占满整个终端。

面板（pane）在窗口里面，把终端切成几块。可以横向切，也可以纵向切。

日常用的时候，我一般是按项目分会话，每个会话里按任务分窗口，需要同时看两个东西的时候才切面板。

## 最常用的命令

从外部操作会话：

```bash
tmux new -s work        # 新建一个叫 work 的会话
tmux ls                 # 列出所有会话
tmux attach -t work     # 附着到 work
tmux kill-session -t work  # 杀掉 work
```

`attach` 可以简写成 `a`：

```bash
tmux a -t work
```

如果只有一个会话，`tmux a` 就够了。

从里面脱离：

```text
Ctrl+b 然后按 d
```

`Ctrl+b` 是默认的前缀键，所有的 tmux 快捷键都要先按它。

## 快捷键

前缀键按完之后，再按一个键。常用的：

`c` 新建窗口，`n` 下一个窗口，`p` 上一个窗口，`0-9` 跳到指定编号的窗口，`,` 重命名窗口。

`%` 左右切分，`"` 上下切分。这两个符号有点反直觉，`%` 是竖着切（左右分），`"` 是横着切（上下分）。

方向键在面板之间切换。`z` 把当前面板最大化，再按一次还原。这个在需要看长输出的时候很有用。

`[` 进入复制模式，可以用方向键或者 vi 的键位翻页。按 `q` 退出。

`d` 脱离，`$` 重命名会话，`s` 列出所有会话并切换。

`?` 显示所有快捷键。这个最有用，记不住的时候按一下。

## 配置文件

默认的配置太素了，而且有些键位不顺手。

`~/.tmux.conf`：

```tmux
# 改前缀键为 Ctrl+a，和 screen 一致，手更习惯
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# 从 1 开始编号，和键盘上的位置对应
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# 更快的转义时间，vim 里按 esc 不用等
set -sg escape-time 10

# 支持 256 色和真彩色
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"

# 鼠标支持
set -g mouse on

# 历史行数
set -g history-limit 50000

# 窗口和面板的分割线用细线
set -g pane-border-style fg=colour238
set -g pane-active-border-style fg=colour39

# 状态栏
set -g status-style bg=colour235,fg=colour250
set -g status-left "#[fg=colour39,bold] #S "
set -g status-right "#[fg=colour250]%Y-%m-%d %H:%M "
set -g status-interval 30

# 用 vim 的键位在复制模式里移动
setw -g mode-keys vi

# 分屏的时候保持当前目录
bind '"' split-window -v -c "#{pane_current_path}"
bind '%' split-window -h -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"

# 用 v 和 y 做复制粘贴，贴近 vim
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-selection-and-cancel
```

几个值得解释的。

`base-index 1` 是让窗口从 1 开始编号。默认从 0 开始，但键盘上 1 在最左边，按起来更顺。

`renumber-windows on` 是关掉一个窗口之后，后面的自动重新编号。不加的话会出现 1、3、4 这样的空档。

`escape-time 10` 默认是 500 毫秒。在 tmux 里用 vim 的时候，按 esc 要等半秒才响应，很难受。改成 10 毫秒就好了。

`mouse on` 这个有人喜欢有人不喜欢。开着之后可以用鼠标点面板、拖滚动条、调整分割线。我觉得挺方便的，尤其是刚上手的时候。

`pane_current_path` 那几行是让新窗口和新面板继承当前目录。默认是新窗口从 home 目录开始，每次都要 cd 过去，很烦。

## 插件管理

tmux 的插件生态也不错，用 TPM（Tmux Plugin Manager）管理：

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

在 `.tmux.conf` 末尾加：

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

run '~/.tmux/plugins/tpm/tpm'
```

然后按 `Ctrl+a` 再按 `I`（大写 i），它会自动安装。

`tmux-sensible` 是一堆合理默认值的集合，省得自己一条条配。

`tmux-resurrect` 能保存和恢复会话。机器重启之后，按 `Ctrl+a` 再按 `Ctrl+r`，之前的窗口和面板布局全都回来了。

`tmux-continuum` 是让 resurrect 自动保存，每十五分钟一次。还能设置成开机自动恢复。

这两个配合起来，体验很好。有一次我的服务器意外重启，恢复之后 tmux 自动把之前的会话全拉起来了，连每个面板的当前目录都在。

不过要注意，resurrect 默认不保存正在运行的程序的输出，只保存布局和目录。想让它保存 vim 的会话或者别的程序状态，得额外配置。

## zsh

说完 tmux，说 zsh。

bash 用了很多年，够用。但 zsh 的补全和主题确实更好看，也更顺手。

```bash
sudo apt install zsh
chsh -s $(which zsh)
```

重新登录之后就是 zsh 了。

第一次启动会有一个配置向导，选 `2` 创建一个基础的 `.zshrc`。

然后装 oh-my-zsh：

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

oh-my-zsh 是个框架，提供主题和插件管理。有人觉得它太重，启动慢。确实有这个问题，在慢速文件系统上能感觉到。

如果在意启动速度，可以用 zinit 或者手动管理插件。我用了几年 oh-my-zsh，觉得还行，启动大概两百毫秒，能接受。

## 主题

我用的主题是 `powerlevel10k`，比 oh-my-zsh 自带的快很多，而且配置灵活。

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```

`.zshrc` 里改：

```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
```

第一次启动会进入一个配置向导，问你要什么风格的提示符、要不要图标、要不要显示时间。按自己的喜好选就行。

有个前提，终端字体要支持 Nerd Fonts，不然那些图标会显示成方块。我用的是 `JetBrainsMono Nerd Font`，在终端设置里选上。

## 插件

`.zshrc` 里加：

```bash
plugins=(
  git
  z
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
)
```

`git` 提供一堆 git 别名，比如 `gst` 是 `git status`，`gco` 是 `git checkout`。

`z` 是目录跳转。它会记录你去过的目录，之后 `z blog` 就能跳到 `/srv/www/blog`，不用敲完整路径。这个用熟了回不去。

`zsh-autosuggestions` 会根据历史命令给出灰色提示，按右方向键接受。敲长命令的时候特别省事。

`zsh-syntax-highlighting` 让命令有颜色，正确的命令是绿色，错误的是红色。敲错的时候能立刻发现。

后两个要单独装：

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

注意 `zsh-syntax-highlighting` 必须放在 plugins 数组的最后，因为它会包装所有命令，放前面会干扰别的插件。

## 别名

我在 `.zshrc` 末尾加了一堆别名：

```bash
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'

alias gs='git status'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'

alias ngt='nginx -t && systemctl reload nginx'
alias jc='journalctl -u'
alias ports='ss -tulpn'
```

这些别名省下的时间不多，但每次省几秒，一天下来也不少。

## 两个配合起来

tmux 和 zsh 配合，体验最好的是这个场景。

我在本地开一个 tmux 会话，里面分三个面板。左边是编辑器，右上跑测试，右下看日志。

然后 `Ctrl+a d` 脱离，去干别的事。

回来 `tmux a`，三个面板原样还在，测试还在跑，日志还在滚。

这个工作流一旦形成习惯，就再也回不去了。

## 一个小技巧

`tmux new -s work -d` 是后台新建会话，不附着。

配合 ssh 可以做一件有意思的事。在本地 `.ssh/config` 里：

```text
Host blog
    HostName blog.mibase.top
    User deploy
    Port 2222
    RequestTTY yes
    RemoteCommand tmux new -A -s main
```

`tmux new -A -s main` 的意思是，如果 main 会话存在就附着，不存在就新建。

这样每次 `ssh blog` 都会直接进到同一个 tmux 会话，不用手动 attach。断线重连也是回到原来的地方。

这个配置我用了一年多，非常舒服。

## 现在

tmux 已经是我每天都要用的东西，和编辑器一样重要。

回头看，真正让我开始用它的是一个很小的事，编译到一半断线。但用下来之后发现，它改变的是整个工作方式。你不再需要担心连接状态，不再需要开一堆终端窗口，所有东西都在一个会话里，随时可以离开，随时可以回来。

zsh 那边，提升的是日常操作的顺手程度。补全、提示、别名，每一样都不起眼，加起来就是每天少敲几百次键盘。

工具的价值就在这儿。它不解决什么大问题，只是让你每天重复的事情变得轻松一点。
