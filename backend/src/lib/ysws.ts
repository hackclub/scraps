import { config } from '../config'

const YSWS_API_URL = 'https://joe.fraud.hackclub.com/api/v1/ysws/events/scraps2'

async function lookupHackatimeId(email: string): Promise<number | null> {
	if (!config.hackatimeAdminKey) return null
	try {
		const res = await fetch('https://hackatime.hackclub.com/api/admin/v1/user/get_user_by_email', {
			method: 'POST',
			headers: {
				'Authorization': `Bearer ${config.hackatimeAdminKey}`,
				'Content-Type': 'application/json',
				'Accept': 'application/json'
			},
			body: JSON.stringify({ email })
		})
		if (!res.ok) return null
		const data = await res.json() as { user_id: number }
		return data.user_id
	} catch {
		return null
	}
}

export async function submitProjectToYSWS(project: {
	name: string
	githubUrl: string | null
	playableUrl: string | null
	hackatimeProject: string | null
	email: string
}) {
	if (!config.fraudToken) {
		console.log('[YSWS] Missing FRAUD_TOKEN, skipping submission')
		return null
	}

	const hackatimeProjects = project.hackatimeProject
		? project.hackatimeProject.split(',').map(n => {
			const trimmed = n.trim()
			const slashIndex = trimmed.indexOf('/')
			return slashIndex !== -1 ? trimmed.substring(slashIndex + 1) : trimmed
		}).filter(n => n.length > 0)
		: []

	const hackatimeId = await lookupHackatimeId(project.email)

	const payload = {
		name: project.name,
		codeLink: project.githubUrl || '',
		demoLink: project.playableUrl || '',
		submitter: {
			hackatimeId: hackatimeId || 0
		},
		hackatimeProjects
	}

	try {
		const res = await fetch(`${YSWS_API_URL}/projects`, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'Authorization': `Bearer ${config.fraudToken}`
			},
			body: JSON.stringify(payload)
		})

		if (!res.ok) {
			const text = await res.text()
			console.error('[YSWS] submission failed:', res.status, text)
			return null
		}

		const data = await res.json()
		console.log('[YSWS] submitted project:', project.name)
		return data
	} catch (e) {
		console.error('[YSWS] submission error:', e)
		return null
	}
}
