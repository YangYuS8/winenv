<script setup lang="ts">
import DefaultTheme from "vitepress/theme";
import { onMounted, onUnmounted } from "vue";

const { Layout } = DefaultTheme;
const storageKey = "winenv-docs-locale";
const base = "/winenv/";

function readPreference(): "en" | "zh" | null {
  try {
    const value = window.localStorage.getItem(storageKey);
    return value === "en" || value === "zh" ? value : null;
  } catch {
    return null;
  }
}

function savePreference(locale: "en" | "zh") {
  try {
    window.localStorage.setItem(storageKey, locale);
  } catch {
    // The site still works when storage is blocked.
  }
}

function localeFromPath(pathname: string): "en" | "zh" {
  return pathname.startsWith(`${base}zh/`) ? "zh" : "en";
}

function pathForLocale(locale: "en" | "zh") {
  const relative = window.location.pathname.startsWith(base)
    ? window.location.pathname.slice(base.length)
    : "";
  const withoutLocale = relative.startsWith("zh/") ? relative.slice(3) : relative;
  const localized = locale === "zh" ? `zh/${withoutLocale}` : withoutLocale;
  return `${base}${localized}${window.location.search}${window.location.hash}`;
}

function switchTo(locale: "en" | "zh") {
  savePreference(locale);
  if (locale !== localeFromPath(window.location.pathname)) {
    window.location.replace(pathForLocale(locale));
  }
}

function rememberLanguageMenu(event: MouseEvent) {
  const target = event.target;
  if (!(target instanceof Element)) return;
  const link = target.closest<HTMLAnchorElement>("a");
  if (!link || !link.closest(".VPNavBarTranslations, .VPNavScreenTranslations, .group.translations")) return;
  const path = new URL(link.href, window.location.href).pathname;
  savePreference(localeFromPath(path));
}

onMounted(() => {
  document.addEventListener("click", rememberLanguageMenu, true);

  const stored = readPreference();
  if (stored) {
    switchTo(stored);
    return;
  }

  // Auto-select only at the canonical entry page. Explicit deep links and
  // direct /zh/ visits remain untouched until the visitor uses the menu.
  if (window.location.pathname === base) {
    const browserLanguage = (navigator.languages?.[0] || navigator.language || "en").toLowerCase();
    switchTo(browserLanguage.startsWith("zh") ? "zh" : "en");
  }
});

onUnmounted(() => {
  document.removeEventListener("click", rememberLanguageMenu, true);
});
</script>

<template>
  <Layout />
</template>
