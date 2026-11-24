export type Theme = 'light' | 'dark';

export function getTheme(): Theme {
	if (typeof document === 'undefined') return 'light';
	return document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
}

export function setTheme(theme: Theme) {
	document.documentElement.dataset.theme = theme;
	try {
		localStorage.setItem('theme', theme);
	} catch {
		return;
	}
}
