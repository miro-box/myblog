---
title: 本站技术栈
date: 2026-11-07
url: /uses/
comments: false
copyright: false
---

## 生成与托管

- **生成器**：[Hugo](https://gohugo.io/)（extended 版），写好 Markdown，推送即发布
- **主题**：以 hugo-theme-reimu 为底子，配色、侧边栏、卡片、深色模式这些样式都是我东拼西凑自己改出来的，主色青蓝，点缀金色
- **托管与解析**：Cloudflare Pages 和 Cloudflare DNS，推送到 GitHub 后自动构建上线
- **代码仓库**：GitHub

## 功能

- **搜索**：Algolia
- **评论**：Twikoo
- **字体**：霞鹜文楷，用 fonttools 裁剪成只含站内用字的一个文件，自托管
- **图片画廊**：自己写的脚本批量添加图片，清单文件压缩后只有一百多 KB
- **RSS**：自带页面样式，用浏览器打开也是好看的

## 自己写的小工具

- 一组 Windows 批处理，放在 `tools` 文件夹里，用菜单选择：新建文章、本地预览、加图、图片转 WebP、同步番剧、更新搜索索引、备份图床、发布等
- 正文字体生成脚本：扫描全站文字，自动裁剪字体并更新样式
- 发布前检查：推送之前先更新字体、试构建一遍，再列出待发布的改动，可选再检查一次友链

## 日常环境

- 系统：Windows，终端用 PowerShell
- 写文章：Markdown，本地用 `hugo server` 预览，满意再推送
