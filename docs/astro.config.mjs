import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://yangyus8.top',
  base: '/winenv',
  trailingSlash: 'always',
  output: 'static',
  integrations: [starlight({
    title: 'Winenv',
    description: 'Fast, composable Windows 11 software and development environment management',
    logo: { src: './public/logo.png', alt: 'Winenv' },
    favicon: '/favicon.png',
    defaultLocale: 'root',
    locales: {
      root: { label: 'English', lang: 'en' },
      zh: { label: '简体中文', lang: 'zh-CN' },
    },
    social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/YangYuS8/winenv' }],
    editLink: { baseUrl: 'https://github.com/YangYuS8/winenv/edit/main/docs/src/content/docs/' },
    lastUpdated: true,
    disable404Route: true,
    customCss: ['./src/styles/custom.css'],
    head: [
      { tag: 'meta', attrs: { name: 'theme-color', content: '#356df3' } },
      { tag: 'meta', attrs: { property: 'og:image', content: 'https://yangyus8.top/winenv/logo.png' } },
      { tag: 'script', attrs: { type: 'module', src: '/winenv/locale.js' } },
    ],
    sidebar: [
      { label: 'Guides', translations: { 'zh-CN': '操作指南' }, items: [{ autogenerate: { directory: 'guide' } }] },
      { label: 'Concepts', translations: { 'zh-CN': '概念解释' }, items: [{ autogenerate: { directory: 'concepts' } }] },
      { label: 'Reference', translations: { 'zh-CN': '参考资料' }, items: [{ autogenerate: { directory: 'reference' } }] },
      { label: 'Community', translations: { 'zh-CN': '社区' }, items: [{ autogenerate: { directory: 'community' } }] },
      { slug: 'changelog' },
    ],
  })],
});
