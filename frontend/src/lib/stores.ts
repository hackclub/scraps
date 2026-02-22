import { writable, get } from 'svelte/store';
import { browser } from '$app/environment';
import { API_URL } from '$lib/config';
import type { User } from '$lib/auth-client';

export interface Project {
	id: number;
	userId: string;
	name: string;
	description: string;
	image: string | null;
	githubUrl: string | null;
	hackatimeProject: string | null;
	hours: number;
	hoursOverride: number | null;
	tier: number;
	status: string;
}

export interface ShopItem {
	id: number;
	name: string;
	description: string;
	image: string;
	price: number;
	category: string;
	count: number;
	rollCount: number;
	heartCount: number;
	userHearted: boolean;
	baseProbability: number;
	adjustedBaseProbability: number;
	baseUpgradeCost: number;
	costMultiplier: number;
	boostAmount: number;
	rollCostOverride: number | null;
	perRollMultiplier: number;
	userBoostPercent: number;
	upgradeCount: number;
	effectiveProbability: number;
	nextUpgradeCost: number | null;
	displayRollCost?: number;
}

export interface LeaderboardEntry {
	rank: number;
	id: number;
	username: string;
	avatar: string;
	hours: number;
	scraps: number;
	scrapsEarned: number;
	projectCount: number;
}

export interface ProbabilityLeader {
	itemId: number;
	itemName: string;
	itemImage: string;
	baseProbability: number;
	topUser: {
		id: number;
		username: string;
		avatar: string | null;
	} | null;
	effectiveProbability: number;
}

export interface ViewsLeaderEntry {
	rank: number;
	id: number;
	name: string;
	image: string | null;
	views: number;
	owner: {
		id: number;
		username: string | null;
		avatar: string | null;
	} | null;
}

export interface NewsItem {
	id: number;
	title: string;
	content: string;
	createdAt: string;
}

export interface ErrorState {
	title?: string;
	message: string;
	details?: string;
}

// Stores
export const userStore = writable<User | null>(null);
export const tutorialActiveStore = writable(false);
export const tutorialProjectIdStore = writable<number | null>(null);
export const projectsStore = writable<Project[]>([]);
export const shopItemsStore = writable<ShopItem[]>([]);
export const leaderboardStore = writable<{ hours: LeaderboardEntry[]; scraps: LeaderboardEntry[] }>(
	{
		hours: [],
		scraps: []
	}
);
export const newsStore = writable<NewsItem[]>([]);
export const probabilityLeadersStore = writable<ProbabilityLeader[]>([]);
export const viewsLeaderboardStore = writable<ViewsLeaderEntry[]>([]);
export const errorStore = writable<ErrorState | null>(null);

// Loading states
export const projectsLoading = writable(true);
export const shopLoading = writable(true);
export const leaderboardLoading = writable(true);
export const newsLoading = writable(true);
export const probabilityLeadersLoading = writable(true);
export const viewsLeaderboardLoading = writable(true);

// Track if this is a fresh page load (refresh/external) vs SPA navigation
let isInitialLoad = true;
let lastPath = '';

export function markNavigated() {
	isInitialLoad = false;
}

export function isFromAdminOrToAdmin(from: string, to: string): boolean {
	const fromAdmin = from.startsWith('/admin');
	const toAdmin = to.startsWith('/admin');
	return fromAdmin !== toAdmin;
}

export function handleNavigation(newPath: string) {
	const shouldInvalidate = isInitialLoad || isFromAdminOrToAdmin(lastPath, newPath);

	if (shouldInvalidate) {
		invalidateAllStores();
	}

	lastPath = newPath;
	markNavigated();
}

export function invalidateAllStores() {
	projectsStore.set([]);
	shopItemsStore.set([]);
	leaderboardStore.set({ hours: [], scraps: [] });
	newsStore.set([]);
	probabilityLeadersStore.set([]);
	viewsLeaderboardStore.set([]);
	projectsLoading.set(true);
	shopLoading.set(true);
	leaderboardLoading.set(true);
	newsLoading.set(true);
	probabilityLeadersLoading.set(true);
	viewsLeaderboardLoading.set(true);
}

// Fetch functions
export async function fetchProjects(force = false) {
	if (!browser) return;

	const current = get(projectsStore);
	if (current.length > 0 && !force && !get(projectsLoading)) return;

	projectsLoading.set(true);
	try {
		const response = await fetch(`${API_URL}/projects?limit=50`, {
			credentials: 'include'
		});
		if (response.ok) {
			const data = await response.json();
			projectsStore.set(data.data || []);
		}
	} catch (e) {
		console.error('Failed to fetch projects:', e);
	} finally {
		projectsLoading.set(false);
	}
}

export async function fetchShopItems(force = false) {
	if (!browser) return;

	const current = get(shopItemsStore);
	if (current.length > 0 && !force && !get(shopLoading)) return;

	shopLoading.set(true);
	try {
		const response = await fetch(`${API_URL}/shop/items`, {
			credentials: 'include'
		});
		if (response.ok) {
			const data = await response.json();
			shopItemsStore.set(data);
		}
	} catch (e) {
		console.error('Failed to fetch shop items:', e);
	} finally {
		shopLoading.set(false);
	}
}

export async function fetchLeaderboard(sortBy: 'hours' | 'scraps', force = false) {
	if (!browser) return;

	const current = get(leaderboardStore);
	if (current[sortBy].length > 0 && !force && !get(leaderboardLoading)) {
		return current[sortBy];
	}

	leaderboardLoading.set(true);
	try {
		const response = await fetch(`${API_URL}/leaderboard?sortBy=${sortBy}`, {
			credentials: 'include'
		});
		if (response.ok) {
			const data = await response.json();
			leaderboardStore.update((store) => ({
				...store,
				[sortBy]: data
			}));
			return data;
		}
	} catch (e) {
		console.error('Failed to fetch leaderboard:', e);
	} finally {
		leaderboardLoading.set(false);
	}
	return [];
}

export async function fetchNews(force = false) {
	if (!browser) return;

	const current = get(newsStore);
	if (current.length > 0 && !force && !get(newsLoading)) return;

	newsLoading.set(true);
	try {
		const response = await fetch(`${API_URL}/news`, {
			credentials: 'include'
		});
		if (response.ok) {
			const data = await response.json();
			newsStore.set(data);
		}
	} catch (e) {
		console.error('Failed to fetch news:', e);
	} finally {
		newsLoading.set(false);
	}
}

export async function fetchProbabilityLeaders(force = false) {
	if (!browser) return;

	const current = get(probabilityLeadersStore);
	if (current.length > 0 && !force && !get(probabilityLeadersLoading)) return current;

	probabilityLeadersLoading.set(true);
	try {
		const response = await fetch(`${API_URL}/leaderboard/probability-leaders`, {
			credentials: 'include'
		});
		if (response.ok) {
			const data = await response.json();
			probabilityLeadersStore.set(data);
			return data;
		}
	} catch (e) {
		console.error('Failed to fetch probability leaders:', e);
	} finally {
		probabilityLeadersLoading.set(false);
	}
	return [];
}

export async function fetchViewsLeaderboard(force = false) {
	if (!browser) return;

	const current = get(viewsLeaderboardStore);
	if (current.length > 0 && !force && !get(viewsLeaderboardLoading)) return current;

	viewsLeaderboardLoading.set(true);
	try {
		const response = await fetch(`${API_URL}/leaderboard/views`, {
			credentials: 'include'
		});
		if (response.ok) {
			const data = await response.json();
			viewsLeaderboardStore.set(data);
			return data;
		}
	} catch (e) {
		console.error('Failed to fetch views leaderboard:', e);
	} finally {
		viewsLeaderboardLoading.set(false);
	}
	return [];
}

// Background prefetch for common data
export async function prefetchUserData() {
	if (!browser) return;

	// Prefetch in parallel
	await Promise.all([fetchProjects(), fetchShopItems(), fetchLeaderboard('scraps'), fetchNews()]);
}

// Update helpers
export function addProject(project: Project) {
	projectsStore.update((projects) => [...projects, project]);
}

export function updateProject(id: number, updates: Partial<Project>) {
	projectsStore.update((projects) => projects.map((p) => (p.id === id ? { ...p, ...updates } : p)));
}

export function updateShopItemHeart(itemId: number, hearted: boolean, heartCount?: number) {
	shopItemsStore.update((items) =>
		items.map((item) => {
			if (item.id === itemId) {
				return {
					...item,
					userHearted: hearted,
					heartCount: heartCount ?? (hearted ? item.heartCount + 1 : item.heartCount - 1)
				};
			}
			return item;
		})
	);
}

// Error helpers
export function showError(error: ErrorState | string) {
	if (typeof error === 'string') {
		errorStore.set({ message: error });
	} else {
		errorStore.set(error);
	}
}

export function clearError() {
	errorStore.set(null);
}

export async function handleApiError(response: Response, fallbackMessage = 'something went wrong') {
	let message = fallbackMessage;
	let details: string | undefined;

	try {
		const data = await response.json();
		if (data.error) {
			message = data.error;
		} else if (data.message) {
			message = data.message;
		}
	} catch {
		if (response.status >= 500) {
			message = 'server error - please try again later';
			details = `status ${response.status}`;
		}
	}

	showError({
		title: response.status >= 500 ? 'server error' : 'error',
		message,
		details
	});
}
