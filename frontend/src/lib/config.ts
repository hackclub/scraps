export const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000';

export interface ServerConfig {
	scrapsPerDollar: number;
	dollarsPerHour: number;
	tierMultipliers: Record<number, number>;
}

export const serverConfig: Partial<ServerConfig> = {};

export async function fetchServerConfig(): Promise<void> {
	try {
		const res = await fetch(`${API_URL}/admin/config`, { credentials: 'include' });
		if (!res.ok) return;
		const data = await res.json();
		Object.assign(serverConfig, data);
	} catch (e) {
		// Intentionally ignore errors — frontend can fall back to local constants if needed
	}
}
