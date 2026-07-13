import { writable, derived } from 'svelte/store';
import en from './en';
import es from './es';
import { API_URL } from '$lib/config';

export type Locale = 'en' | 'es';
type DeepStringify<T> = { [K in keyof T]: T[K] extends string ? string : DeepStringify<T[K]> };
export type Translations = DeepStringify<typeof en>;

const translations: Record<Locale, Translations> = { en, es };

const SUPPORTED_LOCALES: Locale[] = ['en', 'es'];

function matchLocale(lang: string): Locale | null {
	const lower = lang.toLowerCase();
	// Exact match
	if (SUPPORTED_LOCALES.includes(lower as Locale)) return lower as Locale;
	// Match language prefix (e.g. es-MX, es-AR, es-ES -> es)
	const prefix = lower.split('-')[0];
	if (SUPPORTED_LOCALES.includes(prefix as Locale)) return prefix as Locale;
	return null;
}

function getBrowserLocale(): Locale | null {
	if (typeof window === 'undefined') return null;
	// Check navigator.languages first (ordered by preference)
	if (navigator.languages?.length) {
		for (const lang of navigator.languages) {
			const matched = matchLocale(lang);
			if (matched) return matched;
		}
	}
	// Fallback to navigator.language
	if (navigator.language) {
		return matchLocale(navigator.language);
	}
	return null;
}

function getInitialLocale(): Locale {
	if (typeof window === 'undefined') return 'en';
	const stored = localStorage.getItem('locale');
	if (stored === 'en' || stored === 'es') return stored;
	return getBrowserLocale() || 'en';
}

function createLocaleStore() {
	const { subscribe, set, update } = writable<Locale>(getInitialLocale());

	return {
		subscribe,
		set: (value: Locale) => {
			if (typeof window !== 'undefined') {
				localStorage.setItem('locale', value);
				// Sync language preference to backend
				fetch(`${API_URL}/user/language`, {
					method: 'PUT',
					headers: { 'Content-Type': 'application/json' },
					credentials: 'include',
					body: JSON.stringify({ language: value })
				}).catch(() => {});
			}
			set(value);
		},
		update
	};
}

export const locale = createLocaleStore();

export const t = derived(locale, ($locale) => translations[$locale]);

export function setLocale(lang: Locale) {
	locale.set(lang);
}
