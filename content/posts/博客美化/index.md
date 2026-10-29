---
title: '博客美化'
date: 2023-10-23T13:13:38+08:00
draft: false
description: '记录个人独立博客「寻 Mi 处」的完整折腾过程：Hugo Stack 主题配置、本地双字体混排、静态资源与 HTTPS 头像直链、友链小广场搭建及一些浏览器的奇葩小坑。'
slug: 'blog-building-and-customization-log'
categories: ['折腾日常', 'Hugo']
tags: ['Hugo', '博客美化', '前端', 'CSS']
comments: true
image: "cover.webp"
---

> *“在这个数字荒原中，每一个独立博客都是一座赛博孤岛，而亲手为它添砖加瓦，正是独属于程序员与极客的浪漫。”*

历经一番大大小小的像素级微调与踩坑，我的个人独立博客 **「寻 Mi 处」** (`https://blog.mibase.top`) 终于有了理想中的模样。

作为一个喜欢自己动手丰衣足食的折腾党，开箱即用的模板总觉得差了点灵魂。今天就把这段时间从零开始搭建、美化 Hugo Stack 主题的整个过程做个全盘复盘，既是给自己留个备份，也希望能给同样在折腾 Hugo 的朋友一点参考。

## 核心骨架：Hugo Stack 与自定义域名

博客基于目前非常现代化且颜值极高的 **Hugo Stack** 主题搭建。

* **自定义域名**：绑定了独立域名 `blog.mibase.top`。
* **HTTPS 加密**：通过后台配置与 CNAME 配合，全面启用了全站 HTTPS 安全访问，确保所有的静态资源加载都不会被浏览器安全策略拦截。

---

## 视觉灵魂：HarmonyOS Sans 与霞鹜文楷的本地双字体混排

网页的默认字体总显得有些千篇一律。为了兼顾现代科技感与长文阅读的温润感，我选择将两款优秀的开源/商用免费字体搬进本地：

1. **UI 与标题栏**：使用 `HarmonyOS Sans`（鸿蒙字体），线条干净利落，用在侧边栏、菜单和文章标题上极具现代感。
2. **正文阅读区**：使用 `霞鹜文楷 屏幕阅读版`（LXGW WenKai），正楷的微弧度让大段文字的阅读体验直线上升。

### 配置方式

将字体文件丢入 `static/fonts/` 目录下，并在 `layouts/partials/head/custom.html` 中通过 `@font-face` 声明并绑定：

```css
@font-face {
    font-family: 'HarmonyOS Sans';
    src: url('/fonts/HarmonyOS-Sans.ttf') format('truetype');
    font-display: swap;
}

@font-face {
    font-family: 'LXGW WenKai';
    src: url('/fonts/LXGWWenKai.ttf') format('truetype');
    font-display: swap;
}

/* 字体应用规则 */
body, p, article {
    font-family: "LXGW WenKai", serif !important;
}

h1, h2, h3, .sidebar, .menu, .article-title {
    font-family: "HarmonyOS Sans", sans-serif !important;
}
```

## 避坑指南：静态资源与 HTTPS 头像直链

在配置个人头像时，曾踩过一个小坑：误把图片放到了 `assets/` 目录。

- **避坑经验**：在 Hugo 中，只有放在 `static/` 目录下的文件（如 `static/img/miro.jpg`），才会在编译时原封不动地输出到网站根目录。
- 结合 `blog.mibase.top` 的 HTTPS 域名后，我的博主头像直链最终完美落地为：`https://blog.mibase.top/img/miro.jpg`

无论是博客侧边栏的个人 Logo，还是后续在各个页面中引用的名片头像，都能秒级稳定加载。

## 鼠标指针的“赛博幻觉”与现实

这次折腾中比较好玩（也比较头疼）的一个小插曲是自定义鼠标指针。

- 兴冲冲下载了一套很好看的二次元动态鼠标主题（Kuro 的 `.ani` 格式），结果放到网页上毫无反应。
- **技术真相**：现代网页浏览器（Chrome、Edge 等）出于底层安全与实现机制限制，在 CSS 的 `cursor` 属性中原生是不支持 `.ani`（动态光标）格式的——它毕竟是 Windows 桌面的专属产物。
- 既然无法直接使用动态光标，我们也可以通过转换为静态图片或拥抱网页开源的极客像素光标来替代。这也算是在折腾路上学到的小知识点。

## 文章头部元数据美化（短日期格式与强制阅读时长）

Hugo Stack 主题默认的日期格式和阅读时间渲染有时受国际化（i18n）配置影响。为了让日期完美显示为 **`2026-10-23`** 这种干净的格式，并且**强制稳定显示阅读时长**，我们需要通过 Hugo 的模板重写机制来进行自定义。

### 创建覆盖模板文件

在你的 Hugo 博客根目录下，创建以下路径的文件： 👉 **`layouts/partials/article/components/details.html`**

### 写入核心代码

将以下代码完整写入该文件中：

```yaml
<header class="article-header">
    {{- /* 1. 分类标签 */ -}}
    {{- if .Params.categories -}}
    <div class="article-category">
        {{- range (.GetTerms "categories") -}}
            {{- $color := partial "helper/color-from-str" .LinkTitle -}}
            {{- $BackgroundColor := default $color.BackgroundColor .Params.style.background -}}
            {{- $TextColor := default $color.TextColor .Params.style.color -}}
            <a href="{{ .RelPermalink }}" class="link" {{ if or $BackgroundColor $TextColor }}style="background-color: {{ $BackgroundColor }}; color: {{ $TextColor }};"{{ end }}>
                {{ .LinkTitle }}
            </a>
        {{- end -}}
    </div>
    {{- end -}}

    {{- /* 2. 文章标题 */ -}}
    <h1 class="article-title">{{ .Title }}</h1>

    {{- /* 3. 文章副标题/描述 */ -}}
    {{- with .Params.description -}}
    <h2 class="article-subtitle">{{ . }}</h2>
    {{- end -}}

    {{- /* 4. 日期与阅读时长元数据 */ -}}
    <div class="article-details">
        {{- /* 日期强制格式化为 2026-10-23 */ -}}
        <div class="article-date">
            <svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-calendar" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M4 7a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-12z" /><path d="M16 3v4" /><path d="M8 3v4" /><path d="M4 11h16" /><path d="M11 15h1" /><path d="M12 15v3" /></svg>
            <time class="publish-date">
                {{- .Date.Format "2006-01-02" -}}
            </time>
        </div>

        {{- /* 强制稳定显示阅读时长 */ -}}
        {{- $showReadingTime := .Params.readingTime | default (.Site.Params.article.readingTime) -}}
        {{- if $showReadingTime -}}
        <div class="article-reading-time">
            <svg xmlns="http://www.w3.org/2000/svg" class="icon icon-tabler icon-tabler-clock" width="24" height="24" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0 -18 0" /><path d="M12 12v-3" /><path d="M12 12l3 3" /></svg>
            <span>阅读时长：{{ .ReadingTime }} 分钟</span>
        </div>
        {{- end -}}
    </div>
</header>
```

## 页脚全局集成：萌 ICP 备案、APlayer 动漫音乐播放器与 Sakana-Widget 看板娘

Hugo Stack 主题允许我们在页脚或自定义脚本 partial 中挂载全局组件。我们将**萌 ICP 备案号**、**10首动漫神曲 APlayer 播放器**以及**井上泷奈看板娘**统一整合成一个高效的组合。

### 创建或修改自定义页脚文件

路径：👉 **`layouts/partials/footer/custom.html`**

### 写入整合代码

将以下完整的精简纯净代码填入文件中：

```
<!-- ==================== 1. 萌 ICP 备案号挂载 ==================== -->
<div id="icp-container" style="text-align: center; margin: 15px 0; font-size: 0.85rem;">
    <a href="https://icp.gov.moe/?keyword=20260690" target="_blank" rel="noopener noreferrer" style="color: var(--secondary-text-color); text-decoration: none; transition: color 0.2s ease;">
        萌ICP备xxxxxxxx号
    </a>
</div>

<style>
#icp-container a:hover {
    color: var(--accent-color);
}
</style>

<script>
document.addEventListener('DOMContentLoaded', function() {
    const footer = document.querySelector('.site-footer');
    const icpContainer = document.getElementById('icp-container');
    if (footer && icpContainer) {
        footer.appendChild(icpContainer);
    }
});
</script>


<!-- ==================== 2. APlayer 动漫音乐播放器（右下角） ==================== -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/aplayer@1.10.1/dist/APlayer.min.css">
<script src="https://cdn.jsdelivr.net/npm/aplayer@1.10.1/dist/APlayer.min.js"></script>
<div id="aplayer"></div>

<style>
    /* 迷你播放器固定在右下角，避开左下角元素与暗色模式开关 */
    .aplayer.aplayer-fixed .aplayer-body { 
        left: auto !important; 
        right: 0 !important; 
    }
    .aplayer.aplayer-fixed { 
        z-index: 99 !important; 
    }

    /* 手机端隐藏播放器，避免遮挡页面内容与占用性能 */
    @media (max-width: 768px) {
        .aplayer.aplayer-fixed { 
            display: none !important; 
        }
    }
</style>

<script>
document.addEventListener('DOMContentLoaded', function() {
    if (typeof APlayer === 'undefined') return;

    try {
        new APlayer({
            container: document.getElementById('aplayer'),
            fixed: true,
            mini: true,
            autoplay: false,
            loop: 'all',
            order: 'list',
            preload: 'none',
            volume: 0.6,
            listFolded: true,
            audio: [
                {
                    name: 'only my railgun',
                    artist: 'fripSide',
                    url: 'https://music.163.com/song/media/outer/url?id=167908.mp3',
                    cover: 'https://p2.music.126.net/6y-UleORITEDBvrOLV0Q8A==/5639395138885805.jpg'
                },
                {
                    name: 'LEVEL5-judgelight-',
                    artist: 'fripSide',
                    url: 'https://music.163.com/song/media/outer/url?id=167906.mp3',
                    cover: 'https://p1.music.126.net/6y-UleORITEDBvrOLV0Q8A==/5639395138885805.jpg'
                },
                {
                    name: '千本桜',
                    artist: '初音ミク / 黒うさP',
                    url: 'https://music.163.com/song/media/outer/url?id=186026.mp3',
                    cover: 'https://p1.music.126.net/W90vN40T1j1_4319j7v5lQ==/109951163457999127.jpg'
                },
                {
                    name: '打上花火',
                    artist: 'DAOKO / 米津玄師',
                    url: 'https://music.163.com/song/media/outer/url?id=483018251.mp3',
                    cover: 'https://p2.music.126.net/eU3-w56f-DqM7a_O39Xw9g==/109951162955554109.jpg'
                },
                {
                    name: '前前前世',
                    artist: 'RADWIMPS',
                    url: 'https://music.163.com/song/media/outer/url?id=414577884.mp3',
                    cover: 'https://p1.music.126.net/W90vN40T1j1_4319j7v5lQ==/109951163457999127.jpg'
                },
                {
                    name: '君の知らない物語',
                    artist: 'supercell',
                    url: 'https://music.163.com/song/media/outer/url?id=657668.mp3',
                    cover: 'https://p2.music.126.net/7_z0Y_j3i0-9X669z08JtA==/109951163124115403.jpg'
                },
                {
                    name: '夜に駆ける',
                    artist: 'YOASOBI',
                    url: 'https://music.163.com/song/media/outer/url?id=1424982740.mp3',
                    cover: 'https://p1.music.126.net/1yvj1938FwH49zXy9hVw-Q==/109951164724213609.jpg'
                },
                {
                    name: '紅蓮華',
                    artist: 'LiSA',
                    url: 'https://music.163.com/song/media/outer/url?id=1365313391.mp3',
                    cover: 'https://p1.music.126.net/3-9pI7eC6eX5yH789Z401w==/109951164079865181.jpg'
                },
                {
                    name: '残酷な天使のテーゼ',
                    artist: '高橋洋子',
                    url: 'https://music.163.com/song/media/outer/url?id=25664448.mp3',
                    cover: 'https://p2.music.126.net/R-x2zL0J7X0i5f9rX9w2bQ==/109951163219491039.jpg'
                },
                {
                    name: '恋愛サーキュレーション',
                    artist: '花澤香菜',
                    url: 'https://music.163.com/song/media/outer/url?id=297244.mp3',
                    cover: 'https://p1.music.126.net/06-4Nn_Y6y34m1G8O3r70g==/109951163234902111.jpg'
                }
            ]
        });
    } catch (e) {
        console.warn('APlayer 加载异常:', e);
    }
});
</script>


<!-- ==================== 3. Sakana-Widget 井上泷奈看板娘（右下角） ==================== -->
<div id="sakana-widget"></div>

<style>
/* 摆件样式固定在右下角，赋予合适层级 */
#sakana-widget {
    position: fixed;
    bottom: 10px;
    right: 10px;
    z-index: 998;
    pointer-events: auto;
}

/* 核心性能优化：手机端（<= 768px）彻底隐藏看板娘，节省带宽与流量 */
@media screen and (max-width: 768px) {
    #sakana-widget {
        display: none !important;
    }
}
</style>

<!-- 引入 Sakana-Widget 样式表 -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/sakana-widget@2.7.0/lib/sakana.css" />

<script>
document.addEventListener('DOMContentLoaded', function() {
    /* 仅在屏幕宽度大于 768px（电脑/平板）时动态加载看板娘脚本 */
    if (window.innerWidth > 768) {
        const sakanaScript = document.createElement('script');
        sakanaScript.src = "https://cdn.jsdelivr.net/npm/sakana-widget@2.7.0/lib/sakana.js";
        sakanaScript.async = true;
        sakanaScript.onload = () => {
            try {
                new SakanaWidget({
                    character: 'takina', // 井上泷奈
                    size: 180,           // 摆件大小
                    autoFit: true,       // 自适应
                    draggable: true      // 允许鼠标拖拽互动
                }).mount('#sakana-widget');
            } catch (e) {
                console.log("SakanaWidget init error:", e);
            }
        };
        document.head.appendChild(sakanaScript);
    }
});
</script>
```