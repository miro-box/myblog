---
# ==================== 必填（3 项）====================
title: "给 Cloudflare 配上缓存规则之后，博客的图片终于不用每次回源了"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-02-05T02:45:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "记录我给 blog.mibase.top 配 Cloudflare 缓存规则的过程，以及命中率从四成涨到九成之后到底快了多少。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，建议英文。例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "架构部署"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Cloudflare"
    - "CDN"
    - "缓存"
    - "前端优化"

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

域名托管到 Cloudflare 有一段时间了，页面打开速度一直说不上好。白天在公司摸鱼的时候打开自己的博客，首屏的图片总是一块一块地往下蹦，像是网速被谁掐了一半。

打开 F12 看 Network，问题挺明显的。那些几十 KB 的封面图，每一张的响应时间都在三百毫秒往上，而且不管我刷新多少次，它都是这个速度。点开 Response Headers 一看，`CF-Cache-Status` 是 `MISS`，有时候干脆是 `DYNAMIC`。意思很清楚，Cloudflare 根本没帮我存，每次都是它跑回我的 VPS 拿一遍，再转手给我。

我这才认真去看了它的缓存逻辑。

## 默认只缓存一小撮东西

Cloudflare 的免费套餐对缓存是做了限制的。它只对一部分后缀名有默认缓存行为，比如 css、js、图片、字体这些。听起来好像我需要的都在里面，但实际上还有一个坑，就是缓存时长很短，而且第一次请求之后 Edge 节点上存不存、存多久，还要看源站给的 `Cache-Control`。

我的 Nginx 那时候配置得很随便，静态资源只写了 `expires 7d`，别的什么都没管。Cloudflare 拿到这个头，就按七天存。听着还行，可我博客的图换了之后，七天之内访客看到的还是旧图，这个体验很别扭。

后来我把思路理清楚了。图片、字体、css、js 这些东西带上内容指纹，改一次文件名就变一次，这种资源可以放心地缓存很久，甚至一年。HTML 不行，HTML 一改就得让用户立刻看到新的。

## 换成 Cache Rules

网上很多老教程还在教你用 Page Rules。这个功能 Cloudflare 从 2023 年就开始推着大家迁走了，免费套餐能建的条数也少，表达式写法也老旧。现在应该用的是 Rules 里的 Cache Rules，逻辑更清楚，条件可以写得很细。

我进控制台，左边找到 Rules，点 Cache Rules，Create rule。

名字随便起，我写的是 `static-assets`。下面 When incoming requests match 那里，选 Custom filter expression，然后填：

```text
(http.request.uri.path.extension in {"jpg" "jpeg" "png" "gif" "webp" "svg" "ico" "css" "js" "woff" "woff2" "ttf"})
```

这个写法比老教程里那种一串 `contains` 拼起来要干净得多，它是直接判断路径后缀。

Then 那部分做这些设置：

```text
Cache eligibility: Eligible for cache
Edge TTL: Ignore cache-control header and use this TTL -> 1 month
Browser TTL: Override origin -> 1 month
```

Edge TTL 是 Cloudflare 自己节点上存多久，Browser TTL 是告诉访客的浏览器存多久。两个都拉长，命中率才上得去。免费套餐的 Edge TTL 最长就是一个月，够用了。

这里有个细节值得说一下。如果你选的是 `Use cache-control header if present`，那 Cloudflare 就会听源站的，你 Nginx 里写 7 天它就是 7 天。想让 Cloudflare 说了算，就得选 ignore 那一项。我第一次没注意，改完发现一点变化都没有，白折腾了半小时。

## HTML 也可以缓存，但要小心

纯静态博客有个好处，HTML 也是构建出来的静态文件，没有数据库查询，缓存起来毫无压力。我另外加了一条规则，只针对 HTML：

```text
(http.request.uri.path.extension eq "")
```

然后 Edge TTL 设成 2 小时，Browser TTL 设成 30 分钟。

为什么留这么短。因为我一改文章就得让人看到新的。两小时对我来说是个能接受的窗口，写完文章去 Cloudflare 那边手动 Purge 一下就行。如果哪天忘了 Purge，最多两小时也会自己过期，不至于一直挂着旧内容。

Browser TTL 我压得更短，是因为浏览器缓存最难清。用户本地存着的 HTML，你在服务器上怎么改他都不知道，只能等他缓存过期。30 分钟是个折中。

## 源站那边也得配合

只改 Cloudflare 不管源站，效果会打折扣。我在 Nginx 里把静态资源的响应头重写了一遍：

```nginx
location ~* \.(jpg|jpeg|png|gif|webp|svg|ico|css|js|woff2?)$ {
    expires 1y;
    add_header Cache-Control "public, max-age=31536000, immutable";
    access_log off;
}
```

`immutable` 这个值挺有用。它告诉浏览器，这个文件在有效期内绝对不会变，用户按 F5 刷新的时候不用再发一次条件请求。少了这个 `304` 往返，刷新页面的感觉会明显快一截。

前提是你的文件名得带指纹。Hugo 生成的 css 和 js 默认是带 hash 的，图片是我自己命名的，没带。所以我给图片加了个小约定，文件名后面缀上内容的前八位哈希，改图就改名，这样缓存一年也不会出问题。

## 验证到底有没有生效

改完之后别急着高兴，得实际去看。

最直接的办法是 curl：

```bash
curl -sI https://blog.mibase.top/images/cover.jpg | grep -i cf-cache
```

第一次大概率是 `MISS`，这是正常的，节点上还没有。再跑一次，应该就变成 `HIT` 了。如果跑了好几次还是 `MISS`，那就回去看看规则的条件是不是没匹配上，或者 Cache eligibility 是不是还停在 `Bypass cache`。

还有一个 `DYNAMIC`，这个值的意思是 Cloudflare 认为这个请求不该走缓存。通常出现在 HTML 上，或者规则没命中。

我还注意到有个 `REVALIDATED`，那是源站返回了 304，Cloudflare 拿旧的继续用。这个状态其实也挺好，至少没重新传一遍完整内容。

## 命中率从四成到九成

Cloudflare 控制台的 Caching 下面有个 Analytics，能看到缓存命中率。我改之前是 41% 左右，改完第二天稳定在 92% 上下。

这个数字带来的变化是很实在的。以前国内访问我的博客，图片要绕到我的 VPS 上拿，VPS 在洛杉矶，一个来回就是两百多毫秒。现在大部分请求落在 Cloudflare 离用户最近的节点上，二三十毫秒就回来了。

还有一个连带的好处，源站的带宽掉得很明显。Cloudflare 后台显示回源流量少了七成多，我那台按流量计费的机器，账单也跟着降了。

## 几个踩过的坑

规则是有优先级的，同一个请求命中多条规则时，只有最上面那条生效。我一开始把 HTML 的规则放在最前面，结果图片规则被它盖住了，因为 HTML 那条的条件写得太宽。顺序一定要捋一遍。

`Purge Everything` 别乱点。它会把你所有节点上的缓存全部清掉，清完之后的一段时间里，所有请求都会压到源站上。我手滑点过一次，那一分钟 VPS 的负载直接飙到 8。后来我都是按 URL 精确 Purge。

还有 `Vary` 头。如果你的源站返回了 `Vary: Cookie` 之类的东西，Cloudflare 基本就不会缓存这个响应了，因为同一个 URL 对应太多变体。静态博客一般没这个问题，但如果你在 Nginx 里加过什么奇怪的配置，值得检查一下。

## 写在最后

这件事的性价比确实高。不用升级套餐，不用换服务器，只是把规则写对，速度就上了一个台阶。

我现在给静态站做优化的顺序基本固定了。先看资源有没有带指纹，再看缓存头怎么写，最后才去考虑 Cloudflare 那层。前面两步做扎实，CDN 才帮得上忙。顺序反过来的话，你在 CDN 后台点半天，源站一个 `no-cache` 就把你打回原形。
