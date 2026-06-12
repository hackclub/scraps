import { API_URL } from '$lib/config';
import { writable } from 'svelte/store';

export interface User {
	id: number;
	username: string;
	email: string;
	avatar: string | null;
	slackId: string | null;
	scraps: number;
	scrapsPending: number;
	nextPayoutDate: string;
	role: string;
	tutorialCompleted: boolean;
}

export const userScrapsStore = writable<number>(0);
export const userScrapsPendingStore = writable<number>(0);
export const nextPayoutDateStore = writable<string>('');

let cachedUser: User | null | undefined = undefined;
let fetchPromise: Promise<User | null> | null = null;

export function login() {
	window.location.href = `${API_URL}/auth/login`;
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
				userScrapsPendingStore.set(cachedUser.scrapsPending ?? 0);
				nextPayoutDateStore.set(cachedUser.nextPayoutDate ?? '');
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
