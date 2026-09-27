export function safeUrl(url: string | null | undefined): string | undefined {
	if (!url) return undefined;
	try {
		const parsed = new URL(url.trim());
		return parsed.protocol === 'http:' || parsed.protocol === 'https:' ? parsed.href : undefined;
	} catch {
		return undefined;
	}
}
