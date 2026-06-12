import { Elysia } from 'elysia'
import { getUserFromSession } from '../lib/auth'
import { config } from '../config'

const HCCDN_URL = 'https://cdn.hackclub.com/api/v4/upload'
const HCCDN_KEY = config.hccdnKey

interface CDNUploadResponse {
	id: string
	filename: string
	size: number
	content_type: string
	url: string
	created_at: string
}

const upload = new Elysia({ prefix: '/upload' })

upload.post('/image', async ({ body, headers }) => {
	const user = await getUserFromSession(headers as Record<string, string>)
	if (!user) return { error: 'Unauthorized' }

	if (!HCCDN_KEY) {
		console.error('[UPLOAD] HCCDN_KEY not configured')
		return { error: 'Upload service not configured' }
	}

	const { file } = body as { file: File }

	if (!file) {
		return { error: 'No file provided' }
	}

	try {
		const contentType = file.type
		const extMap: Record<string, string> = {
			'image/jpeg': 'jpg',
			'image/jpg': 'jpg',
			'image/png': 'png',
			'image/gif': 'gif',
			'image/webp': 'webp'
		}
		const ext = extMap[contentType] || 'png'
		const filename = `scrap-${Date.now()}.${ext}`

		const formData = new FormData()
		formData.append('file', file, filename)

		console.log('[UPLOAD] Uploading to CDN:', { userId: user.id, filename, size: file.size })

		const response = await fetch(HCCDN_URL, {
			method: 'POST',
			headers: {
				'Authorization': `Bearer ${HCCDN_KEY}`
			},
			body: formData
		})

		if (!response.ok) {
			const errorText = await response.text()
			console.error('[UPLOAD] CDN error:', { status: response.status, body: errorText })
			return { error: 'Failed to upload image' }
		}

		const data: CDNUploadResponse = await response.json()
		console.log('[UPLOAD] Upload successful:', { url: data.url })

		return { url: data.url }
	} catch (error) {
		console.error('[UPLOAD] Error:', error)
		return { error: 'Failed to upload image' }
	}
})

export default upload
