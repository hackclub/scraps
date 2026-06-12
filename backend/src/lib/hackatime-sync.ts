import { db } from '../db'
import { projectsTable } from '../schemas/projects'
import { usersTable } from '../schemas/users'
import { sessionsTable } from '../schemas/sessions'
import { userActivityTable } from '../schemas/user-emails'
import { isNotNull, and, or, eq, isNull, sql } from 'drizzle-orm'
import { config } from '../config'

const HACKATIME_API = 'https://hackatime.hackclub.com/api/admin/v1'
const SCRAPS_START_DATE = '2026-02-03'
const SYNC_INTERVAL_MS = 2 * 60 * 1000 // 2 minutes

interface HackatimeAdminProject {
	name: string
	total_heartbeats: number
	total_duration: number
	first_heartbeat: number
	last_heartbeat: number
	languages: string[]
	repo: string
	repo_mapping_id: number
	archived: boolean
}

interface HackatimeUser {
	user_id: number
	username: string
	slack_uid?: string
	banned?: boolean
	suspected?: boolean
}

interface HackatimeAdminProjectsResponse {
	user_id: number
	username: string
	total_projects: number
	projects: HackatimeAdminProject[]
}

// Cache of email -> hackatime user to avoid repeated lookups
const hackatimeUserCache = new Map<string, HackatimeUser>()
// Cache of hackatime user_id -> hackatime user
const hackatimeUserIdCache = new Map<number, HackatimeUser>()

export async function getHackatimeUser(email: string, slackId?: string | null): Promise<HackatimeUser | null> {
	const cacheKey = email || slackId || ''
	const cached = hackatimeUserCache.get(cacheKey)
	if (cached !== undefined) return cached

	try {
		let user_id: number | null = null

		// Try email lookup first
		const emailResponse = await fetch(`${HACKATIME_API}/user/get_user_by_email`, {
			method: 'POST',
			headers: {
				'Authorization': `Bearer ${config.hackatimeAdminKey}`,
				'Content-Type': 'application/json',
				'Accept': 'application/json'
			},
			body: JSON.stringify({ email })
		})
		if (emailResponse.ok) {
			const emailData = await emailResponse.json() as { user_id: number }
			user_id = parseInt(String(emailData.user_id), 10)
			if (isNaN(user_id)) user_id = null
		}

		// If email lookup failed and we have a slack ID, try fuzzy search by slack ID
		if (user_id === null && slackId) {
			const fuzzyResponse = await fetch(`${HACKATIME_API}/user/search_fuzzy`, {
				method: 'POST',
				headers: {
					'Authorization': `Bearer ${config.hackatimeAdminKey}`,
					'Content-Type': 'application/json',
					'Accept': 'application/json'
				},
				body: JSON.stringify({ query: slackId })
			})
			if (fuzzyResponse.ok) {
				const fuzzyData = await fuzzyResponse.json() as { users: { id: number }[] }
				if (fuzzyData.users?.length === 1) {
					user_id = fuzzyData.users[0].id
				}
			}
		}

		if (user_id === null) return null

		// Get full user info by user_id
		const infoResponse = await fetch(`${HACKATIME_API}/user/info?user_id=${user_id}`, {
			headers: {
				'Authorization': `Bearer ${config.hackatimeAdminKey}`,
				'Accept': 'application/json'
			}
		})
		if (!infoResponse.ok) return null

		const infoData = await infoResponse.json()
		const userObj = infoData.user ?? infoData
		const user: HackatimeUser = {
			user_id: parseInt(String(userObj.user_id), 10) || user_id,
			username: userObj.username ?? null,
			slack_uid: userObj.slack_uid || undefined,
			banned: userObj.banned || false,
			suspected: userObj.suspected || false
		}
		hackatimeUserCache.set(cacheKey, user)
		return user
	} catch {
		return null
	}
}

export async function getHackatimeUserById(userId: number): Promise<HackatimeUser | null> {
	const cached = hackatimeUserIdCache.get(userId)
	if (cached !== undefined) return cached

	try {
		const infoResponse = await fetch(`${HACKATIME_API}/user/info?user_id=${userId}`, {
			headers: {
				'Authorization': `Bearer ${config.hackatimeAdminKey}`,
				'Accept': 'application/json'
			}
		})
		if (!infoResponse.ok) return null

		const infoData = await infoResponse.json()
		const userObj = infoData.user ?? infoData
		const user: HackatimeUser = {
			user_id: parseInt(String(userObj.user_id), 10) || userId,
			username: userObj.username ?? null,
			slack_uid: userObj.slack_uid || undefined,
			banned: userObj.banned || false,
			suspected: userObj.suspected || false
		}
		hackatimeUserIdCache.set(userId, user)
		return user
	} catch {
		return null
	}
}

// Cache of user_id -> admin projects
const adminProjectsCache = new Map<number, HackatimeAdminProject[]>()

async function fetchUserProjectsByUserId(userId: number): Promise<HackatimeAdminProject[] | null> {
	if (adminProjectsCache.has(userId)) return adminProjectsCache.get(userId)!

	try {
		const params = new URLSearchParams({
			user_id: String(userId),
			start_date: SCRAPS_START_DATE
		})
		const response = await fetch(`${HACKATIME_API}/user/projects?${params}`, {
			headers: {
				'Authorization': `Bearer ${config.hackatimeAdminKey}`,
				'Accept': 'application/json'
			}
		})
		if (!response.ok) return null

		const data: HackatimeAdminProjectsResponse = await response.json()
		const projects = data.projects || []
		adminProjectsCache.set(userId, projects)
		return projects
	} catch {
		return null
	}
}

interface ParsedHackatimeEntry {
	slackId: string | null
	hackatimeUserId: number | null
	projectName: string
}

function parseHackatimeEntry(entry: string): ParsedHackatimeEntry | null {
	if (!entry) return null

	// New format: "123:projectName" (numeric hackatime user ID with colon)
	// Also handles broken "undefined:projectName" or "null:projectName" from previous bugs
	const colonIndex = entry.indexOf(':')
	if (colonIndex !== -1 && !entry.startsWith('U')) {
		const idStr = entry.substring(0, colonIndex)
		const id = parseInt(idStr, 10)
		if (!isNaN(id)) {
			return {
				slackId: null,
				hackatimeUserId: id,
				projectName: entry.substring(colonIndex + 1)
			}
		}
		// Broken prefix (e.g. "undefined:projectName") — treat as plain name needing migration
		return {
			slackId: null,
			hackatimeUserId: null,
			projectName: entry.substring(colonIndex + 1)
		}
	}

	// Old format: "U12345/projectName" (Slack ID with slash)
	const slashIndex = entry.indexOf('/')
	if (slashIndex !== -1 && entry.startsWith('U')) {
		return {
			slackId: entry.substring(0, slashIndex),
			hackatimeUserId: null,
			projectName: entry.substring(slashIndex + 1)
		}
	}

	// Plain project name (no prefix)
	return {
		slackId: null,
		hackatimeUserId: null,
		projectName: entry
	}
}

function parseHackatimeProjects(hackatimeProject: string | null): ParsedHackatimeEntry[] {
	if (!hackatimeProject) return []
	return hackatimeProject
		.split(',')
		.map(p => p.trim())
		.filter(p => p.length > 0)
		.map(p => parseHackatimeEntry(p))
		.filter((p): p is ParsedHackatimeEntry => p !== null && p.projectName.length > 0)
}

async function syncAllProjects(): Promise<void> {
	console.log('[HACKATIME-SYNC] Starting sync...')
	const startTime = Date.now()

	// Clear caches at start of each sync run
	hackatimeUserCache.clear()
	hackatimeUserIdCache.clear()
	adminProjectsCache.clear()

	try {
		// Get all projects with hackatime projects that are not deleted and not shipped, joined with user email and slackId
		const projects = await db
			.select({
				id: projectsTable.id,
				hackatimeProject: projectsTable.hackatimeProject,
				hours: projectsTable.hours,
				userId: projectsTable.userId,
				userEmail: usersTable.email,
				userSlackId: usersTable.slackId
			})
			.from(projectsTable)
			.innerJoin(usersTable, eq(projectsTable.userId, usersTable.id))
			.where(and(
				isNotNull(projectsTable.hackatimeProject),
				or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)),
				sql`${projectsTable.status} != 'shipped'`
			))

		// Group projects by user email to batch API calls
		const projectsByEmail = new Map<string, typeof projects>()
		for (const project of projects) {
			const existing = projectsByEmail.get(project.userEmail) || []
			existing.push(project)
			projectsByEmail.set(project.userEmail, existing)
		}

		let updated = 0

		let migrated = 0

		for (const [email, userProjects] of projectsByEmail) {
			const slackId = userProjects[0].userSlackId
			const hackatimeUser = await getHackatimeUser(email, slackId)

			if (hackatimeUser?.banned) {
				const userId = userProjects[0].userId
				const deleted = await db.delete(sessionsTable).where(eq(sessionsTable.userId, userId)).returning()
				if (deleted.length > 0) {
					console.log(`[HACKATIME-SYNC] Banned user ${email} (id=${userId}): deleted ${deleted.length} sessions`)
				}
				continue
			}

			for (const project of userProjects) {
				const entries = parseHackatimeProjects(project.hackatimeProject)
				if (entries.length === 0) continue

				let totalSeconds = 0
				let needsMigration = false
				const migratedEntries: string[] = []

				const entriesByUserId = new Map<number, string[]>()
				for (const entry of entries) {
					let resolvedUserId: number | null = null

					if (entry.hackatimeUserId) {
						resolvedUserId = entry.hackatimeUserId
						migratedEntries.push(`${entry.hackatimeUserId}:${entry.projectName}`)
					} else if (entry.slackId) {
						needsMigration = true
						if (hackatimeUser && typeof hackatimeUser.user_id === 'number') {
							resolvedUserId = hackatimeUser.user_id
							migratedEntries.push(`${hackatimeUser.user_id}:${entry.projectName}`)
						} else {
							migratedEntries.push(`${entry.slackId}/${entry.projectName}`)
						}
					} else {
						needsMigration = true
						if (hackatimeUser && typeof hackatimeUser.user_id === 'number') {
							resolvedUserId = hackatimeUser.user_id
							migratedEntries.push(`${hackatimeUser.user_id}:${entry.projectName}`)
						} else {
							migratedEntries.push(entry.projectName)
						}
					}

					if (resolvedUserId === null) continue

					const existing = entriesByUserId.get(resolvedUserId) || []
					existing.push(entry.projectName)
					entriesByUserId.set(resolvedUserId, existing)
				}

				for (const [userId, projectNames] of entriesByUserId) {
					const adminProjects = await fetchUserProjectsByUserId(userId)
					if (adminProjects) {
						for (const name of projectNames) {
							const found = adminProjects.find(p => p.name === name)
							if (found) {
								totalSeconds += found.total_duration
							}
						}
					}
				}

				const hours = Math.round(totalSeconds / 3600 * 10) / 10
				const newHackatimeProject = migratedEntries.join(',')

				if (hours !== project.hours || (needsMigration && newHackatimeProject !== project.hackatimeProject)) {
					const updates: { hours: number; updatedAt: Date; hackatimeProject?: string } = { hours, updatedAt: new Date() }
					if (needsMigration && newHackatimeProject !== project.hackatimeProject) {
						updates.hackatimeProject = newHackatimeProject
						migrated++
						console.log(`[HACKATIME-SYNC] Migrated project ${project.id}: "${project.hackatimeProject}" -> "${newHackatimeProject}"`)
					}
					await db
						.update(projectsTable)
						.set(updates)
						.where(eq(projectsTable.id, project.id))
					updated++
				}
			}
		}

		const elapsed = Date.now() - startTime
		console.log(`[HACKATIME-SYNC] Completed: ${projects.length} projects, ${updated} updated, ${migrated} migrated, ${elapsed}ms`)

		// Check hour milestones for all users
		await checkHourMilestones()
	} catch (error) {
		console.error('[HACKATIME-SYNC] Error:', error)
	}
}

const HOUR_MILESTONES = [
	{ hours: 1, action: 'scrapsOneHour' },
	{ hours: 5, action: 'scrapsFiveHours' },
	{ hours: 10, action: 'scrapsTenHours' },
	{ hours: 20, action: 'scrapsTwentyHours' }
] as const

async function checkHourMilestones(): Promise<void> {
	try {
		// Get total hours per user across all non-deleted projects
		const userHours = await db
			.select({
				userId: projectsTable.userId,
				totalHours: sql<number>`COALESCE(SUM(COALESCE(${projectsTable.hoursOverride}, ${projectsTable.hours})), 0)`.as('total_hours')
			})
			.from(projectsTable)
			.where(or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)))
			.groupBy(projectsTable.userId)

		// Get existing milestone activities for all users
		const existingMilestones = await db
			.select({
				userId: userActivityTable.userId,
				action: userActivityTable.action
			})
			.from(userActivityTable)
			.where(sql`${userActivityTable.action} IN ('scrapsOneHour', 'scrapsFiveHours', 'scrapsTenHours', 'scrapsTwentyHours')`)

		const existingSet = new Set(
			existingMilestones
				.filter(m => m.userId != null)
				.map(m => `${m.userId}:${m.action}`)
		)

		// Get emails for users we might need to insert for
		const userIds = userHours.map(u => u.userId)
		let userEmails: Map<number, string> = new Map()
		if (userIds.length > 0) {
			const users = await db
				.select({ id: usersTable.id, email: usersTable.email })
				.from(usersTable)
				.where(sql`${usersTable.id} IN ${userIds}`)
			userEmails = new Map(users.map(u => [u.id, u.email]))
		}

		let milestonesLogged = 0

		for (const { userId, totalHours } of userHours) {
			const hours = Number(totalHours) || 0
			for (const milestone of HOUR_MILESTONES) {
				if (hours >= milestone.hours && !existingSet.has(`${userId}:${milestone.action}`)) {
					await db.insert(userActivityTable).values({
						userId,
						email: userEmails.get(userId) || '',
						action: milestone.action
					})
					milestonesLogged++
				}
			}
		}

		if (milestonesLogged > 0) {
			console.log(`[HACKATIME-SYNC] Logged ${milestonesLogged} new hour milestones`)
		}
	} catch (error) {
		console.error('[HACKATIME-SYNC] Error checking hour milestones:', error)
	}
}

let syncInterval: ReturnType<typeof setInterval> | null = null

export async function syncSingleProject(projectId: number): Promise<{ hours: number; updated: boolean; error?: string }> {
	try {
		const [project] = await db
			.select({
				id: projectsTable.id,
				hackatimeProject: projectsTable.hackatimeProject,
				hours: projectsTable.hours,
				userId: projectsTable.userId,
				userEmail: usersTable.email,
				userSlackId: usersTable.slackId
			})
			.from(projectsTable)
			.innerJoin(usersTable, eq(projectsTable.userId, usersTable.id))
			.where(eq(projectsTable.id, projectId))
			.limit(1)

		if (!project) return { hours: 0, updated: false, error: 'Project not found' }
		if (!project.hackatimeProject) return { hours: project.hours ?? 0, updated: false, error: 'No Hackatime project linked' }

		const entries = parseHackatimeProjects(project.hackatimeProject)
		if (entries.length === 0) return { hours: project.hours ?? 0, updated: false, error: 'Invalid Hackatime project format' }

		const hackatimeUser = await getHackatimeUser(project.userEmail, project.userSlackId)

		if (hackatimeUser?.banned) {
			await db.delete(sessionsTable).where(eq(sessionsTable.userId, project.userId))
			return { hours: 0, updated: false, error: 'User is banned on Hackatime' }
		}

		let totalSeconds = 0
		const migratedEntries: string[] = []
		let needsMigration = false

		// Group entries by resolved hackatime user_id
		const entriesByUserId = new Map<number, string[]>()
		for (const entry of entries) {
			let resolvedUserId: number | null = null

			if (entry.hackatimeUserId) {
				resolvedUserId = entry.hackatimeUserId
				migratedEntries.push(`${entry.hackatimeUserId}:${entry.projectName}`)
			} else {
				needsMigration = true
				if (hackatimeUser && typeof hackatimeUser.user_id === 'number') {
					resolvedUserId = hackatimeUser.user_id
					migratedEntries.push(`${hackatimeUser.user_id}:${entry.projectName}`)
				} else {
					if (entry.slackId) {
						migratedEntries.push(`${entry.slackId}/${entry.projectName}`)
					} else {
						migratedEntries.push(entry.projectName)
					}
				}
			}

			if (resolvedUserId === null) continue

			const existing = entriesByUserId.get(resolvedUserId) || []
			existing.push(entry.projectName)
			entriesByUserId.set(resolvedUserId, existing)
		}

		if (entriesByUserId.size === 0) {
			return { hours: project.hours ?? 0, updated: false, error: 'Could not find Hackatime user' }
		}

		for (const [userId, projectNames] of entriesByUserId) {
			const adminProjects = await fetchUserProjectsByUserId(userId)
			if (adminProjects === null) continue

			for (const name of projectNames) {
				const found = adminProjects.find(p => p.name === name)
				if (found) {
					totalSeconds += found.total_duration
				}
			}
		}

		const hours = Math.round(totalSeconds / 3600 * 10) / 10
		const newHackatimeProject = migratedEntries.join(',')

		if (hours !== project.hours || (needsMigration && newHackatimeProject !== project.hackatimeProject)) {
			const updates: { hours: number; updatedAt: Date; hackatimeProject?: string } = { hours, updatedAt: new Date() }
			if (needsMigration && newHackatimeProject !== project.hackatimeProject) {
				updates.hackatimeProject = newHackatimeProject
				console.log(`[HACKATIME-SYNC] Migrated project ${projectId}: "${project.hackatimeProject}" -> "${newHackatimeProject}"`)
			}
			await db
				.update(projectsTable)
				.set(updates)
				.where(eq(projectsTable.id, projectId))
			console.log(`[HACKATIME-SYNC] Manual sync project ${projectId}: ${project.hours}h -> ${hours}h`)
			return { hours, updated: true }
		}

		return { hours, updated: false }
	} catch (error) {
		console.error(`[HACKATIME-SYNC] Error syncing project ${projectId}:`, error)
		return { hours: 0, updated: false, error: 'Sync failed' }
	}
}

export function startHackatimeSync(): void {
	if (syncInterval) return

	console.log('[HACKATIME-SYNC] Starting background sync (every 2 minutes)')

	// Run immediately on start
	syncAllProjects()

	// Then run every 2 minutes
	syncInterval = setInterval(syncAllProjects, SYNC_INTERVAL_MS)
}

export function stopHackatimeSync(): void {
	if (syncInterval) {
		clearInterval(syncInterval)
		syncInterval = null
		console.log('[HACKATIME-SYNC] Stopped background sync')
	}
}
