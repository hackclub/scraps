import Airtable from 'airtable'
import { db } from '../db'
import { projectsTable } from '../schemas/projects'
import { usersTable } from '../schemas/users'
import { userActivityTable } from '../schemas/user-emails'
import { projectActivityTable } from '../schemas/activity'
import { reviewsTable } from '../schemas/reviews'
import { config } from '../config'
import { eq, and, or, isNull, min, sql, inArray } from 'drizzle-orm'
import { fetchUserIdentity } from './auth'
import { getProjectShippedDates } from './effective-hours'

const SYNC_INTERVAL_MS = 5 * 60 * 1000 // 5 minutes

let syncInterval: ReturnType<typeof setInterval> | null = null

// Fetch hours already awarded in other YSWS programs from the unified airtable
export async function fetchOtherYswsHours(codeUrls: Set<string>, playableUrls: Set<string>): Promise<Map<string, number>> {
	// Map of URL -> total hours awarded in other YSWS programs
	const urlHoursMap = new Map<string, number>()

	if (!config.unifiedAirtableToken || !config.unifiedAirtableBaseId || !config.unifiedAirtableTableId) {
		return urlHoursMap
	}

	const baseUrl = `https://api.airtable.com/v0/${config.unifiedAirtableBaseId}/${config.unifiedAirtableTableId}`

	const seenRecordIds = new Set<string>()

	async function fetchByFormula(formula: string): Promise<{ recordId: string; codeUrl: string; playableUrl: string; hours: number }[]> {
		const results: { recordId: string; codeUrl: string; playableUrl: string; hours: number }[] = []
		let offset: string | undefined
		do {
			const params = new URLSearchParams({
				filterByFormula: formula,
				pageSize: '100',
			})
			params.append('fields[]', 'YSWS')
			params.append('fields[]', 'Code URL')
			params.append('fields[]', 'Playable URL')
			params.append('fields[]', 'Override Hours Spent')
			params.append('fields[]', 'Hours Spent')
			if (offset) params.set('offset', offset)

			const res = await fetch(`${baseUrl}?${params.toString()}`, {
				headers: { Authorization: `Bearer ${config.unifiedAirtableToken}` },
			})
			if (!res.ok) break

			const data = await res.json() as { records: { id: string; fields: Record<string, any> }[]; offset?: string }
			for (const record of data.records) {
				if (seenRecordIds.has(record.id)) continue
				seenRecordIds.add(record.id)
				const overrideHours = record.fields['Override Hours Spent']
				const hoursSpent = record.fields['Hours Spent']
				const hours = Number(overrideHours ?? hoursSpent ?? 0)
				if (hours > 0) {
					results.push({
						recordId: record.id,
						codeUrl: record.fields['Code URL'] || '',
						playableUrl: record.fields['Playable URL'] || '',
						hours,
					})
				}
			}
			offset = data.offset
		} while (offset)
		return results
	}

	try {
		// Batch code URL lookups
		const codeUrlArr = [...codeUrls]
		for (let i = 0; i < codeUrlArr.length; i += 15) {
			const batch = codeUrlArr.slice(i, i + 15)
			const orParts = batch.map(u => `{Code URL}='${u.replace(/'/g, "\\'")}'`)
			const formula = `AND(YSWS!='scraps',OR(${orParts.join(',')}))`
			const results = await fetchByFormula(formula)
			for (const r of results) {
				if (r.codeUrl) {
					urlHoursMap.set(r.codeUrl, (urlHoursMap.get(r.codeUrl) || 0) + r.hours)
				}
			}
		}

		// Batch playable URL lookups
		const playableUrlArr = [...playableUrls]
		for (let i = 0; i < playableUrlArr.length; i += 15) {
			const batch = playableUrlArr.slice(i, i + 15)
			const orParts = batch.map(u => `{Playable URL}='${u.replace(/'/g, "\\'")}'`)
			const formula = `AND(YSWS!='scraps',OR(${orParts.join(',')}))`
			const results = await fetchByFormula(formula)
			for (const r of results) {
				if (r.playableUrl) {
					urlHoursMap.set(r.playableUrl, (urlHoursMap.get(r.playableUrl) || 0) + r.hours)
				}
			}
		}
	} catch (err) {
		console.error('[AIRTABLE-SYNC] Error fetching other YSWS hours:', err)
	}

	return urlHoursMap
}

function getBase(): Airtable.Base | null {
	if (!config.airtableToken || !config.airtableBaseId) {
		console.log('[AIRTABLE-SYNC] Missing AIRTABLE_TOKEN or AIRTABLE_BASE_ID, skipping sync')
		return null
	}

	const airtable = new Airtable({ apiKey: config.airtableToken })
	return airtable.base(config.airtableBaseId)
}

function formatHoursMinutes(hours: number): string {
	const totalMinutes = Math.round(hours * 60)
	const h = Math.floor(totalMinutes / 60)
	const m = totalMinutes % 60
	if (h === 0) return `${m}min`
	if (m === 0) return `${h}h`
	return `${h}h ${m}min`
}

function buildJustification(project: {
	id: number
	hours: number | null
	hoursOverride: number | null
}, reviews: {
	action: string
	reviewerName: string | null
	internalJustification: string | null
	createdAt: Date
}[], effectiveHours: number): string {
	const lines: string[] = []
	const rawHours = project.hours ?? 0

	if (project.hoursOverride !== null && project.hoursOverride !== rawHours) {
		lines.push(`The user logged ${formatHoursMinutes(rawHours)} on hackatime.`)
		lines.push(`Hours were overridden to ${formatHoursMinutes(project.hoursOverride)} by a reviewer.`)
		if (effectiveHours !== project.hoursOverride) {
			lines.push(`After deducting overlapping projects, effective hours: ${formatHoursMinutes(effectiveHours)}.`)
		}
	} else if (effectiveHours !== rawHours) {
		lines.push(`The user logged ${formatHoursMinutes(rawHours)} on hackatime.`)
		lines.push(`After deducting overlapping projects, effective hours: ${formatHoursMinutes(effectiveHours)}.`)
	} else {
		lines.push(`The user logged ${formatHoursMinutes(effectiveHours)} on hackatime.`)
	}
	lines.push('')
	lines.push(`The scraps project can be found at ${config.frontendUrl}/projects/${project.id}`)

	if (reviews.length > 0) {
		lines.push('')
		lines.push('Review history:')
		for (const review of reviews) {
			const reviewerName = review.reviewerName || 'Unknown'
			const date = review.createdAt.toISOString().split('T')[0]
			lines.push(`- ${reviewerName} ${review.action} on ${date}`)
			if (review.internalJustification) {
				lines.push(`  Justification: ${review.internalJustification}`)
			}
		}
	}

	lines.push('')
	lines.push(`Full review history can be found at ${config.frontendUrl}/admin/reviews/${project.id}`)

	return lines.join('\n')
}

export async function syncProjectsToAirtable(): Promise<void> {
	const base = getBase()
	if (!base) return

	console.log('[AIRTABLE-SYNC] Syncing shipped projects...')

	try {
		// Get all shipped projects with user data
		const projects = await db
			.select({
				id: projectsTable.id,
				name: projectsTable.name,
				description: projectsTable.description,
				image: projectsTable.image,
				githubUrl: projectsTable.githubUrl,
				playableUrl: projectsTable.playableUrl,
				hours: projectsTable.hours,
				hoursOverride: projectsTable.hoursOverride,
				hackatimeProject: projectsTable.hackatimeProject,
				scrapsPaidAt: projectsTable.scrapsPaidAt,
				tier: projectsTable.tier,
				status: projectsTable.status,
				updateDescription: projectsTable.updateDescription,
				aiDescription: projectsTable.aiDescription,
				feedbackSource: projectsTable.feedbackSource,
				feedbackGood: projectsTable.feedbackGood,
				feedbackImprove: projectsTable.feedbackImprove,
				createdAt: projectsTable.createdAt,
				userId: projectsTable.userId,
				username: usersTable.username,
				email: usersTable.email,
				slackId: usersTable.slackId,
				accessToken: usersTable.accessToken
			})
			.from(projectsTable)
			.innerJoin(usersTable, eq(projectsTable.userId, usersTable.id))
			.where(and(
				eq(projectsTable.status, 'shipped'),
				or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted))
			))

		// Fetch all reviews for shipped projects with reviewer usernames
		const projectIds = projects.map(p => p.id)
		let reviewsByProjectId = new Map<number, { action: string; reviewerName: string | null; internalJustification: string | null; createdAt: Date }[]>()
		if (projectIds.length > 0) {
			const allReviews = await db
				.select({
					projectId: reviewsTable.projectId,
					action: reviewsTable.action,
					internalJustification: reviewsTable.internalJustification,
					createdAt: reviewsTable.createdAt,
					reviewerUsername: usersTable.username
				})
				.from(reviewsTable)
				.leftJoin(usersTable, eq(reviewsTable.reviewerId, usersTable.id))
				.where(inArray(reviewsTable.projectId, projectIds))

			for (const review of allReviews) {
				const existing = reviewsByProjectId.get(review.projectId) || []
				existing.push({
					action: review.action,
					reviewerName: review.reviewerUsername,
					internalJustification: review.internalJustification,
					createdAt: review.createdAt
				})
				reviewsByProjectId.set(review.projectId, existing)
			}
		}

		// Fetch project activity events for timeline
		let activityByProjectId = new Map<number, { action: string; createdAt: Date }[]>()
		if (projectIds.length > 0) {
			const allActivity = await db
				.select({
					projectId: projectActivityTable.projectId,
					action: projectActivityTable.action,
					createdAt: projectActivityTable.createdAt
				})
				.from(projectActivityTable)
				.where(inArray(projectActivityTable.projectId, projectIds))

			for (const activity of allActivity) {
				if (!activity.projectId) continue
				const existing = activityByProjectId.get(activity.projectId) || []
				existing.push({ action: activity.action, createdAt: activity.createdAt })
				activityByProjectId.set(activity.projectId, existing)
			}
		}

		const table = base(config.airtableProjectsTableId)

		// Fetch existing records from Airtable to find which ones to update vs create
		const existingRecords: Map<string, string> = new Map() // github_url -> airtable record id
		const approvedRecords: Set<string> = new Set() // github_urls that are already approved in Airtable
		const pendingUpdateRecords: Map<string, string> = new Map() // github_url -> pending airtable record id (for URLs that also have an approved record)
		const airtableHoursMap: Map<string, number> = new Map() // github_url -> hours from approved records
		const airtableRecordsToDelete: string[] = [] // airtable record ids to delete (for rejected projects)
		const pendingRecordIds: Map<string, string> = new Map() // github_url -> non-approved airtable record id
		const recordsToAutoApprove: string[] = [] // airtable record ids that have YSWS Record ID but aren't Approved yet
		await new Promise<void>((resolve, reject) => {
			table.select({
				fields: ['Code URL', 'Review Status', 'Optional - Override Hours Spent', 'Automation - YSWS Record ID']
			}).eachPage(
				(records, fetchNextPage) => {
					for (const record of records) {
						const githubUrl = record.get('Code URL')
						if (githubUrl) {
							const url = String(githubUrl)
							existingRecords.set(url, record.id)
							const reviewStatus = record.get('Review Status')
							const yswsRecordId = record.get('Automation - YSWS Record ID')
							if (reviewStatus === 'Approved') {
								approvedRecords.add(url)
								const hours = record.get('Optional - Override Hours Spent')
								if (hours !== undefined && hours !== null) {
									airtableHoursMap.set(url, Number(hours))
								}
							} else {
								// Track non-approved record id for this URL
								pendingRecordIds.set(url, record.id)
								// Auto-approve records that have a YSWS Record ID but aren't marked Approved
								if (yswsRecordId) {
									recordsToAutoApprove.push(record.id)
								}
							}
						}
					}
					fetchNextPage()
				},
				(err) => {
					if (err) reject(err)
					else resolve()
				}
			)
		})
		// Mark URLs that have both an approved record and a non-approved (pending) record
		for (const [url, recordId] of pendingRecordIds.entries()) {
			if (approvedRecords.has(url)) {
				pendingUpdateRecords.set(url, recordId)
			}
		}

		// Auto-approve Airtable records that have a YSWS Record ID but aren't Approved yet
		for (let i = 0; i < recordsToAutoApprove.length; i += 10) {
			const batch = recordsToAutoApprove.slice(i, i + 10)
			await table.update(batch.map(id => ({ id, fields: { 'Review Status': 'Approved' } })))
		}
		if (recordsToAutoApprove.length > 0) {
			console.log(`[AIRTABLE-SYNC] Auto-approved ${recordsToAutoApprove.length} records with YSWS Record ID`)
		}

		// Find projects that were rejected in payout review (scraps_unawarded)
		// Only remove their Airtable entries if they have NOT been later approved
		if (projectIds.length > 0) {
			// Get all rejected reviews
			const rejectedReviews = await db
				.select({
					projectId: reviewsTable.projectId,
					action: reviewsTable.action
				})
				.from(reviewsTable)
				.where(and(
					inArray(reviewsTable.projectId, projectIds),
					eq(reviewsTable.action, 'scraps_unawarded')
				))

			// Get all approved reviews
			const approvedReviews = await db
				.select({
					projectId: reviewsTable.projectId,
					action: reviewsTable.action
				})
				.from(reviewsTable)
				.where(and(
					inArray(reviewsTable.projectId, projectIds),
					eq(reviewsTable.action, 'approved')
				))

			const approvedProjectIds = new Set(approvedReviews.map(r => r.projectId))

			for (const review of rejectedReviews) {
				// Only delete if NOT later approved
				if (approvedProjectIds.has(review.projectId)) continue
				// Find githubUrl for this project
				const project = projects.find(p => p.id === review.projectId)
				if (project && project.githubUrl) {
					const airtableId = existingRecords.get(project.githubUrl)
					if (airtableId) {
						airtableRecordsToDelete.push(airtableId)
					}
				}
			}
		}

		const toCreate: Airtable.FieldSet[] = []
		const toUpdate: { id: string; fields: Airtable.FieldSet }[] = []
		const duplicateProjectIds: number[] = [] // projects with duplicate Code URLs to revert
		const updateCreates: Airtable.FieldSet[] = [] // new rows for updated approved projects

		// Cache user identity per userId to avoid redundant API calls
		const userInfoCache: Map<number, Awaited<ReturnType<typeof fetchUserIdentity>>> = new Map()

		// Batch-fetch first shipped dates from project_activity for all projects
		const shippedDates = await getProjectShippedDates(projects.map(p => p.id))

		// Fetch hours awarded in other YSWS programs for deduction
		const allCodeUrls = new Set(projects.map(p => p.githubUrl).filter((u): u is string => !!u))
		const allPlayableUrls = new Set(projects.map(p => p.playableUrl).filter((u): u is string => !!u))
		const otherYswsHours = await fetchOtherYswsHours(allCodeUrls, allPlayableUrls)
		if (otherYswsHours.size > 0) {
			console.log(`[AIRTABLE-SYNC] Found ${otherYswsHours.size} URLs with hours in other YSWS programs`)
		}

		// Track which Code URLs we've already seen to detect cross-user duplicates
		// Same-user duplicates are project updates and should be allowed
		const seenCodeUrls = new Map<string, number>() // url -> userId

		for (const project of projects) {
			if (!project.githubUrl) continue // skip projects without a GitHub URL
			if (!project.image) continue // screenshot must exist

			// Check if this project is already approved in Airtable
			const isApproved = approvedRecords.has(project.githubUrl)
			const currentEffectiveHours = Math.round((project.hoursOverride ?? project.hours ?? 0) * 10) / 10
			const airtableHours = airtableHoursMap.get(project.githubUrl)
			const roundedAirtableHours = airtableHours !== undefined ? Math.round(airtableHours * 10) / 10 : undefined

			// For approved projects, check if this is an update that needs a new row
			const isUnpaidUpdate = isApproved && !project.scrapsPaidAt
			const isHoursUpdate = isApproved && roundedAirtableHours !== undefined && currentEffectiveHours > roundedAirtableHours
			const hasUpdateDescription = isApproved && !!project.updateDescription
			const isUpdate = isUnpaidUpdate || isHoursUpdate || hasUpdateDescription

			if (isApproved && !isUpdate) continue

			// Check for cross-user duplicate Code URL among shipped projects
			const previousOwner = seenCodeUrls.get(project.githubUrl)
			if (previousOwner !== undefined && previousOwner !== project.userId) {
				console.log(`[AIRTABLE-SYNC] Duplicate Code URL detected for project ${project.id}: ${project.githubUrl}, reverting to waiting_for_review`)
				duplicateProjectIds.push(project.id)
				continue
			}
			seenCodeUrls.set(project.githubUrl, project.userId)

			// Fetch user identity if not cached
			if (!userInfoCache.has(project.userId) && project.accessToken) {
				const info = await fetchUserIdentity(project.accessToken)
				userInfoCache.set(project.userId, info)
			}
			const userIdentity = userInfoCache.get(project.userId)?.identity

			// Compute effective hours by deducting overlapping shipped project hours
			// Only deduct from projects that were shipped BEFORE this one (using activity-derived dates)
			const projectShippedDate = shippedDates.get(project.id)
			let effectiveHours = project.hoursOverride ?? project.hours ?? 0
			if (project.hackatimeProject && projectShippedDate) {
				const hackatimeNames = project.hackatimeProject.split(',').map(n => n.trim()).filter(n => n.length > 0)
				if (hackatimeNames.length > 0) {
					for (const op of projects) {
						if (op.id === project.id || op.userId !== project.userId) continue
						if (!op.hackatimeProject) continue
						const opShippedDate = shippedDates.get(op.id)
						if (!opShippedDate) continue
						// Only deduct from projects shipped before this one
						if (opShippedDate >= projectShippedDate) continue
						const opNames = op.hackatimeProject.split(',').map(n => n.trim()).filter(n => n.length > 0)
						if (opNames.some(name => hackatimeNames.includes(name))) {
							effectiveHours -= (op.hoursOverride ?? op.hours ?? 0)
						}
					}
					effectiveHours = Math.max(0, effectiveHours)
				}
			}

			// Deduct hours already awarded in other YSWS programs
			// Skip deduction if project has an override — the reviewer already set the intended hours
			if (project.hoursOverride === null) {
				let otherYswsDeduction = 0
				if (project.githubUrl && otherYswsHours.has(project.githubUrl)) {
					otherYswsDeduction += otherYswsHours.get(project.githubUrl)!
				}
				if (project.playableUrl && otherYswsHours.has(project.playableUrl)) {
					otherYswsDeduction += otherYswsHours.get(project.playableUrl)!
				}
				if (otherYswsDeduction > 0) {
					console.log(`[AIRTABLE-SYNC] Deducting ${otherYswsDeduction}h from project ${project.id} (awarded in other YSWS programs)`)
					effectiveHours = Math.max(0, effectiveHours - otherYswsDeduction)
				}
			}

			const firstName = userIdentity?.first_name || (project.username || '').split(' ')[0] || ''
			const lastName = userIdentity?.last_name || (project.username || '').split(' ').slice(1).join(' ') || ''

			// Build activity timeline for this project
			const activities = activityByProjectId.get(project.id) || []
			const sortedActivities = [...activities].sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
			let activityTimeline = ''
			if (sortedActivities.length > 0) {
				const timelineLines = sortedActivities.map(a => {
					const date = a.createdAt.toISOString().split('T')[0]
					const time = a.createdAt.toISOString().split('T')[1].split('.')[0]
					return `- ${a.action} (${date} ${time} UTC)`
				})
				activityTimeline = `\nProject timeline:\n${timelineLines.join('\n')}`
			}

			const descriptionParts = [project.description || '']
			if (project.updateDescription) {
				descriptionParts.push(`\nThis project is an update. ${project.updateDescription}`)
			}
			if (project.aiDescription) {
				descriptionParts.push(`\nAI was used in this project. ${project.aiDescription}`)
			}
			if (activityTimeline) {
				descriptionParts.push(activityTimeline)
			}

			// For approved projects that have been updated, create a NEW row or update existing pending row
			if (isUpdate && isApproved) {
				const previousHours = roundedAirtableHours ?? 0
				const deltaHours = Math.max(0, effectiveHours - previousHours)

				const updateDescParts: string[] = []
				updateDescParts.push(`[UPDATE] This is an update to a previously approved project.`)
				if (project.updateDescription) {
					updateDescParts.push(`\nWhat was updated: ${project.updateDescription}`)
				}
				updateDescParts.push(`\nOriginal project had ${formatHoursMinutes(previousHours)} approved.`)
				updateDescParts.push(`New hours from this update: ${formatHoursMinutes(deltaHours)}`)
				if (project.description) {
					updateDescParts.push(`\nOriginal description: ${project.description}`)
				}
				if (project.aiDescription) {
					updateDescParts.push(`\nAI was used in this project. ${project.aiDescription}`)
				}
				if (activityTimeline) {
					updateDescParts.push(activityTimeline)
				}

				const updateFields: Airtable.FieldSet = {
					'Code URL': project.githubUrl,
					'Description': updateDescParts.join('\n'),
					'Email': project.email || '',
					'First Name': firstName,
					'Last Name': lastName,
					'GitHub Username': project.username || '',
					'How can we improve?': project.feedbackImprove || '',
					'How did you hear about this?': project.feedbackSource || '',
					'What are we doing well?': project.feedbackGood || '',
					'Slack ID': project.slackId || '',
					'Optional - Override Hours Spent': deltaHours,
					'Optional - Override Hours Spent Justification': buildJustification(
						project,
						reviewsByProjectId.get(project.id) || [],
						deltaHours
					),
					'Playable URL': project.playableUrl || '',
					'Screenshot': [{ url: project.image }] as any,
				}

				if (userIdentity?.addresses) {
					if (userIdentity.addresses[0]) {
						if (userIdentity.addresses[0].line_1) updateFields['Address (Line 1)'] = userIdentity.addresses[0].line_1
						if (userIdentity.addresses[0].line_2) updateFields['Address (Line 2)'] = userIdentity.addresses[0].line_2
					}
					if (userIdentity.addresses[0].city) updateFields['City'] = userIdentity.addresses[0].city
					if (userIdentity.addresses[0].state) updateFields['State / Province'] = userIdentity.addresses[0].state
					if (userIdentity.addresses[0].postal_code) updateFields['ZIP / Postal Code'] = userIdentity.addresses[0].postal_code
					if (userIdentity.addresses[0].country) updateFields['Country'] = userIdentity.addresses[0].country
				}

				if (userIdentity?.birthday) {
					updateFields['Birthday'] = userIdentity.birthday
				}

				// If a pending update row already exists, update it; otherwise create a new one
				const existingPendingId = pendingUpdateRecords.get(project.githubUrl)
				if (existingPendingId) {
					toUpdate.push({ id: existingPendingId, fields: updateFields })
				} else {
					updateCreates.push(updateFields)
				}
				continue
			}

			const fields: Airtable.FieldSet = {
				'Code URL': project.githubUrl,
				'Description': descriptionParts.join('\n'),
				'Email': project.email || '',
				'First Name': firstName,
				'Last Name': lastName,
				'GitHub Username': project.username || '',
				'How can we improve?': project.feedbackImprove || '',
				'How did you hear about this?': project.feedbackSource || '',
				'What are we doing well?': project.feedbackGood || '',
				'Slack ID': project.slackId || '',
				'Optional - Override Hours Spent': effectiveHours,
				'Optional - Override Hours Spent Justification': buildJustification(
					project,
					reviewsByProjectId.get(project.id) || [],
					effectiveHours
				),
				'Playable URL': project.playableUrl || '',
				'Screenshot': [{ url: project.image }] as any,
			}

			// Add address fields from userinfo
			if (userIdentity?.addresses) {
				if (userIdentity.addresses[0]) {
					if (userIdentity.addresses[0].line_1) fields['Address (Line 1)'] = userIdentity.addresses[0].line_1
					if (userIdentity.addresses[0].line_2) fields['Address (Line 2)'] = userIdentity.addresses[0].line_2
				}
				if (userIdentity.addresses[0].city) fields['City'] = userIdentity.addresses[0].city
				if (userIdentity.addresses[0].state) fields['State / Province'] = userIdentity.addresses[0].state
				if (userIdentity.addresses[0].postal_code) fields['ZIP / Postal Code'] = userIdentity.addresses[0].postal_code
				if (userIdentity.addresses[0].country) fields['Country'] = userIdentity.addresses[0].country
			}

			// Add birthday and phone from identity
			if (userIdentity?.birthday) {
				fields['Birthday'] = userIdentity.birthday
			}
			// if (userIdentity?.phone_number) {
			// 	fields['Phone Number'] = userIdentity.phone_number
			// }

			const existingId = existingRecords.get(project.githubUrl)
			if (existingId) {
				toUpdate.push({ id: existingId, fields })
			} else {
				toCreate.push(fields)
			}
		}

		// Airtable API allows max 10 records per request
		const allCreates = [...toCreate, ...updateCreates]
		for (let i = 0; i < allCreates.length; i += 10) {
			const batch = allCreates.slice(i, i + 10)
			await table.create(batch.map(fields => ({ fields })))
		}

		// Deduplicate toUpdate by Airtable record ID (keep last occurrence)
		const deduplicatedUpdates = new Map<string, { id: string; fields: Airtable.FieldSet }>()
		for (const update of toUpdate) {
			deduplicatedUpdates.set(update.id, update)
		}
		const uniqueUpdates = Array.from(deduplicatedUpdates.values())

		for (let i = 0; i < uniqueUpdates.length; i += 10) {
			const batch = uniqueUpdates.slice(i, i + 10)
			await table.update(batch)
		}

		// Delete Airtable records for rejected payout projects
		for (let i = 0; i < airtableRecordsToDelete.length; i += 10) {
			const batch = airtableRecordsToDelete.slice(i, i + 10)
			await table.destroy(batch)
		}

		// Revert duplicate projects back to waiting_for_review
		for (const projectId of duplicateProjectIds) {
			await db
				.update(projectsTable)
				.set({ status: 'waiting_for_review', updatedAt: new Date() })
				.where(eq(projectsTable.id, projectId))
		}
		if (duplicateProjectIds.length > 0) {
			console.log(`[AIRTABLE-SYNC] Reverted ${duplicateProjectIds.length} duplicate projects back to waiting_for_review`)
		}

		if (airtableRecordsToDelete.length > 0) {
			console.log(`[AIRTABLE-SYNC] Deleted ${airtableRecordsToDelete.length} rejected payout projects from Airtable`)
		}

		console.log(`[AIRTABLE-SYNC] Projects: ${toCreate.length} created, ${updateCreates.length} update rows created, ${uniqueUpdates.length} updated`)
	} catch (error) {
		console.error('[AIRTABLE-SYNC] Error syncing projects:', error)
	}
}

async function syncUsersToAirtable(): Promise<void> {
	const base = getBase()
	if (!base) return

	console.log('[AIRTABLE-SYNC] Syncing users...')

	try {
		const users = await db
			.select({
				id: usersTable.id,
				slackId: usersTable.slackId,
				email: usersTable.email,
				createdAt: usersTable.createdAt,
				tutorialCompleted: usersTable.tutorialCompleted
			})
			.from(usersTable)

		const table = base(config.airtableUsersTableId)

		// Fetch existing records
		const existingRecords: Map<string, string> = new Map() // slack_id -> airtable record id
		await new Promise<void>((resolve, reject) => {
			table.select({
				fields: ['slack_id']
			}).eachPage(
				(records, fetchNextPage) => {
					for (const record of records) {
						const slackId = record.get('slack_id')
						if (slackId) {
							existingRecords.set(String(slackId), record.id)
						}
					}
					fetchNextPage()
				},
				(err) => {
					if (err) reject(err)
					else resolve()
				}
			)
		})

		// Batch-fetch auth_started and auth_completed timestamps from user_activity
		const authStartedRows = await db
			.select({
				userId: userActivityTable.userId,
				earliest: min(userActivityTable.createdAt)
			})
			.from(userActivityTable)
			.where(eq(userActivityTable.action, 'auth_started'))
			.groupBy(userActivityTable.userId)

		const authCompletedRows = await db
			.select({
				userId: userActivityTable.userId,
				earliest: min(userActivityTable.createdAt)
			})
			.from(userActivityTable)
			.where(eq(userActivityTable.action, 'auth_completed'))
			.groupBy(userActivityTable.userId)

		// Batch-fetch tutorial_completed timestamps from user_activity
		const tutorialCompletedRows = await db
			.select({
				userId: userActivityTable.userId,
				earliest: min(userActivityTable.createdAt)
			})
			.from(userActivityTable)
			.where(eq(userActivityTable.action, 'tutorial_completed'))
			.groupBy(userActivityTable.userId)

		// Batch-fetch earliest project_created from project_activity
		const firstProjectRows = await db
			.select({
				userId: projectActivityTable.userId,
				earliest: min(projectActivityTable.createdAt)
			})
			.from(projectActivityTable)
			.where(eq(projectActivityTable.action, 'project_created'))
			.groupBy(projectActivityTable.userId)

		// Batch-fetch earliest project_submitted from project_activity
		const firstProjectSubmittedRows = await db
			.select({
				userId: projectActivityTable.userId,
				earliest: min(projectActivityTable.createdAt)
			})
			.from(projectActivityTable)
			.where(eq(projectActivityTable.action, 'project_submitted'))
			.groupBy(projectActivityTable.userId)

		// Batch-fetch earliest project_shipped from project_activity
		const firstProjectShippedRows = await db
			.select({
				userId: projectActivityTable.userId,
				earliest: min(projectActivityTable.createdAt)
			})
			.from(projectActivityTable)
			.where(eq(projectActivityTable.action, 'project_shipped'))
			.groupBy(projectActivityTable.userId)

		// Batch-fetch hour milestone timestamps from user_activity
		const hourMilestoneActions = ['scrapsOneHour', 'scrapsFiveHours', 'scrapsTenHours', 'scrapsTwentyHours'] as const
		const hourMilestoneRows = await db
			.select({
				userId: userActivityTable.userId,
				action: userActivityTable.action,
				earliest: min(userActivityTable.createdAt)
			})
			.from(userActivityTable)
			.where(sql`${userActivityTable.action} IN ('scrapsOneHour', 'scrapsFiveHours', 'scrapsTenHours', 'scrapsTwentyHours')`)
			.groupBy(userActivityTable.userId, userActivityTable.action)

		const authStartedMap = new Map(authStartedRows.filter(r => r.userId != null).map(r => [r.userId!, r.earliest]))
		const authCompletedMap = new Map(authCompletedRows.filter(r => r.userId != null).map(r => [r.userId!, r.earliest]))
		const tutorialCompletedMap = new Map(tutorialCompletedRows.filter(r => r.userId != null).map(r => [r.userId!, r.earliest]))
		const firstProjectMap = new Map(firstProjectRows.map(r => [r.userId, r.earliest]))
		const firstProjectSubmittedMap = new Map(firstProjectSubmittedRows.map(r => [r.userId, r.earliest]))
		const firstProjectShippedMap = new Map(firstProjectShippedRows.map(r => [r.userId, r.earliest]))

		// Build per-user maps for hour milestones
		const hourMilestoneMap = new Map<number, Map<string, Date | null>>()
		for (const row of hourMilestoneRows) {
			if (row.userId == null) continue
			if (!hourMilestoneMap.has(row.userId)) {
				hourMilestoneMap.set(row.userId, new Map())
			}
			hourMilestoneMap.get(row.userId)!.set(row.action, row.earliest)
		}

		const toCreate: Airtable.FieldSet[] = []
		const toUpdate: { id: string; fields: Airtable.FieldSet }[] = []

		for (const user of users) {
			if (!user.slackId) continue

			const authStarted = authStartedMap.get(user.id)
			const authCompleted = authCompletedMap.get(user.id)
			const tutorialCompleted = tutorialCompletedMap.get(user.id)
			const firstProjectCreated = firstProjectMap.get(user.id)
			const firstProjectSubmitted = firstProjectSubmittedMap.get(user.id)
			const firstProjectShipped = firstProjectShippedMap.get(user.id)
			const userMilestones = hourMilestoneMap.get(user.id)

			const fields: Airtable.FieldSet = {
				'slack_id': user.slackId,
				'email': user.email || '',
			}

			if (authStarted) {
				fields['Loops - scrapsAuthStarted'] = authStarted.toISOString()
			} else if (user.tutorialCompleted) {
				fields['Loops - scrapsAuthStarted'] = user.createdAt.toISOString()
			}
			if (authCompleted) {
				fields['Loops - scrapsAuthFinished'] = authCompleted.toISOString()
			} else if (user.tutorialCompleted) {
				fields['Loops - scrapsAuthFinished'] = user.createdAt.toISOString()
			}
			if (user.tutorialCompleted) {
				fields['Loops - scrapsTutorialCompleted'] = tutorialCompleted
					? tutorialCompleted.toISOString()
					: user.createdAt.toISOString()
			}
			if (firstProjectCreated) {
				fields['Loops - scrapsFirstProjectCreated'] = firstProjectCreated.toISOString()
			}
			if (firstProjectSubmitted) {
				fields['Loops - scrapsFirstProjectSubmitted'] = firstProjectSubmitted.toISOString()
			}
			if (firstProjectShipped) {
				fields['Loops - scrapsFirstProjectShipped'] = firstProjectShipped.toISOString()
			}
			if (userMilestones) {
				const oneHour = userMilestones.get('scrapsOneHour')
				const fiveHours = userMilestones.get('scrapsFiveHours')
				const tenHours = userMilestones.get('scrapsTenHours')
				const twentyHours = userMilestones.get('scrapsTwentyHours')
				if (oneHour) fields['Loops - scrapsOneHour'] = oneHour.toISOString()
				if (fiveHours) fields['Loops - scrapsFiveHours'] = fiveHours.toISOString()
				if (tenHours) fields['Loops - scrapsTenHours'] = tenHours.toISOString()
				if (twentyHours) fields['Loops - scrapsTwentyHours'] = twentyHours.toISOString()
			}

			const existingId = existingRecords.get(user.slackId)
			if (existingId) {
				toUpdate.push({ id: existingId, fields })
			} else {
				toCreate.push(fields)
			}
		}

		// Airtable API allows max 10 records per request
		for (let i = 0; i < toCreate.length; i += 10) {
			const batch = toCreate.slice(i, i + 10)
			await table.create(batch.map(fields => ({ fields })))
		}

		for (let i = 0; i < toUpdate.length; i += 10) {
			const batch = toUpdate.slice(i, i + 10)
			await table.update(batch)
		}

		console.log(`[AIRTABLE-SYNC] Users: ${toCreate.length} created, ${toUpdate.length} updated`)
	} catch (error) {
		console.error('[AIRTABLE-SYNC] Error syncing users:', error)
	}
}

async function syncAll(): Promise<void> {
	await syncProjectsToAirtable()
	await syncUsersToAirtable()
}

export function startAirtableSync(): void {
	if (syncInterval) return

	if (!config.airtableToken || !config.airtableBaseId) {
		console.log('[AIRTABLE-SYNC] Missing AIRTABLE_TOKEN or AIRTABLE_BASE_ID, sync disabled')
		return
	}

	console.log('[AIRTABLE-SYNC] Starting background sync (every 5 minutes)')

	// Run immediately on start
	syncAll()

	// Then run every 5 minutes
	syncInterval = setInterval(syncAll, SYNC_INTERVAL_MS)
}

export function stopAirtableSync(): void {
	if (syncInterval) {
		clearInterval(syncInterval)
		syncInterval = null
		console.log('[AIRTABLE-SYNC] Stopped background sync')
	}
}