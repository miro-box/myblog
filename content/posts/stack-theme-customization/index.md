---
# ==================== 必填（3 项）====================
title: "Stack 主题用了半年，这些地方我都改过"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2025-07-25T11:35:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从首页信息、侧边栏、代码块到归档页，把 Stack 主题的每一处小改造和对应的文件位置都记下来。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "博客搭建"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Hugo"
    - "Stack"
    - "主题定制"

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

Stack 这个主题，默认配置出来的样子已经挺好了。我用它就是因为开箱即用，不用折腾。

但用久了总会想改点东西。有些是审美上的，有些是功能上的，有些纯粹是强迫症。

改的时候我一直坚持一个原则，能不碰主题源码就不碰。因为主题是 submodule，你一改，下次更新就冲突。

所以下面的改动，全部通过 Hugo 的覆盖机制实现。要么是配置，要么是在 `layouts` 下面放同名的文件。

## 先搞清楚覆盖是怎么工作的

Hugo 查找模板的顺序是，项目根目录的 `layouts` 优先，然后是主题的 `layouts`。

所以你想改主题里的 `layouts/partials/footer.html`，不需要去 `themes/hugo-theme-stack/layouts/partials/` 改，只需要在项目的 `layouts/partials/` 下放一个同名文件，Hugo 会自动用你的。

这个机制叫 template lookup order，官方文档里有完整的顺序表。

配置也一样。主题的 `exampleSite/config/_default/` 是默认值，你在自己的 `config/_default/` 里写同名文件，就是覆盖。

## 首页的副标题

Stack 的首页左侧有个大标题和一段描述，来自 `config/_default/params.toml`：

```toml
[sidebar]
    emoji = "���"
    subtitle = "记录一些折腾的过程"
    avatar = "img/avatar.png"
```

`emoji` 会显示在标题旁边。`subtitle` 是标题下面那行小字。

`avatar` 的路径是相对于 `assets` 目录的。所以你要把头像放在 `assets/img/avatar.png`，不是 `static`。

这一点容易搞混。Stack 用的是 Hugo Pipes 处理图片，`assets` 下的东西才能被处理。

## 社交图标

```toml
[[params.social]]
    name = "github"
    icon = "brand-github"
    weight = 10
    url = "https://github.com/yourname"

[[params.social]]
    name = "rss"
    icon = "rss"
    weight = 20
    url = "/index.xml"
```

`icon` 用的是 Tabler Icons 的名字。完整列表在 tabler-icons.io 上，找的时候去掉前面的 `brand-` 或者 `outline-` 前缀看。

`weight` 决定顺序，小的在前。

## 侧边栏的菜单

```toml
[[menu.main]]
    identifier = "home"
    name = "首页"
    url = "/"
    weight = 10

[[menu.main]]
    identifier = "archives"
    name = "归档"
    url = "/archives/"
    weight = 20

[[menu.main]]
    identifier = "search"
    name = "搜索"
    url = "/search/"
    weight = 30
```

注意 `url` 结尾的斜杠。Hugo 的 `baseURL` 带斜杠，页面 URL 也带，不加斜杠会导致相对路径解析出错。

归档页和搜索页需要在 `content/page/` 下面建对应的目录，不然点了 404。

## 代码块的样式

Stack 的代码高亮用的是 Chroma。默认的配色是 `monokai`，我觉得在亮色背景下太刺眼。

改成 `github`：

```toml
[markup.highlight]
    noClasses = false
    codeFences = true
    guessSyntax = false
    lineNos = false
    lineNumbersInTable = false
    tabWidth = 4
    style = "github"
```

`noClasses = false` 这个设置很关键。它让 Chroma 输出 class 而不是内联样式，这样你才能用自己的 css 覆盖配色。

`guessSyntax = false` 是我改的。默认是 true，它会猜代码块的语言，猜错了反而难看。显式写语言更可靠。

暗色模式下的配色，Stack 有单独的处理。在 `assets/scss/custom.scss` 里：

```scss
[data-scheme="dark"] {
  .highlight {
    .chroma {
      background-color: #1e1e1e;
    }
  }
}
```

## 代码复制按钮

Stack 本身没带这个功能，但实现起来不难。

先加一个 partial，`layouts/partials/article/components/copy-button.html`：

```html
<button class="copy-code-button" aria-label="复制代码">
  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
    <rect x="9" y="9" width="13" height="13" rx="2"></rect>
    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
  </svg>
</button>
```

然后在 `assets/js/custom.js` 里加事件：

```javascript
document.querySelectorAll('pre > code').forEach((codeBlock) => {
  const button = document.createElement('button');
  button.className = 'copy-code-button';
  button.textContent = '复制';
  button.addEventListener('click', async () => {
    await navigator.clipboard.writeText(codeBlock.innerText);
    button.textContent = '已复制';
    setTimeout(() => { button.textContent = '复制'; }, 1500);
  });
  codeBlock.parentElement.style.position = 'relative';
  codeBlock.parentElement.appendChild(button);
});
```

`navigator.clipboard` 需要 https，http 下是 undefined。本地开发用 `localhost` 是可以的，因为浏览器把 localhost 当安全上下文。

Stack 会自动加载 `assets/js/custom.js`，不用额外配置。这个约定挺方便的。

## 目录的样式

Stack 的 TOC 在文章右侧，宽屏下才显示。我改了一下它的位置和宽度。

在 `assets/scss/custom.scss` 里：

```scss
@media (min-width: 1280px) {
  .article-toc {
    position: sticky;
    top: 2rem;
    max-height: calc(100vh - 4rem);
    overflow-y: auto;
  }
}
```

`position: sticky` 让目录在滚动的时候跟着走，但滚到底部就停住。这个体验比固定定位好，不会挡住页脚。

## 页脚的备案号

国内的站需要放备案号，链接到工信部的网站。

`layouts/partials/footer/footer.html`：

```html
<footer class="footer">
    <div class="container">
        <div class="footer-content">
            {{- with .Site.Params.footer.since }}
            <span>&copy; {{ . }} - {{ now.Year }}</span>
            {{- end }}
            <span>{{ .Site.Params.footer.copyright }}</span>
            <a href="https://beian.miit.gov.cn/" target="_blank" rel="noopener">
                京ICP备xxxxxxxx号
            </a>
        </div>
    </div>
</footer>
```

`rel="noopener"` 一定要加。外链带 `target="_blank"` 而不加 `noopener`，被链接的页面可以通过 `window.opener` 操作你的页面，这是个经典的安全问题。

## 文章卡片的摘要长度

Stack 默认取文章的前若干字符做摘要。这个长度可以在 front matter 里用 `description` 控制，也可以在配置里全局设：

```toml
[params.article]
    summary = "auto"
```

`auto` 是自动截取。如果你想让每篇文章用自己的 `description`，设成 `"description"`。

我觉得用 `description` 更好，因为自动截取经常截在奇怪的地方，句子断在半截。

## 暗色模式的默认值

Stack 默认跟随系统。但我想让它默认是暗色。

`assets/js/custom.js`：

```javascript
document.addEventListener('DOMContentLoaded', () => {
  const saved = localStorage.getItem('prefers-color-scheme');
  if (!saved) {
    document.documentElement.dataset.scheme = 'dark';
    localStorage.setItem('prefers-color-scheme', 'dark');
  }
});
```

Stack 自己用 `localStorage` 存用户的选择，键名是 `prefers-color-scheme`。我们先检查有没有存过，没存过就设成 dark。

这个改动要小心，因为它会在页面渲染之后才执行，可能有一瞬间的闪烁。要彻底解决得在 `<head>` 里内联一段脚本，但那就要改 `head.html` 了。

## 归档页的分组

Stack 的归档页默认按年份分组，这个我觉得挺好的，没改。

但我加了一个显示每年文章数的功能。

`layouts/partials/page/archive.html` 里，找到渲染年份的地方，改成：

```html
<h2 class="archive-year">
  {{ .Key }}
  <span class="archive-count">{{ len .Pages }}</span>
</h2>
```

`.Pages` 是 Hugo 的分组对象里的字段，包含这一组的所有页面。`len` 拿到数量。

## 搜索

Stack 内置了搜索，用的是 `fuse.js` 加一个生成的 `index.json`。

需要在配置里开：

```toml
[params]
    [params.search]
        enable = true
```

然后建一个 `content/page/search/index.md`，front matter 里写：

```yaml
---
title: "搜索"
layout: "search"
---
```

`layout: search` 会让 Hugo 用主题里的搜索模板。

搜索的索引文件在 `public/index.json`，Hugo 构建的时候自动生成。如果搜索没结果，先看看这个文件在不在。

## 一个我踩过的坑

改完 `custom.scss` 之后，样式没生效。

原因是 Hugo 的 `resources` 缓存。它会把编译过的 scss 存在 `resources/_gen/` 下面，改了源文件但缓存没失效的时候，用的还是旧的。

解决办法：

```bash
hugo --gc
```

或者手动删掉 `resources/_gen/`。我后来在部署脚本里固定加了 `--gc`，就没再遇到。

## 主题更新的处理

因为所有改动都在项目目录里，更新主题不会冲突。

```bash
git submodule update --remote themes/hugo-theme-stack
```

跑完之后看一眼有没有报错，然后本地 `hugo server` 确认样式没坏。

有一次更新之后，侧边栏的布局变了，因为主题改了一个 class 名。我的 `custom.scss` 里覆盖的规则就失效了。这种情况只能看一眼 release notes，手动改。

## 现在

改了这么多，主题的骨架还是原样，只是细节上更合我的习惯。

我一直觉得，主题定制最好的状态是，别人看不出你用了什么主题，但你自己用着舒服。

过度定制的反面教材我也见过，有人把主题改得面目全非，结果每次更新都要花一天合并冲突。那还不如自己从头写一个。

我的建议是，先列出来你真正需要的改动，通常不超过十条。剩下那些"看起来可以更好"的，忍住。
