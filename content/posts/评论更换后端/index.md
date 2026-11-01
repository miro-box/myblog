---
# ==================== 必填（3 项）====================
title: "谁还在用 GitHub 登录发评论？我把博客评论区搬到 Netlify 后的全套折腾与避坑指南"   # 标题：由文件名自动生成，直接改成中文标题即可
date: 2026-11-01T12:00:00+08:00                              # 发布时间：自动生成，不用动
draft: false                                    # 草稿开关：true=不发布；写完改成 false 再 push

# ==================== 建议填 ====================
description: "深度解析为什么从 Giscus/Utterances 迁移到 Twikoo+Netlify，涵盖 MongoDB 数据库配置、Resend SMTP 587 端口踩坑实录、Cloudflare Turnstile 无感防刷机制及 Stack 主题专属邮件模板定制。"                                # 一句话简介（显示在首页卡片/RSS）
slug: "migrate-giscus-to-twikoo-netlify"         # 网址后缀
categories:                                    # 分类：只选 1 个
    - "折腾手记"                               #   例：折腾手记 / 嵌入式 / 网安 / 生活随笔
tags:                                          # 标签：可多个
    - "Twikoo"
    - "Netlify"
    - "Hugo"
    - "Cloudflare"
    - "博客折腾"

# ==================== 封面图（用不到就保持注释）====================
# 方式 A（推荐）：图片和文章放同一文件夹（Page Bundle），文件名 cover.webp
image: "cover.webp"

# ==================== 可选（不需要就整行删掉）====================
toc: true                                      # 显示文章目录：true / false（短文可关）
hidden: false                                  # true=不出现在首页/列表，但链接仍可访问
comments: true                                 # 是否开启评论：true / false
---

前阵子有朋友私信我：“在你博客想留个言，结果跳出来要授权 GitHub 账号，试了两次网络超时就放弃了。”

听到这话我才猛然醒悟。以前我觉得 Giscus / Utterances 这种基于 GitHub Issues 或 Discussions 的评论方案简直是神器——数据不用自己准备数据库，防垃圾评论完全依靠 GitHub 的账号体系，维护成本低到了极点。

但站在普通访客的角度来看，这种体验其实极其糟糕：

**高昂的访问门槛**：非程序员群体或者没有 GitHub 账号的读者，看完文章哪怕有一两句话想交流，看到OAuth登录弹窗的那一刻就会直接选择关闭页面。

**极其不稳定的网络连接**：国内直连访问 GitHub API 常常遇到掉包、连接重置或高延迟，评论框经常出现无限加载的转圈状态。

**缺乏主动通知闭环**：当有其他人在评论区回复了该访客，除非访客主动重新打开这篇文章页面，否则完全无法获得邮件提醒。

个人博客本来就是为了建立交流与连接。如果设置了一道道门槛把读者关在门外，那这片方寸之地未免显得过于冷清。于是我决定彻底抛弃原有的方案，重构评论系统，将评论后端迁移至 **Twikoo** 并托管于 **Netlify** 服务。

本文将完整记录从架构选型、数据库接入、Netlify 部署、SMTP 发信避坑到 Cloudflare 人机防护的完整流程。

---

## 架构对比与技术选型

在正式动手之前，我针对目前主流的自建评论系统与托管平台进行了一番权衡：

| 方案 | 部署平台 | 数据存储 | 优点 | 缺点 |
| :--- | :--- | :--- | :--- | :--- |
| **Giscus** | GitHub Pages | GitHub Discussions | 免维护、零成本 | 须授权登录 GitHub，国内访问不稳，无邮件提醒 |
| **Valine / Waline** | LeanCloud / Vercel | LeanCloud / MongoDB | 功能丰富，支持多后端 | LeanCloud 国际版绑定困难，国内版需备案域名 |
| **Twikoo (Vercel)** | Vercel | MongoDB / CloudBase | 快速部署，部署成本低 | `*.vercel.app` 被部分地区屏蔽，发信长连接易超时 |
| **Twikoo (Netlify)** | Netlify | MongoDB Atlas | 免费额度充足，国内直连稳，Serverless 函数优秀 | 需配置跨域与环境变量 |

综合评估后，**Twikoo + Netlify + MongoDB Atlas** 成为了目前兼顾稳定性、自由度与免费额度的最佳方案。

---

## 搭建 Backend 基础设施

### 准备 MongoDB Atlas 数据库
首先需要一个持久化存储评论数据的数据库。MongoDB Atlas 提供了永久免费的 500MB M0 沙箱集群，对于个人博客的评论数据量来说绰绰有余。

注册并登录 [MongoDB Atlas](https://www.mongodb.com/cloud/atlas)。

创建一个免费集群（Shared Cluster），节点地区推荐选择 **Asia (Singapore 或 Tokyo)**。

在 **Database Access** 页面新建一个数据库用户，设置好账号密码（密码请避免包含特殊符号，或进行 URL 编码）。

在 **Network Access** 页面添加 IP 白名单，直接设置为 `0.0.0.0/0`（允许所有 IP 访问，因为 Netlify Serverless 函数的出口 IP 是动态变化的）。

点击 **Connect** 按钮，选择 *Connect your application*，获取形如以下的连接字符串（`MONGODB_URI`）：
```text
mongodb+sandbox://<username>:<password>@cluster0.xxx.mongodb.net/twikoo?retryWrites=true&w=majority
```

### Fork 并部署到 Netlify
打开 GitHub，Fork [Twikoo 官方 Netlify 部署模版](https://github.com/twikoojs/twikoo)。

登录 [Netlify 控制台](https://app.netlify.com/)，选择 **Add new site** -> **Import an existing project**。

选择刚才 Fork 的 Git 仓库，构建设置保持默认（Build command 留空，Publish directory 填写 `public` 或保持默认）。

进入 **Site configuration** -> **Environment variables**，添加环境变量：

* **`MONGODB_URI`**：填写上一小节保存的 MongoDB 连接字符串。

部署完成后，Netlify 会分配一个默认的二级域名（如 `random-name.netlify.app`）。在 **Domain management** 中绑定你的自定义子域名（例如：`comments.mibase.top`），并在 DNS 服务商处将 CNAME 指向 Netlify。

---

## 安全与跨域限制（CORS）

如果不对评论后端进行跨域限制，任何人都可以拿你的 API 接口配置到他们自己的网站上，甚至恶意消耗你的数据库额度。

进入 Netlify 的 Environment variables 页面，添加跨域白名单配置：

* **`CORS_ALLOW_ORIGIN`**：`https://blog.mibase.top,https://mibase.top,https://200596.xyz`

> **注意**：如果有多个前端访问域名（例如主站、备用域名及本地测试环境），请使用英文逗号 `,` 分隔，严禁包含多余空格。

---

## SMTP 邮件发信与 587 端口踩坑实录

这是整个折腾过程中最耗时、也最容易遇到隐蔽 Bug 的步骤。

### 踩坑分析：为什么 465 端口会连接超时？
最初我在配置 Resend 服务（发件箱 `hi@mibase.top`）时，习惯性地选择了 `465` 端口（SMTPS 协议）。

在本地测试环境中发信正常，但在 Netlify / Vercel 这类 Serverless 无服务器函数运行环境中，每次访客提交评论，前端就会无限转圈，随后控制台抛出 `Connection Timeout` 错误。

**根本原因**：Serverless 函数在执行完主逻辑后会迅速关停上下文，而 465 端口需要建立同步的 SSL/TLS 握手长连接，在云函数的极短生命周期内非常容易触发死锁或超时挂起。

### 正确配置：切换至 587 端口（STARTTLS）
解决该问题的核心在于切换为 **`587` 端口**（基于明文先建立连接，再通过 STARTTLS 指令升级为加密传输）。

请直接在 Twikoo 管理后台的**邮件通知**卡片中按如下格式填写：

* **`SMTP_HOST`**：`smtp.resend.com`
* **`SMTP_PORT`**：`587`
* **`SMTP_USER`**：`resend`
* **`SMTP_PASS`**：`re_xxxxxxxxxxxx` *(替换为你的 Resend API Key)*
* **`SMTP_SECURE`**：`false` *(必须填 false，587 端口会自动完成 TLS 提升)*

配置完成后，点击后台测试发信，日志瞬间返回 `250 OK`，发信延迟降低至 1 秒以内。

---

## 契合 Stack 主题的高亮蓝（`#307af6`）HTML 邮件模板

为了让收到的通知邮件与“昭鸢笺”博客的主体视觉保持一致，我废弃了易因变量缺失而导致排版错乱的模版，改写了一套纯净版 HTML 信笺代码。

### 访客收到回复时的通知模板

* **`MAIL_SUBJECT`**：
  ```text
  你在【昭鸢笺】的纸笺上收到了新回复 ✉️
  ```

* **`MAIL_TEMPLATE`**：
  ```html
  <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 32px; background: #ffffff; border: 1px solid #f3e8ff; border-radius: 12px; color: #2d2d2d;">
    <div style="text-align: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px dashed #f0d5ff;">
      <span style="font-size: 13px; letter-spacing: 2px; color: #b862ff; text-transform: uppercase; font-weight: 600;">blog.mibase.top · 昭鸢笺</span>
      <h2 style="font-size: 19px; font-weight: 600; color: #1f1f1f; margin: 8px 0 0 0;">你的字句，有了新的回音</h2>
    </div>

    <p style="font-size: 14px; color: #555555; margin-bottom: 8px;"><strong>${PARENT_NICK}</strong> 曾留白道：</p>
    <blockquote style="background: #faf5ff; padding: 14px 18px; border-left: 3px solid #d8b4fe; margin: 0 0 18px 0; font-size: 14px; color: #6b7280; border-radius: 0 6px 6px 0;">${PARENT_COMMENT}</blockquote>

    <p style="font-size: 14px; color: #555555; margin-bottom: 8px;">而 <strong>${NICK}</strong> 续写道：</p>
    <blockquote style="background: #fcf4ff; padding: 14px 18px; border-left: 3px solid #c084fc; margin: 0 0 24px 0; font-size: 14px; color: #1f1f1f; border-radius: 0 6px 6px 0;">${COMMENT}</blockquote>

    <div style="text-align: center; margin-top: 28px;">
      <a href="${POST_URL}" style="display: inline-block; background: #c084fc; color: #ffffff; padding: 11px 28px; font-size: 14px; text-decoration: none; border-radius: 6px; font-weight: 600; letter-spacing: 0.5px; box-shadow: 0 3px 10px rgba(192, 132, 252, 0.35);">展开阅览完整对话</a>
    </div>

    <p style="font-size: 12px; color: #9ca3af; text-align: center; margin-top: 36px; padding-top: 16px; border-top: 1px solid #f5f3ff;">此封信件由 <a href="https://blog.mibase.top" style="color: #b862ff; text-decoration: none;">昭鸢笺</a> 自动轻传，愿文字常伴。</p>
  </div>
  ```

### 博主收到新评论时的通知模板

* **`MAIL_SUBJECT_ADMIN`**：
  ```text
  ✨ 昭鸢笺落下一枚新笺：来自新访客的足迹
  ```

* **`MAIL_TEMPLATE_ADMIN`**：
  ```html
  <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 32px; background: #ffffff; border: 1px solid #f3e8ff; border-radius: 12px; color: #2d2d2d;">
    <div style="text-align: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px dashed #f0d5ff;">
      <span style="font-size: 13px; letter-spacing: 2px; color: #b862ff; text-transform: uppercase; font-weight: 600;">blog.mibase.top · 昭鸢笺</span>
      <h2 style="font-size: 19px; font-weight: 600; color: #1f1f1f; margin: 8px 0 0 0;">有访客在云笺上留下了痕迹</h2>
    </div>

    <div style="background: #faf5ff; padding: 16px 20px; border-radius: 8px; margin-bottom: 20px; font-size: 13px; color: #4b5563; border: 1px solid #f3e8ff;">
      <p style="margin: 0 0 8px 0;"><strong>来信者：</strong>${NICK}</p>
      <p style="margin: 0 0 8px 0;"><strong>电子邮箱：</strong>${MAIL}</p>
      <p style="margin: 0;"><strong>归处（IP 属地）：</strong>${IP}</p>
    </div>

    <p style="font-size: 14px; color: #555555; margin-bottom: 8px;"><strong>留白内容：</strong></p>
    <blockquote style="background: #fcf4ff; padding: 14px 18px; border-left: 3px solid #c084fc; margin: 0 0 24px 0; font-size: 14px; color: #1f1f1f; border-radius: 0 6px 6px 0;">${COMMENT}</blockquote>

    <div style="text-align: center; margin-top: 28px;">
      <a href="${POST_URL}" style="display: inline-block; background: #1f1f1f; color: #ffffff; padding: 11px 28px; font-size: 14px; text-decoration: none; border-radius: 6px; font-weight: 500; letter-spacing: 0.5px;">赴约回复</a>
    </div>

    <p style="font-size: 12px; color: #9ca3af; text-align: center; margin-top: 36px; padding-top: 16px; border-top: 1px solid #f5f3ff;">来自 昭鸢笺 (blog.mibase.top) 后台自动化提醒</p>
  </div>
  ```

---

## 无感反垃圾（Cloudflare Turnstile 验证）

降低评论门槛后，最大的隐患是自动化垃圾评论脚本（Spam Bot）。传统九宫格验证码与扭曲文字校验极大伤害用户体验，因此我引入了 **Cloudflare Turnstile**。

### 配置 Turnstile
1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)，进入左侧导航栏的 **Turnstile** 选项卡。
2. 点击 **Add site**：
   * **Site name**：`昭鸢笺`
   * **Domain**：输入主域名 `mibase.top`（自动覆盖子域名 `blog.mibase.top` 和 `comments.mibase.top`）。
   * **Widget Mode**：选择 **Managed**（托管模式）或 **Non-interactive**（无感模式）。
3. 保存后获取 `Site Key` 和 `Secret Key`。

### 注入 Twikoo 参数
将密钥配置到 Netlify 环境变量或 Twikoo 管理后台中：
* **`TURNSTILE_SITE_KEY`**：`0x4AAAAAA...`
* **`TURNSTILE_SECRET_KEY`**：`0x4AAAAAA...`

开启后，正常访客发评论时后端会静默完成人机校验，用户端无任何感知；而恶意攻击脚本则会被 100% 拦截在外。同时可将 **`NOTIFY_SPAM`** 设置为 `false`，彻底避免垃圾评论触发 SMTP 发信，节省 API 额度。

---

## 总结与效果感受

完成迁移与配置后，整体系统的运行效果如下：

**响应速度提升明显**：Netlify Serverless 函数与国内直连节点配合，评论区加载延迟从原先的 3 秒以上缩短至 500ms 左右。

**交流门槛彻底消除**：读者不再需要授权 GitHub 账号，只需填写昵称和邮箱即可畅所欲言。

**闭环体验完善**：依托于 Resend 587 端口和主题色模板，博主与访客之间能建立即时且美观的邮件沟通链条。

对于独立博客而言，基础设施的折腾并非为了炫技，而是为了在赛博世界里搭建一座没有门槛、稳定舒适的方寸小屋。

**如果你也饱受 Giscus 加载卡顿或 Vercel 发信超时的困扰，不妨尝试这套 Netlify + Resend + Turnstile 的架构方案。欢迎在下方全新的评论区留言测试！**