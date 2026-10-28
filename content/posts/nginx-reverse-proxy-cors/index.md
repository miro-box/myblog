---
# ==================== 必填（3 项）====================
title: "前后端分离之后，CORS 报错缠了我整整一个下午"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2024-12-09T04:26:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "从浏览器控制台那行红字开始，讲清楚预检请求、Allow-Origin 不能写星号、凭证和 Nginx 该怎么配。"                                # 一句话简介（显示在首页卡片/RSS）。例："记录我用 Hugo 搭博客的全过程"
slug: ""                                       # 网址后缀，例：my-first-post → /p/my-first-post/；留空=用文件名
categories:                                    # 分类：只选 1 个
    - "服务器运维"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Nginx"
    - "CORS"
    - "排障"

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

朋友让我帮忙看一个后台管理页面，说他本地跑得好好的，部署到服务器上之后，登录接口一直报错。

控制台里的红字是这样的：

```text
Access to XMLHttpRequest at 'https://api.example.com/auth/login'
from origin 'https://admin.example.com' has been blocked by CORS policy:
Response to preflight request doesn't pass access control check:
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

典型的 CORS。我当时心想，加个头的事，十分钟搞定。

结果从下午两点弄到六点。

## 先说清楚 CORS 是什么

跨域资源共享，是浏览器的一套安全机制。

浏览器有个同源策略。两个 URL，协议、域名、端口三者完全一样才算同源。`https://a.com` 和 `https://api.a.com` 不同源，`https://a.com` 和 `http://a.com` 也不同源，端口不同更不用说。

不同源之间的请求，浏览器默认会拦。但这个拦分两种。

简单请求，浏览器直接发出去，服务器返回了，浏览器检查响应头里有没有 `Access-Control-Allow-Origin`，没有就把结果丢掉，报错。注意，请求是真的发出去了，服务器也真的处理了，只是浏览器不把结果给页面。

非简单请求，浏览器会先发一个 `OPTIONS` 请求，叫预检。服务器要在这个预检的响应里明确告诉浏览器，允许哪些方法、哪些头。预检通过了，浏览器才发真正的请求。

什么算非简单请求。方法不是 GET、HEAD、POST 的；Content-Type 不是 `application/x-www-form-urlencoded`、`multipart/form-data`、`text/plain` 的；带了自定义请求头的。这三条占一条就算。

我的登录接口用的是 `POST` 加 `Content-Type: application/json`，所以是非简单请求，会触发预检。

## 先看看预检返回了什么

用 curl 模拟一下：

```bash
curl -i -X OPTIONS https://api.example.com/auth/login \
  -H "Origin: https://admin.example.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type"
```

返回：

```text
HTTP/2 405
server: nginx/1.24.0
content-type: text/html
allow: POST
```

405 Method Not Allowed。也就是说，Nginx 把 `OPTIONS` 请求转给了后端，后端不认识 `OPTIONS` 这个方法，直接拒绝了。

问题找到了。后端框架没有处理预检请求。

## 让后端来处理

如果后端是 Spring Boot，加一个全局配置：

```java
@Configuration
public class CorsConfig implements WebMvcConfigurer {
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                .allowedOrigins("https://admin.example.com")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .allowCredentials(true)
                .maxAge(3600);
    }
}
```

`allowCredentials(true)` 是为了让浏览器带上 cookie。这个后面会讲到，它有个限制。

如果是 Express：

```javascript
const cors = require('cors');
app.use(cors({
  origin: 'https://admin.example.com',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  maxAge: 3600
}));
```

这个是正路。但有个前提，后端得能改。我这个朋友的后端是外包做的，源码不在手上，只能从 Nginx 那边想办法。

## 在 Nginx 里拦下来

Nginx 的做法是，遇到 `OPTIONS` 请求，直接返回，不往后端转。

```nginx
location /auth/ {
    if ($request_method = 'OPTIONS') {
        add_header 'Access-Control-Allow-Origin' 'https://admin.example.com' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization' always;
        add_header 'Access-Control-Max-Age' 3600 always;
        add_header 'Content-Length' 0;
        return 204;
    }

    add_header 'Access-Control-Allow-Origin' 'https://admin.example.com' always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;

    proxy_pass http://backend;
}
```

几个细节。

`return 204` 是 No Content，预检请求不需要返回内容，204 是标准做法。有些教程写 `200`，也能过，但 204 更准确。

`always` 这个参数很重要。不加它，`add_header` 只在响应码是 200、201、204、206、301、302、303、304、307、308 的时候才生效。如果后端返回 400 或者 500，头就没了，浏览器那边会报 CORS 错误，把真正的问题盖住。

`Content-Length 0` 是为了让某些严格的客户端不等待响应体。

`if` 在 `location` 里用是有风险的，官方文档里叫 "if is evil"。但这个场景是安全的，因为它只是判断一个变量然后 return，不涉及 `proxy_pass` 的重新求值。这是官方文档里明确认可的一种用法。

## 为什么不能写星号

很多人图省事，直接写：

```nginx
add_header 'Access-Control-Allow-Origin' '*';
```

这个在不需要 cookie 的场景下是可以的。但只要你的前端带上了 `credentials: 'include'`，或者 `withCredentials = true`，浏览器就会拒绝。

因为规范里写得很清楚，`Access-Control-Allow-Origin` 是 `*` 的时候，`Access-Control-Allow-Credentials` 不能是 `true`。

原因不难理解。如果允许任意源加凭证，那任何网站都能带着用户的 cookie 请求你的接口，这就是 CSRF。

所以我用了具体的域名，而不是星号。

## 多个域名怎么办

如果前端有好几个域名，比如正式环境和测试环境，就得动态判断。

```nginx
map $http_origin $cors_origin {
    default "";
    "~^https://admin\.example\.com$"      $http_origin;
    "~^https://staging\.example\.com$"    $http_origin;
    "~^http://localhost:5173$"            $http_origin;
}

server {
    location /api/ {
        add_header 'Access-Control-Allow-Origin' $cors_origin always;
        add_header 'Access-Control-Allow-Credentials' 'true' always;
        add_header 'Vary' 'Origin' always;
        ...
    }
}
```

`map` 里的正则要转义点号，不然 `example.com` 会匹配到 `exampleXcom`。

`add_header Vary Origin` 这一行别漏。它告诉缓存层，同一个 URL 对不同 Origin 的响应可能不一样。没有它，CDN 或者浏览器可能把 A 域名的响应缓存下来给 B 域名用，导致时好时坏。

## 一个特别隐蔽的问题

配完之后，登录接口通了，但另一个接口还是报错。

```text
The 'Access-Control-Allow-Origin' header contains multiple values
'https://admin.example.com, https://admin.example.com', but only one is allowed.
```

头出现了两次。

原因是，Nginx 加了，后端也加了。两边的值一样，但浏览器只接受一个。

排查方法：

```bash
curl -sI https://api.example.com/some/endpoint -H "Origin: https://admin.example.com" | grep -i access-control
```

能看到重复的行。

解决办法是二选一。要么让后端别加，要么在 Nginx 里用 `proxy_hide_header` 把后端的那个藏起来：

```nginx
proxy_hide_header 'Access-Control-Allow-Origin';
add_header 'Access-Control-Allow-Origin' $cors_origin always;
```

这个坑我踩了很久，因为报错信息里说的是 "multiple values"，但它不会告诉你这两个值是从哪儿来的。

## Cookie 相关的额外配置

如果前后端不同域，cookie 的 `SameSite` 属性会挡住。

从 Chrome 80 开始，`SameSite` 默认是 `Lax`，意思是跨站请求不带 cookie。前后端不同域，就是跨站。

解决办法是把 cookie 设成 `SameSite=None; Secure`。

`None` 必须配 `Secure`，也就是说必须走 https。http 环境下浏览器会直接拒绝这个 cookie。

如果是后端设的 cookie，得改后端的配置。如果是 Nginx 设的，可以这样：

```nginx
proxy_cookie_flags ~ secure samesite=none;
```

这个指令从 Nginx 1.19.3 开始有。

## 预检缓存

每次跨域请求之前都要发一个 OPTIONS，这个开销不小。

`Access-Control-Max-Age` 就是用来缓存的，单位是秒。

```nginx
add_header 'Access-Control-Max-Age' 3600 always;
```

一小时之内，同一个 URL 的预检结果会被浏览器缓存，不再重复发。

这个值不能设太大。Chrome 的上限是两小时，Firefox 是二十四小时。设成 86400 在 Chrome 里也只生效两小时。

我设的 3600，一小时。对于接口地址比较稳定的场景够用了。

## 怎么快速验证

我后来形成了一个固定的验证流程。

先看预检：

```bash
curl -i -X OPTIONS https://api.example.com/auth/login \
  -H "Origin: https://admin.example.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type"
```

返回里应该能看到 `Access-Control-Allow-Origin`，状态码 204。

再看实际请求：

```bash
curl -i -X POST https://api.example.com/auth/login \
  -H "Origin: https://admin.example.com" \
  -H "Content-Type: application/json" \
  -d '{"user":"test","pass":"test"}'
```

也要有 `Access-Control-Allow-Origin`。

最后在浏览器里看 Network 面板。预检请求的 Status 应该是 204，Response Headers 里有那几个头。实际请求也一样。

如果 curl 能过但浏览器不过，那多半是 cookie 或者 `Vary` 的问题。

## 还有几种替代方案

如果前后端都是自己控制的，最干净的做法是把它们放在同一个域名下。

前端在 `https://example.com`，后端在 `https://example.com/api`，Nginx 按路径分流。这样就完全没有跨域问题。

我的博客就是这个结构，静态文件在根路径，接口在 `/api/` 下面，同一个域名，省心。

还有一种是用开发代理。Vite 的 `server.proxy`、webpack 的 `devServer.proxy`，本地开发的时候把 `/api` 代理到后端，浏览器看到的是同源请求。这个只解决开发环境，生产环境还是得配 CORS。

## 现在回头看

这件事花了一下午，其中真正解决问题的配置只有十几行。时间都花在排查上了。

如果一开始就知道去看预检请求的返回，可能半小时就搞定了。但当时我一直在看实际请求，没意识到问题出在 OPTIONS 那一步。

这也是 CORS 最烦人的地方，它的报错信息永远指向结果，不指向原因。你得自己一层层往回找。

现在我的习惯是，遇到 CORS，第一件事永远是 curl 一遍 OPTIONS。这一步做完，问题基本就定位了。
