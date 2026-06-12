export function formatHours(hours: number): string {
	return hours.toFixed(1);
}

/**
 * Parse a stored hackatime project entry and extract just the project name.
 * Handles all formats:
 *   - "123:project-name" (migrated format with hackatime user ID)
 *   - "U12345/project-name" (old Slack ID format)
 *   - "project-name" (plain format)
 */
export function parseHackatimeProjectName(entry: string): string {
	const trimmed = entry.trim();
	if (!trimmed) return trimmed;

	// New format: "123:projectName" (numeric hackatime user ID with colon)
	const colonIndex = trimmed.indexOf(':');
	if (colonIndex !== -1 && !trimmed.startsWith('U')) {
		return trimmed.substring(colonIndex + 1);
	}

	// Old format: "U12345/projectName" (Slack ID with slash)
	const slashIndex = trimmed.indexOf('/');
	if (slashIndex !== -1 && trimmed.startsWith('U')) {
		return trimmed.substring(slashIndex + 1);
	}

	// Plain project name
	return trimmed;
}

/**
 * Parse a comma-separated hackatime project string into an array of plain project names.
 */
export function parseHackatimeProjectNames(hackatimeProject: string | null): string[] {
	if (!hackatimeProject) return [];
	return hackatimeProject
		.split(',')
		.map((p) => parseHackatimeProjectName(p))
		.filter((p) => p.length > 0);
}

export function validateGithubUrl(url: string | null | undefined): {
	valid: boolean;
	error?: string;
} {
	if (!url || !url.trim()) return { valid: true };
	const trimmed = url.trim();

	let parsed: URL;
	try {
		parsed = new URL(trimmed);
	} catch {
		return { valid: false, error: 'Not a valid URL' };
	}

	if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
		return { valid: false, error: 'Must use http or https' };
	}
	return { valid: true };
}

export function validatePlayableUrl(url: string | null | undefined): {
	valid: boolean;
	error?: string;
} {
	if (!url || !url.trim()) return { valid: true };
	const trimmed = url.trim();

	let parsed: URL;
	try {
		parsed = new URL(trimmed);
	} catch {
		return { valid: false, error: 'Not a valid URL' };
	}

	if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
		return { valid: false, error: 'Must use http or https' };
	}

	if (!parsed.hostname.includes('.')) {
		return { valid: false, error: 'Must be a valid public URL' };
	}

	return { valid: true };
}
