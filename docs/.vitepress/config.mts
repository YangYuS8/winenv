import { defineConfig } from "vitepress";

export default defineConfig({
  lang: "zh-CN",
  title: "Winenv",
  description: "高效、可组合的 Windows 11 软件与开发环境管理",
  base: "/winenv/",
  cleanUrls: true,
  lastUpdated: true,
  sitemap: { hostname: "https://yangyus8.top/winenv/" },
  head: [
    ["meta", { name: "theme-color", content: "#356df3" }],
    ["meta", { property: "og:locale", content: "zh_CN" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:title", content: "Winenv 文档" }],
    ["meta", { property: "og:description", content: "高效、可组合的 Windows 11 软件与开发环境管理" }],
  ],
  themeConfig: {
    logo: "/logo.svg",
    siteTitle: "Winenv",
    nav: [
      { text: "指南", link: "/guide/getting-started", activeMatch: "/guide/" },
      { text: "命令", link: "/reference/commands", activeMatch: "/reference/" },
      { text: "更新日志", link: "/changelog" },
    ],
    sidebar: {
      "/guide/": [{
        text: "使用指南",
        items: [
          { text: "开始使用", link: "/guide/getting-started" },
          { text: "查找与管理软件", link: "/guide/packages" },
          { text: "接入现有 Windows", link: "/guide/existing-windows" },
          { text: "组合 Profile", link: "/guide/profiles" },
          { text: "目录外的软件", link: "/guide/manual-installers" },
        ],
      }],
      "/reference/": [{
        text: "参考",
        items: [
          { text: "命令速查", link: "/reference/commands" },
          { text: "状态、存储与安全", link: "/reference/state-and-security" },
          { text: "文档与发布自动化", link: "/reference/automation" },
        ],
      }],
    },
    socialLinks: [{ icon: "github", link: "https://github.com/YangYuS8/winenv" }],
    search: {
      provider: "local",
      options: {
        translations: {
          button: { buttonText: "搜索文档", buttonAriaLabel: "搜索文档" },
          modal: {
            noResultsText: "没有找到相关内容",
            resetButtonTitle: "清除查询",
            footer: { selectText: "选择", navigateText: "切换", closeText: "关闭" },
          },
        },
      },
    },
    outline: { label: "本页内容", level: [2, 3] },
    docFooter: { prev: "上一篇", next: "下一篇" },
    lastUpdated: { text: "最后更新于" },
    editLink: {
      pattern: "https://github.com/YangYuS8/winenv/edit/main/docs/:path",
      text: "在 GitHub 上编辑此页",
    },
    returnToTopLabel: "返回顶部",
    sidebarMenuLabel: "菜单",
    darkModeSwitchLabel: "主题",
    lightModeSwitchTitle: "切换为浅色主题",
    darkModeSwitchTitle: "切换为深色主题",
    footer: { message: "以 MIT License 发布", copyright: "Winenv" },
  },
});
