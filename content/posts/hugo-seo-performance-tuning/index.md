---
# ==================== 必填（3 项）====================
title: "把 Hugo 博客的加载速度从三秒压到八百毫秒"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-12-29T20:18:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从 Lighthouse 的分数出发，一项项处理图片、字体、渲染阻塞和结构化数据，顺手把搜索引擎收录也理顺了。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "博客搭建"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Hugo"
    - "SEO"
    - "性能优化"
    - "Stack"

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

博客搭起来之后，我有一阵子特别在意 Lighthouse 那个分数。

第一次跑的时候，移动端性能 41 分，红色的。首屏内容绘制三点二秒，最大内容绘制四点一秒。这个成绩放在 2024 年，属实难看。

花了一个周末逐项处理，现在稳定在 96 分左右，首屏八百毫秒。这篇记录一下具体做了什么，哪些有用，哪些是白费劲。

## 先搞清楚慢在哪

别一上来就乱改。先跑一遍 Lighthouse，看它给的诊断项。

打开 Chrome 开发者工具，Lighthouse 标签页，选 Mobile，跑一次。跑完会给你一堆建议，按影响大小排序。

我那次排在最前面的是三件事。图片没有指定尺寸导致布局偏移，字体加载阻塞渲染，还有一个第三方脚本。

改之前先记一下基线，不然改完不知道有没有变好。

## 图片是最大的问题

我博客的文章配图是直接从手机相册里拖出来的，一张四兆。首页卡片显示的是缩略图，但它加载的其实是原图，浏览器自己缩。

这就很浪费。一个用户打开首页，要下十几兆的图片，手机上还容易因为内存不足崩掉。

Hugo 内置了图片处理，用 Page Bundle 就能直接调：

```markdown
{{ $img := .Resources.Get "cover.jpg" }}
{{ $small := $img.Resize "800x webp q80" }}
<img src="{{ $small.RelPermalink }}" width="{{ $small.Width }}" height="{{ $small.Height }}" alt="封面">
```

`Resize "800x webp q80"` 的意思是，宽度缩到 800，保持比例，转成 webp 格式，质量 80。webp 比 jpg 小百分之三十左右，肉眼几乎看不出区别。

如果要响应式，用 `srcset`：

```markdown
{{ $img := .Resources.Get "cover.jpg" }}
{{ $s := $img.Resize "480x webp" }}
{{ $m := $img.Resize "800x webp" }}
{{ $l := $img.Resize "1200x webp" }}
<img
  src="{{ $m.RelPermalink }}"
  srcset="{{ $s.RelPermalink }} 480w, {{ $m.RelPermalink }} 800w, {{ $l.RelPermalink }} 1200w"
  sizes="(max-width: 600px) 480px, (max-width: 900px) 800px, 1200px"
  width="{{ $m.Width }}" height="{{ $m.Height }}"
  loading="lazy" alt="封面">
```

`width` 和 `height` 一定要写。这是 Lighthouse 那个"图片元素没有明确的宽度和高度"的根源。有了这两个属性，浏览器在图片加载之前就能预留出空间，不会发生布局偏移。CLS 这个指标直接从 0.24 降到 0.01。

`loading="lazy"` 让首屏之外的图片延迟加载。但首屏的图片不要加，加了反而会拖慢 LCP。

## 字体

Stack 主题默认用的是系统字体栈，本来不该有这个问题。但我自己加了个思源黑体，从 Google Fonts 拉的。

问题在于，Google Fonts 的那个 css 是渲染阻塞的。浏览器必须等它下载完，才能决定用什么字体显示文字。国内访问 Google 的域名还经常超时，一等就是好几秒。

解决办法是把字体下到本地，自己托管：

```bash
mkdir -p static/fonts
wget -O static/fonts/NotoSansSC-Regular.woff2 "https://..."
```

然后在 css 里：

```css
@font-face {
  font-family: 'Noto Sans SC';
  src: url('/fonts/NotoSansSC-Regular.woff2') format('woff2');
  font-display: swap;
  unicode-range: U+4E00-9FFF;
}
```

`font-display: swap` 是关键。它让浏览器先用后备字体显示文字，等自定义字体下载完了再替换。用户不会看到一片空白。

中文字体文件很大，完整的思源黑体有十几兆。所以我又做了一步，用 `fonttools` 做子集化，只保留常用的三千多个字：

```bash
pip install fonttools brotli
pyftsubset NotoSansSC-Regular.otf --text-file=common.txt --flavor=woff2 --output-file=NotoSansSC-subset.woff2
```

这样能从十几兆压到六百多 KB。

不过说实话，后来我干脆把自定义字体删了，直接用系统字体栈：

```css
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
```

效果上没什么差别，还省了六百 KB 的下载。这是我折腾一圈之后最实际的一个决定。

## 渲染阻塞的 css 和 js

Hugo 生成的 css 是通过 `resources.Get` 和 `minify` 处理的，Stack 主题已经做得不错了。

但我检查的时候发现，有个 `custom.css` 是同步加载的，它在 `<head>` 里，会阻塞渲染。

如果这个 css 不大，可以直接内联：

```html
{{ $css := resources.Get "css/custom.css" | minify }}
<style>{{ $css.Content | safeCSS }}</style>
```

内联的好处是省掉一次请求。坏处是不能缓存，每次都要跟着 html 一起下载。所以只适合小文件，几百字节以内。

大一点的用 `preload`：

```html
<link rel="preload" href="/css/custom.css" as="style">
<link rel="stylesheet" href="/css/custom.css" media="print" onload="this.media='all'">
```

这个写法有点绕，原理是先以 `media="print"` 加载，这样浏览器不会把它当渲染阻塞资源，加载完了再通过 `onload` 把 media 改成 `all`。

js 那边，我给所有非关键的脚本都加了 `defer`：

```html
<script src="/js/main.js" defer></script>
```

`defer` 表示下载不阻塞解析，等 html 解析完了再按顺序执行。比 `async` 更可控，因为 `async` 的执行顺序不确定。

## 去掉那个第三方脚本

我在侧边栏加了个访问量统计，用的是某个第三方服务的小挂件。它加载的时候会额外拉三个资源，其中一个还卡了两秒。

看了下它的实现，就是一个 `img` 加一段脚本。我把它删了，换成了自己写的，用 Cloudflare 的 Workers 记录访问，前端只请求一个自己域名下的接口。

从三个跨域请求变成一个同域请求，这一项就省了将近一秒。

这个教训是，第三方的挂件比自己写的贵得多。你控制不了它的性能，也控制不了它什么时候挂。

## 缓存策略

静态博客的缓存可以设得很激进。我在 nginx 里给静态资源设了一年：

```nginx
location ~* \.(css|js|woff2|jpg|jpeg|png|webp|svg)$ {
    expires 1y;
    add_header Cache-Control "public, max-age=31536000, immutable";
}
```

前提是文件名带指纹。Hugo 的 `resources` 管道默认会给处理过的资源加 hash，比如 `custom.a1b2c3d4.css`，改内容就改名字，所以缓存一年也不会出问题。

html 不能这么设，我给了十分钟，加上 `must-revalidate`。

## 结构化数据

SEO 这块，除了 title 和 description，最重要的是给搜索引擎结构化数据。

Stack 主题自带了一部分，但不够全。我加了一段 JSON-LD，放在 `layouts/partials/head.html` 的扩展位置：

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BlogPosting",
  "headline": {{ .Title }},
  "datePublished": {{ .Date.Format "2006-01-02T15:04:05Z07:00" }},
  "dateModified": {{ .Lastmod.Format "2006-01-02T15:04:05Z07:00" }},
  "author": {"@type": "Person", "name": "{{ .Site.Params.author }}"},
  "mainEntityOfPage": {"@type": "WebPage", "@id": {{ .Permalink }}}
}
</script>
```

这个能让搜索结果里显示作者、日期这些信息，点击率会高一些。

## sitemap 和 robots

Hugo 默认会生成 `sitemap.xml`，不用管。

`robots.txt` 我用的是模板：

```text
User-agent: *
Allow: /
Disallow: /page/

Sitemap: {{ .Site.BaseURL }}sitemap.xml
```

`Disallow: /page/` 是分页页，这些页面内容重复，让爬虫抓了没意义，还分散权重。

## 收录的情况

提交了 sitemap 之后，我在 Google Search Console 里看，首页三天收录，文章页大概一周。

百度的收录慢很多，而且它对这个域名的抓取频率很低。我后来在百度站长平台手动提交了几次，情况好了一点，但依然不如 Google。

这个我没太纠结。写博客主要是给自己留个记录，有人搜到是意外收获。

## 那些没用的事

有几个优化我试过但放弃了。

一个是 `preconnect` 到各种第三方域名。我加了之后 Lighthouse 分数反而掉了两分，因为每个 `preconnect` 本身也要开销，域名一多就得不偿失。

一个是把 css 全内联。文件一大，html 体积涨到两百多 KB，首字节时间反而变长。现在只内联关键的那部分。

还有一个是 Service Worker 做离线缓存。技术上是能跑，但博客更新频率低，用户很少重复访问同一篇，收益不明显，还容易因为缓存版本没更新导致看到旧内容。

## 现在的成绩

移动端 96 分，桌面端 99。首屏八百毫秒左右，LCP 一点二秒。

这个分数在个人博客里算不错的，但我越来越觉得分数本身没那么重要。真正有用的是那几个具体的改动，图片压缩、字体本地化、去掉第三方脚本。这三件事做完，体验上的提升是能感觉到的，分数只是顺带的结果。

如果你的博客也慢，我建议先看图片。十有八九，问题就在那儿。
