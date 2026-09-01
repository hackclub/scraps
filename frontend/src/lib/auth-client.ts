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
	try {
		ref =
			new URLSearchParams(window.location.search).get('r') || localStorage.getItem('referralCode');
	} catch {
		ref = null;
	}
	const qs = ref ? `?r=${encodeURIComponent(ref)}` : '';
	window.location.href = `${API_URL}/auth/login${qs}`;
}

// Call on any public page load so a ?r= code survives until the user logs in.
export function captureReferralCode() {
	try {
		const code = new URLSearchParams(window.location.search).get('r');
		if (code) localStorage.setItem('referralCode', code);
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
				window.location.href = 'https://fraud.land';
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
