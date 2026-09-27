import { getUser } from '$lib/auth-client';

const MB = 1024 * 1024;

export async function uploadLimitMb(): Promise<number> {
	try {
		const user = await getUser();
		return user && ['admin', 'creator'].includes(user.role) ? 15 : 5;
	} catch {
		return 5;
	}
}

export async function isOverUploadLimit(file: File): Promise<number | null> {
	const mb = await uploadLimitMb();
	return file.size > mb * MB ? mb : null;
}
