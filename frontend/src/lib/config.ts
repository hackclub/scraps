// Rails now serves the built frontend directly, so in production the API is same-origin
// and API_URL can just be empty (relative paths). Local dev still runs two processes
// (Vite on :5173, Rails on :3000), so it needs an absolute URL to cross that gap.
export const API_URL =
	import.meta.env.VITE_API_URL ||
	(typeof window !== 'undefined' && window.location.hostname !== 'localhost'
		? ''
		: 'http://localhost:3000');

export interface ServerConfig {
	scrapsPerDollar: number;
	tierMultipliers: Record<number, number>;
	version: string;
	versionSha: string;
	versionUrl: string | null;
}

export const serverConfig: Partial<ServerConfig> = {};

import { writable } from 'svelte/store';

export const deployVersion = writable<{ short: string; url: string | null } | null>(null);

export async function fetchServerConfig(): Promise<void> {
	try {
		const res = await fetch(`${API_URL}/admin/config`, { credentials: 'include' });
		if (!res.ok) return;
		const data = await res.json();
		Object.assign(serverConfig, data);
		if (data.version) deployVersion.set({ short: data.version, url: data.versionUrl ?? null });
	} catch (_e) {
		// Intentionally ignore errors — frontend can fall back to local constants if needed
	}
}
