export const storageKey = 'winenv-docs-locale';
export const base = '/winenv/';

export function localeForPath(pathname) {
  return pathname === `${base}zh` || pathname.startsWith(`${base}zh/`) ? 'zh' : 'en';
}

export function preferredEntry(pathname, stored, languages = []) {
  // An explicit locale or deep link always wins over an old browser preference.
  if (pathname !== base && pathname !== base.slice(0, -1)) return null;
  const preference = stored === 'en' || stored === 'zh'
    ? stored
    : (languages[0] || 'en').toLowerCase().startsWith('zh') ? 'zh' : 'en';
  return preference === 'zh' ? `${base}zh/` : null;
}

if (typeof document !== 'undefined') {
  let stored;
  try { stored = localStorage.getItem(storageKey); } catch { /* Storage is optional. */ }
  const destination = preferredEntry(location.pathname, stored, navigator.languages || [navigator.language]);
  if (destination) location.replace(destination + location.search + location.hash);

  document.addEventListener('change', (event) => {
    const select = event.target;
    if (!(select instanceof HTMLSelectElement) || !select.closest('starlight-lang-select')) return;
    const target = new URL(select.value, location.href);
    if (target.origin !== location.origin || !target.pathname.startsWith(base)) return;
    try { localStorage.setItem(storageKey, localeForPath(target.pathname)); } catch { /* Storage is optional. */ }
    target.search = location.search;
    target.hash = location.hash;
    event.stopImmediatePropagation();
    location.assign(target.href);
  }, true);
}
