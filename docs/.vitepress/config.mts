import { defineConfig, type DefaultTheme } from "vitepress";

const repository = "https://github.com/YangYuS8/winenv";
const site = "https://yangyus8.top/winenv";

const commonTheme: DefaultTheme.Config = {
  logo: "/logo.svg",
  siteTitle: "Winenv",
  socialLinks: [{ icon: "github", link: repository }],
  search: { provider: "local" },
};

const englishTheme: DefaultTheme.Config = {
  ...commonTheme,
  nav: [
    { text: "Guides", link: "/guide/getting-started", activeMatch: "^/guide/" },
    { text: "Reference", link: "/reference/commands", activeMatch: "^/reference/" },
    { text: "Community", link: "/community/contributing", activeMatch: "^/community/" },
    { text: "Changelog", link: "/changelog" },
  ],
  sidebar: {
    "/guide/": [{
      text: "Guides",
      items: [
        { text: "Getting started", link: "/guide/getting-started" },
        { text: "Finding and managing software", link: "/guide/packages" },
        { text: "Adopting an existing PC", link: "/guide/existing-windows" },
        { text: "Composing profiles", link: "/guide/profiles" },
        { text: "Software outside the catalogs", link: "/guide/manual-installers" },
      ],
    }],
    "/reference/": [{
      text: "Reference",
      items: [
        { text: "Command reference", link: "/reference/commands" },
        { text: "State, storage, and security", link: "/reference/state-and-security" },
        { text: "Documentation and releases", link: "/reference/automation" },
      ],
    }],
    "/community/": [{
      text: "Community",
      items: [
        { text: "Contributing", link: "/community/contributing" },
        { text: "Translation guide", link: "/community/i18n" },
        { text: "Governance", link: "/community/governance" },
      ],
    }],
  },
  outline: { label: "On this page", level: [2, 3] },
  docFooter: { prev: "Previous page", next: "Next page" },
  lastUpdated: { text: "Last updated" },
  editLink: {
    pattern: `${repository}/edit/main/docs/:path`,
    text: "Edit this page on GitHub",
  },
  footer: { message: "Released under the MIT License", copyright: "Winenv" },
};

const chineseTheme: DefaultTheme.Config = {
  ...commonTheme,
  nav: [
    { text: "指南", link: "/zh/guide/getting-started", activeMatch: "^/zh/guide/" },
    { text: "参考", link: "/zh/reference/commands", activeMatch: "^/zh/reference/" },
    { text: "社区", link: "/zh/community/contributing", activeMatch: "^/zh/community/" },
    { text: "更新日志", link: "/zh/changelog" },
  ],
  sidebar: {
    "/zh/guide/": [{
      text: "使用指南",
      items: [
        { text: "开始使用", link: "/zh/guide/getting-started" },
        { text: "查找与管理软件", link: "/zh/guide/packages" },
        { text: "接入现有 Windows", link: "/zh/guide/existing-windows" },
        { text: "组合 Profile", link: "/zh/guide/profiles" },
        { text: "目录外的软件", link: "/zh/guide/manual-installers" },
      ],
    }],
    "/zh/reference/": [{
      text: "参考",
      items: [
        { text: "命令速查", link: "/zh/reference/commands" },
        { text: "状态、存储与安全", link: "/zh/reference/state-and-security" },
        { text: "文档与发布自动化", link: "/zh/reference/automation" },
      ],
    }],
    "/zh/community/": [{
      text: "社区",
      items: [
        { text: "参与贡献", link: "/zh/community/contributing" },
        { text: "翻译指南", link: "/zh/community/i18n" },
        { text: "项目治理", link: "/zh/community/governance" },
      ],
    }],
  },
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
    pattern: `${repository}/edit/main/docs/:path`,
    text: "在 GitHub 上编辑此页",
  },
  returnToTopLabel: "返回顶部",
  sidebarMenuLabel: "菜单",
  darkModeSwitchLabel: "主题",
  lightModeSwitchTitle: "切换为浅色主题",
  darkModeSwitchTitle: "切换为深色主题",
  langMenuLabel: "切换语言",
  skipToContentLabel: "跳到正文",
  footer: { message: "以 MIT License 发布", copyright: "Winenv" },
};

function pageUrl(path: string) {
  const isIndex = /(^|\/)index\.md$/.test(path);
  const clean = path
    .replace(/index\.md$/, "")
    .replace(/\.md$/, "")
    .replace(/^\/+|\/+$/g, "");
  return clean ? `${site}/${clean}${isIndex ? "/" : ""}` : `${site}/`;
}

export default defineConfig({
  base: "/winenv/",
  cleanUrls: true,
  lastUpdated: true,
  sitemap: { hostname: `${site}/` },
  head: [
    ["meta", { name: "theme-color", content: "#356df3" }],
    ["meta", { property: "og:type", content: "website" }],
  ],
  locales: {
    root: {
      label: "English",
      lang: "en-US",
      title: "Winenv",
      description: "Fast, composable Windows 11 software and development environment management",
      head: [
        ["meta", { property: "og:locale", content: "en_US" }],
        ["meta", { property: "og:title", content: "Winenv documentation" }],
        ["meta", { property: "og:description", content: "Fast, composable Windows 11 software and development environment management" }],
      ],
      themeConfig: englishTheme,
    },
    zh: {
      label: "简体中文",
      lang: "zh-CN",
      link: "/zh/",
      title: "Winenv",
      description: "高效、可组合的 Windows 11 软件与开发环境管理",
      head: [
        ["meta", { property: "og:locale", content: "zh_CN" }],
        ["meta", { property: "og:title", content: "Winenv 文档" }],
        ["meta", { property: "og:description", content: "高效、可组合的 Windows 11 软件与开发环境管理" }],
      ],
      themeConfig: chineseTheme,
    },
  },
  transformHead({ pageData }) {
    const current = pageData.relativePath;
    const english = current.startsWith("zh/") ? current.slice(3) : current;
    const chinese = `zh/${english}`;
    return [
      ["link", { rel: "canonical", href: pageUrl(current) }],
      ["link", { rel: "alternate", hreflang: "en", href: pageUrl(english) }],
      ["link", { rel: "alternate", hreflang: "zh-CN", href: pageUrl(chinese) }],
      ["link", { rel: "alternate", hreflang: "x-default", href: pageUrl(english) }],
    ];
  },
});
