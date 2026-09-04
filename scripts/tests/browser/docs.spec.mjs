import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('English homepage, metadata, assets, and screenshot', async ({ page }, testInfo) => {
  const response = await page.goto('/winenv/');
  expect(response.status()).toBe(200);
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.locator('h1')).toHaveText('Make Windows software manageable');
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://yangyus8.top/winenv/');
  const favicon = await page.locator('link[rel~="icon"]').getAttribute('href');
  expect((await page.request.get(favicon)).status()).toBe(200);
  await expect(page.getByAltText('Winenv').first()).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('homepage-en.png'), fullPage: true });
});

test('Chinese browser gets the Chinese entry and can persist English manually', async ({ browser }) => {
  const context = await browser.newContext({ locale: 'zh-CN' });
  const page = await context.newPage();
  await page.goto('http://127.0.0.1:4321/winenv/');
  await expect(page).toHaveURL(/\/winenv\/zh\/$/);
  await expect(page.locator('html')).toHaveAttribute('lang', 'zh-CN');
  await page.goto('http://127.0.0.1:4321/winenv/zh/guide/profiles/?source=test#_top');
  await page.getByRole('banner').locator('starlight-lang-select select').selectOption('/winenv/guide/profiles/');
  await expect(page).toHaveURL(/\/winenv\/guide\/profiles\/\?source=test#_top$/);
  expect(await page.evaluate(() => localStorage.getItem('winenv-docs-locale'))).toBe('en');
  await page.goto('http://127.0.0.1:4321/winenv/');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await context.close();
});

test('stored preference never overrides an explicit deep link', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('winenv-docs-locale', 'zh'));
  await page.goto('/winenv/reference/commands/#software');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.locator('#software')).toBeVisible();
  await page.goto('/winenv/');
  await expect(page).toHaveURL(/\/winenv\/zh\/$/);
});

test('blocked storage still allows explicit locale navigation', async ({ page }) => {
  await page.addInitScript(() => {
    Storage.prototype.getItem = () => { throw new Error('Storage blocked'); };
    Storage.prototype.setItem = () => { throw new Error('Storage blocked'); };
  });
  await page.goto('/winenv/zh/guide/profiles/');
  await page.getByRole('banner').locator('starlight-lang-select select').selectOption('/winenv/guide/profiles/');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
});

for (const [locale, query] of [['', 'profiles'], ['zh/', '软件']]) {
  test(`production search stays in ${locale || 'English'}`, async ({ page }) => {
    await page.goto(`/winenv/${locale}`);
    await page.locator('site-search button[data-open-modal]').click();
    await page.locator('.pagefind-ui__search-input').fill(query);
    const first = page.locator('.pagefind-ui__result-link').first();
    await expect(first).toBeVisible();
    const href = await first.getAttribute('href');
    expect(href).toContain(`/winenv/${locale}`);
    if (!locale) expect(href).not.toContain('/winenv/zh/');
    await first.click();
    await expect(page.locator('h1')).toBeVisible();
  });
}

test('mobile navigation works without horizontal overflow', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/winenv/guide/getting-started/');
  await page.getByRole('button', { name: 'Menu', exact: true }).click();
  await page.locator('#starlight__sidebar a[href="/winenv/reference/commands/"]').click();
  await expect(page.locator('h1')).toHaveText('Command reference');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('mobile-reference.png'), fullPage: true });
});

for (const locale of ['', 'zh/']) {
  for (const theme of ['light', 'dark']) {
    test(`accessibility smoke ${locale || 'en'} ${theme}`, async ({ page }, testInfo) => {
      await page.addInitScript((value) => localStorage.setItem('starlight-theme', value), theme);
      await page.goto(`/winenv/${locale}guide/getting-started/`);
      // Expressive Code adds keyboard focus after its debounced ResizeObserver.
      await expect.poll(() => page.locator('.expressive-code pre').evaluateAll((blocks) =>
        blocks.every((block) => block.scrollWidth <= block.clientWidth || block.tabIndex === 0)
      )).toBe(true);
      const result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
      expect(result.violations).toEqual([]);
      await page.screenshot({ path: testInfo.outputPath(`${locale ? 'zh' : 'en'}-${theme}.png`), fullPage: true });
      await page.goto(`/winenv/${locale}`);
      const homepage = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
      expect(homepage.violations).toEqual([]);
    });
  }
}

test('error page has working recovery links', async ({ page }) => {
  await page.goto('/winenv/404/');
  await expect(page.locator('h1')).toHaveText('Page not found');
  await expect(page.getByRole('link', { name: 'documentation homepage', exact: true })).toHaveAttribute('href', '/winenv/');
});
