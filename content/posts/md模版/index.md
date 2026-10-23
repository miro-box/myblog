---

title: "Hugo archetypes 模板配置教程"
date: 2026-10-23T21:31:35+08:00
draft: false
description: "配置 Hugo 原型模板，新建文章自动生成 Frontmatter，不用每次复制头部配置，减少 YAML 报错。"
slug: "hugo-archetypes-setup"
categories:
  - "折腾手记"
tags:
  - "Hugo"
  - "博客"
toc: true
hidden: false
comments: true
image: "cover.jpg"

---

每次写 Hugo 博客最折磨人的不是写正文，而是每次新建文章都要去翻旧文章复制 Frontmatter。 标题、发布时间、简介、分类、标签、封面、目录开关…… 配置项一大堆，稍微缩进错、冒号漏写，一执行 `hugo server` 直接红字报错，调试半天。

其实 Hugo 原生就提供了 `archetypes` 原型模板功能，只需要配置一次，后续新建文章自动生成带注释、格式正确的完整模板，彻底告别复制粘贴和 YAML 语法翻车。

## 一、什么是 archetypes

`archetypes` 相当于文章的模板母版。当你执行 `hugo new` 创建文章时，Hugo 会读取 archetypes 下对应的 md 文件，自动填充内置变量（时间、文件名等）生成新文章。 一般博客根目录自带 `archetypes/` 文件夹，如果没有，直接手动新建即可。

我们主要使用 `archetypes/post.md`，专门用来生成普通博文模板。

## 二、编写模板文件

在 `archetypes/` 目录新建或者编辑 `post.md`，直接复制下面这段内容保存。

> 已经修正 YAML 数组语法，带中文注释，自带文章写作骨架，开箱即用。

~~~yaml
---
# 必填配置
title: "{{ replace .Name "-" " " | title }}"
date: {{ .Date }}
draft: true

# 推荐补充
description: ""
slug: ""
categories:
  - "折腾手记"
tags:
  - "Hugo"

# 封面图配置，二选一，不需要就注释掉
# image: "cover.jpg"       # Page Bundle 模式，图片和文章放在同一个目录（推荐）
# image: "/images/cover.jpg" # 图片存放在 static/images 下

# 可选功能开关
toc: true
# math: true
# license: ""
# lastmod:
# weight: 1
hidden: false
comments: true
---

> 💡 导读：在这里写简短摘要，会用于首页卡片预览、RSS 摘要

## 一、前言
这里写背景、需求、写这篇文章的缘由。

## 二、正文
### 1. 小标题
正文内容写在这里。

```c
// 代码示例
#include <stdio.h>

int main() {
    printf("Hello Hugo\n");
    return 0;
}
~~~

> ⚠️ 注意：记录踩坑点、重要提醒、限制条件

## 三、总结

梳理要点、记录后续计划、待办事项。

~~~yaml
### 配置项简单说明
- `draft: true`：草稿模式，不会被发布；写完定稿改为 `false`
- `categories`：分类，建议只保留一项，按需修改
- `tags`：标签，可以多行添加多个
- `toc: true`：自动生成文章目录，短文可以改成 false
- `hidden: false`：设为 true 时，文章不会出现在列表页，但直接访问链接仍然可以打开

## 三、模板使用方法
推荐使用 **Page Bundle** 文件夹模式，封面图、截图都可以和文章放在同一个目录，管理更清爽。

在项目终端执行命令：
```bash
hugo new post/文章英文标识/index.md
~~~

执行完成后，Hugo 会自动在 `content/post/` 下创建文件夹，并生成 `index.md`。 打开生成的文件，Frontmatter、文章章节骨架都已经准备好了，只需要修改标题、填充内容。

内容全部写完检查无误，将 `draft: true` 修改为 `draft: false`，就可以正常构建、部署。

## 四、小提示

1. 如果想要不同类型文章用不同模板，可以在 archetypes 新建别的文件，比如 `note.md`，用 `hugo new note/xxx/index.md` 调用
2. 模板修改后，**只对之后新建的文章生效**，已经存在的文章不会自动更新
3. 注释可以根据自己习惯删减，不用的配置项直接删掉，模板会更干净

以后写博客，不用再到处复制头部配置，专注写内容就好，再也不会因为 YAML 格式问题编译报错。
