<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:atom="http://www.w3.org/2005/Atom">
  <xsl:output method="html" encoding="utf-8" indent="yes" doctype-system="about:legacy-compat"/>

  <xsl:template match="/rss/channel">
    <html lang="zh-CN">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title><xsl:value-of select="title"/> · 订阅</title>
        <link rel="stylesheet" href="/fonts/wenkai-sub.css"/>
        <link rel="icon" href="/favicon.ico"/>
        <style>
          :root {
            --bg: #eef3f5; --card: #ffffff; --text: #33414a; --muted: #7b8a93;
            --teal: #2289a0; --teal-soft: rgba(34, 137, 160, .10); --gold: #c9a45c;
            --line: rgba(34, 137, 160, .18); --shadow: 0 6px 22px rgba(34, 137, 160, .12);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #1c2128; --card: #262b32; --text: #c9d1d9; --muted: #8b98a3;
              --teal: #5cbad0; --teal-soft: rgba(92, 186, 208, .12);
              --line: rgba(92, 186, 208, .22); --shadow: 0 6px 22px rgba(0, 0, 0, .35);
            }
          }
          * { box-sizing: border-box; }
          body {
            margin: 0; padding: 32px 16px 56px; background: var(--bg); color: var(--text);
            font-family: 'LXGW WenKai Sub', 'LXGW WenKai', -apple-system, 'PingFang SC', 'Microsoft YaHei', sans-serif;
            line-height: 1.7;
          }
          .wrap { max-width: 760px; margin: 0 auto; }
          header.top {
            background: var(--card); border-radius: 14px; box-shadow: var(--shadow);
            border-top: 3px solid var(--gold); padding: 26px 28px 22px;
          }
          h1 { margin: 0 0 6px; font-size: 26px; letter-spacing: 3px; color: var(--teal); }
          h1::before {
            content: ""; display: inline-block; width: 9px; height: 9px; margin-right: 12px;
            background: var(--gold); transform: rotate(45deg) translateY(-3px);
          }
          .sub { margin: 0; color: var(--muted); font-size: 14px; }
          .tip {
            margin-top: 18px; padding: 12px 16px; border-radius: 10px; font-size: 14px;
            background: var(--teal-soft); border-left: 3px solid var(--gold);
          }
          .tip code {
            display: inline-block; margin-top: 6px; padding: 2px 8px; border-radius: 6px;
            background: var(--card); color: var(--teal); word-break: break-all; font-size: 13px;
          }
          .tip a { color: var(--teal); text-decoration: none; border-bottom: 1px solid var(--gold); }
          h2 {
            margin: 30px 4px 12px; font-size: 16px; letter-spacing: 3px; color: var(--teal); font-weight: 600;
          }
          ul { list-style: none; margin: 0; padding: 0; }
          li { margin-bottom: 12px; }
          li a.item {
            display: block; padding: 16px 20px; border-radius: 12px; text-decoration: none;
            background: var(--card); box-shadow: var(--shadow); color: inherit;
            border-left: 3px solid transparent; transition: transform .25s, border-color .25s;
          }
          li a.item:hover { transform: translateX(4px); border-left-color: var(--gold); }
          .t { display: block; font-size: 17px; color: var(--teal); font-weight: 700; }
          .meta { display: block; margin-top: 4px; font-size: 13px; color: var(--muted); }
          .cat {
            display: inline-block; margin-left: 8px; padding: 0 9px; border-radius: 999px;
            border: 1px solid var(--line); color: var(--teal); font-size: 12px;
          }
          footer { margin-top: 28px; text-align: center; font-size: 13px; color: var(--muted); }
          footer a { color: var(--teal); text-decoration: none; }
        </style>
      </head>
      <body>
        <div class="wrap">
          <header class="top">
            <h1><xsl:value-of select="title"/></h1>
            <p class="sub">订阅源 · 这是给阅读器用的 RSS 地址，在浏览器里也能直接看最近的文章</p>
            <div class="tip">
              把下面这个地址添加到你的 RSS 阅读器（Feedly、Inoreader、Reeder 等）就能订阅：<br/>
              <code><xsl:value-of select="atom:link/@href"/></code>
            </div>
          </header>

          <h2>最近更新</h2>
          <ul>
            <xsl:for-each select="item">
              <li>
                <a class="item">
                  <xsl:attribute name="href"><xsl:value-of select="link"/></xsl:attribute>
                  <span class="t"><xsl:value-of select="title"/></span>
                  <span class="meta">
                    <xsl:variable name="mon" select="(string-length(substring-before('JanFebMarAprMayJunJulAugSepOctNovDec', substring(pubDate, 9, 3))) div 3) + 1"/>
                    <xsl:value-of select="concat(substring(pubDate, 13, 4), '-', format-number($mon, '00'), '-', substring(pubDate, 6, 2))"/>
                    <xsl:for-each select="category">
                      <span class="cat"><xsl:value-of select="."/></span>
                    </xsl:for-each>
                  </span>
                </a>
              </li>
            </xsl:for-each>
          </ul>

          <footer>
            <a href="/">← 回到 <xsl:value-of select="title"/></a>
          </footer>
        </div>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
