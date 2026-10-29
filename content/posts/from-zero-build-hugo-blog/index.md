---
# ==================== 必填（3 项）====================
title: "折腾了三种博客程序之后，我最后还是回到了 Hugo"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-11-12T16:06:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从 WordPress 到 Hexo 再到 Hugo，把 blog.mibase.top 这套东西从零搭起来的过程，包括主题选择、目录结构和第一次部署。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "博客搭建"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Hugo"
    - "Stack"
    - "静态博客"

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

我的博客换过三次。

最早是 WordPress，插件装了一堆，功能确实全，但每次后台点一下都要等两三秒。那台 1 核 1G 的 VPS 跑 PHP 加 MySQL，内存常年飘在 90% 以上，隔三差五就被 OOM killer 干掉一次。

后来换 Hexo。静态生成，快是快，但 `node_modules` 那个目录，每次重装都像是在抽奖。有一次 `npm install` 装了两百多个包，其中一个包依赖的包又依赖别的包，最后卡在一个早就没人维护的模块上，编译失败。

再后来听人提 Hugo。我一开始觉得它就是个静态生成器，和 Hexo 差不多，没什么非换不可的理由。直到我看见有人用它构建几千篇文章只要几秒钟。

现在这个站跑在 Hugo 上，用了快一年，中间没有一次因为构建本身出问题。

## 装

Windows 上最省事的是用 scoop：

```bash
scoop install hugo-extended
```

一定要装 extended 版本。普通版本不支持 SCSS 和 Sass，而 Stack 主题的样式是用 SCSS 写的，装错版本会构建失败，报错信息还特别含糊。

Linux 上直接下二进制：

```bash
wget https://github.com/gohugoio/hugo/releases/latest/download/hugo_extended_linux-amd64.tar.gz
tar -xzf hugo_extended_linux-amd64.tar.gz
sudo mv hugo /usr/local/bin/
```

装完验证：

```bash
hugo version
```

输出里带 `extended` 字样就对了。

## 建站

```bash
hugo new site blog
cd blog
```

生成的目录结构是这样：

```text
blog/
├── archetypes
├── assets
├── content
├── data
├── i18n
├── layouts
├── static
├── themes
└── hugo.toml
```

`content` 是文章，`static` 是原样拷贝的文件，`themes` 是主题。`assets` 这个目录值得说一下，放进去的东西会经过 Hugo 的管道处理，比如 SCSS 编译、图片压缩、JS 打包。

## 选主题

我试过好几个，最后停在 Stack 上。

它的视觉风格比较克制，左侧固定侧边栏，文章列表卡片式，暗色模式做得挺舒服。功能上该有的都有，标签、分类、归档、搜索、代码高亮、目录，不用自己补。

装主题有两种方式，submodule 和直接下载。submodule 干净一些：

```bash
git init
git submodule add https://github.com/CaiJimmy/hugo-theme-stack.git themes/hugo-theme-stack
```

用 submodule 之后，更新主题就是 `git submodule update --remote`，不会污染自己的仓库。

## 配置

`hugo.toml` 里最基本的东西：

```toml
baseURL = "https://blog.mibase.top/"
languageCode = "zh-cn"
title = "明月小站"
theme = "hugo-theme-stack"

[pagination]
  pagerSize = 10

[permalinks]
  posts = "/p/:slug/"

[markup]
  [markup.highlight]
    noClasses = false
    codeFences = true
    lineNos = false
```

`[permalinks]` 那段决定了文章的 URL 结构。我设成 `/p/:slug/`，是因为之前见过别人的站用日期做路径，文章一多，URL 长得没法记。用 slug 更短，也更容易分享。

注意 Hugo 从 0.128 开始把 `paginate` 改成了 `pagination.pagerSize`。老教程里写的 `paginate = 10` 现在会报警告。

Stack 主题还需要一份自己的配置，放在 `config/_default/` 下面。主题仓库里的 `exampleSite` 目录有一份完整的示例，复制过来改最省事。

```bash
cp -r themes/hugo-theme-stack/exampleSite/config/_default/* config/_default/
```

然后改 `config/_default/hugo.toml` 里的 `baseURL`、`title`，改 `params.toml` 里的头像、社交链接、侧边栏设置。

## 写下第一篇

```bash
hugo new content posts/hello-world/index.md
```

注意这里写的是 `posts/hello-world/index.md`，不是 `posts/hello-world.md`。

这是 Hugo 的 Page Bundle 机制。用目录加 `index.md` 的形式，可以把图片和文章放在一起，引用的时候直接写相对路径：

```markdown
![截图](screenshot.png)
```

不用管最终部署到哪个路径，Hugo 会自己处理。这个设计比把图片全塞进 `static` 里要好，因为文章和它的资源绑在一起，删文章的时候资源也跟着删，不会留下垃圾。

生成的 front matter 长这样：

```yaml
---
title: "Hello World"
date: 2024-11-12T16:06:00+08:00
draft: true
---
```

`draft: true` 表示草稿，本地 `hugo server` 能看到，但构建的时候会被排除。写完改成 `false` 才会发布。

这个机制挺有用的。有时候写一半的东西不想让人看到，就留着 `true`，等写完再改。

## 本地预览

```bash
hugo server -D
```

`-D` 是显示草稿。默认只监听 `localhost:1313`，如果要让局域网里的手机也能看：

```bash
hugo server -D --bind 0.0.0.0 --baseURL http://192.168.1.10:1313
```

`--baseURL` 这个参数不加的话，手机打开页面样式是乱的，因为 css 的路径还指向 localhost。

Hugo 的 server 有热重载，改文章、改模板都会立刻刷新浏览器。改配置文件有时候需要重启，因为它不监听配置文件的变化。

## 构建

```bash
hugo --minify --gc
```

产物在 `public` 目录。

`--minify` 会压缩 html、css、js 和 json，一般能小 20% 左右。`--gc` 清理掉不再被引用的缓存文件，防止 `resources` 目录无限膨胀。

有个参数我一开始不知道，`--printPathWarnings`，它会告诉你哪些页面有重复路径。文章多了之后很有用，能提前发现 slug 冲突。

## 部署

我把 `public` 目录通过 git 钩子同步到服务器，那套流程写在另一篇里了。简单说就是本地 push，服务器上的钩子执行 `hugo` 构建，nginx 指向产物目录。

这个方案的好处是不需要额外的 CI 服务，坏处是构建在服务器上跑，服务器得装 Hugo。我服务器上装的是 extended 版本，和本地保持一致。

## 目录约定

用了一段时间，我把目录固定成了这样：

```text
content/
├── page/
│   ├── about/index.md
│   └── links/index.md
└── posts/
    ├── hello-world/index.md
    └── another-post/index.md
```

`posts` 下面全是文章，一篇一个目录。`page` 下面放独立页面，比如关于、友链。Stack 主题默认就是这么分的。

分类和标签不用建目录，写在 front matter 里就行，Hugo 会自动生成列表页。

## 一个容易踩的坑

Hugo 的 `date` 字段如果没有时区，会按 UTC 解释。

我第一篇文章写的是 `date: 2024-11-12 16:06:00`，构建出来发现时间比实际早了八小时。后来改成带时区的格式 `2024-11-12T16:06:00+08:00` 才对。

这个在本地看不出来，因为 `hugo server` 用的是本地时区。部署到服务器上，服务器是 UTC，就露馅了。

## 现在回头看

三次换博客程序，每次的动机都不一样。

WordPress 是图省事，Hexo 是图轻快，Hugo 是图稳定。

现在这套东西，构建三秒，部署十秒，改一行配置立刻能看到效果。中间没有数据库，没有后台，没有需要重启的服务。它就是一堆文件。

这种简单带来的安心感，是前面两个方案没给过我的。

## 一些我后来才明白的细节

`hugo.toml` 里的 `baseURL` 结尾一定要带斜杠。写成 `https://blog.mibase.top` 而不是 `https://blog.mibase.top/`，生成的 rss 和 sitemap 里的链接会缺一个斜杠，有些抓取工具会因此报错。

`content` 目录下以 `_index.md` 开头的文件是列表页，不是文章。`posts/_index.md` 定义了文章列表页的标题和排序方式。如果你不小心把文章命名成 `_index.md`，它不会出现在文章列表里，反而会变成那个目录的列表页。

草稿的 `draft: true` 只影响构建，不影响 `hugo server`。只要加了 `-D`，草稿一样能看到。有时候我写完忘了改，本地看着好好的，部署上去发现没有这篇，才想起来。

`resources/_gen` 这个目录是 Hugo 的缓存，可以删，删了会重新生成。但它不要提交到 git 里，会污染 diff。`.gitignore` 里加上这一行：

```text
resources/_gen/
public/
```

`public` 也不该提交。它是构建产物，每次部署都会重新生成，提交进去只会让仓库变大。

## 如果重新来一次

我会在第一天就把这些东西配好，而不是用了半年才补。

`hugo.toml` 里的 `enableRobotsTXT`，加上之后会自动生成 robots.txt。

`[markup.goldmark.renderer]` 里的 `unsafe = true`，加上之后才能在文章里直接写 html。默认是关闭的，是为了安全，但自己的博客自己写内容，没什么风险。

`[outputs]` 里给首页加上 `JSON`，这样才有搜索用的 `index.json`。Stack 的搜索依赖这个。

这些都是一次性的配置，配好之后就不用管了。但不知道的时候，会卡很久。
