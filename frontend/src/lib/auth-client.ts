import { API_URL } from '$lib/config';
import { writable } from 'svelte/store';

export interface User {
	id: number;
	username: string;
	email: string;
	avatar: string | null;
	slackId: string | null;
	scraps: number;
	role: string;
	tutorialCompleted: boolean;
}

export const userScrapsStore = writable<number>(0);

let cachedUser: User | null | undefined = undefined;
let fetchPromise: Promise<User | null> | null = null;

export function login() {
	let ref: string | null = null;
	let source: string | null = null;
	try {
		const params = new URLSearchParams(window.location.search);
		ref = params.get('r') || localStorage.getItem('referralCode');
		source = params.get('source') || localStorage.getItem('signupSource');
	} catch {
		ref = null;
		source = null;
	}
	const qs = new URLSearchParams();
	if (ref) qs.set('r', ref);
	if (source) qs.set('s', source);
	const query = qs.toString();
	window.location.href = `${API_URL}/auth/login${query ? `?${query}` : ''}`;
}

// Call on any public page load so a ?r= code survives until the user logs in.
export function captureReferralCode() {
	try {
		const params = new URLSearchParams(window.location.search);
		const code = params.get('r');
		if (code) localStorage.setItem('referralCode', code);
		const source = params.get('source');
		if (source && !localStorage.getItem('signupSource')) localStorage.setItem('signupSource', source);
	} catch {
		/* ignore */
	}
}

export async function logout() {
	cachedUser = undefined;
	fetchPromise = null;
	await fetch(`${API_URL}/auth/logout`, {
		method: 'POST',
		credentials: 'include'
	});
	window.location.href = '/';
}

export async function getUser(forceRefresh = false): Promise<User | null> {
	if (!forceRefresh && cachedUser !== undefined) return cachedUser;

	if (fetchPromise) return fetchPromise;

	fetchPromise = (async (): Promise<User | null> => {
		try {
			const response = await fetch(`${API_URL}/auth/me`, {
				credentials: 'include'
			});
			if (!response.ok) {
				cachedUser = null;
				return null;
			}
			const data = await response.json();
			if (data.banned) {
				window.location.href = 'https://fraud.hackclub.com';
				cachedUser = null;
				return null;
			}
			cachedUser = (data.user as User) || null;
			if (cachedUser) {
				userScrapsStore.set(cachedUser.scraps);
			}
			return cachedUser;
		} catch {
			cachedUser = null;
			return null;
		} finally {
			fetchPromise = null;
		}
	})();

	return fetchPromise;
}

export async function refreshUserScraps(): Promise<number | null> {
	const user = await getUser(true);
	return user?.scraps ?? null;
}
