import { db } from '../db'
import { projectActivityTable } from '../schemas/activity'
import { projectsTable } from '../schemas/projects'
import { eq, and, or, isNull, sql, inArray, min } from 'drizzle-orm'

/**
 * Get the first shipped date for each project from the project_activity table.
 * Returns a Map of projectId -> first shipped Date.
 */
export async function getProjectShippedDates(projectIds: number[]): Promise<Map<number, Date>> {
	if (projectIds.length === 0) return new Map()

	const rows = await db
		.select({
			projectId: projectActivityTable.projectId,
			firstShipped: min(projectActivityTable.createdAt)
		})
		.from(projectActivityTable)
		.where(and(
			inArray(projectActivityTable.projectId, projectIds),
			eq(projectActivityTable.action, 'project_shipped')
		))
		.groupBy(projectActivityTable.projectId)

	const map = new Map<number, Date>()
	for (const row of rows) {
		if (row.projectId != null && row.firstShipped != null) {
			map.set(row.projectId, row.firstShipped)
		}
	}
	return map
}

/**
 * Get the first shipped date for a single project from the project_activity table.
 */
export async function getProjectShippedDate(projectId: number): Promise<Date | null> {
	const map = await getProjectShippedDates([projectId])
	return map.get(projectId) ?? null
}

/**
 * Check if a project has ever been shipped (has a project_shipped activity entry).
 */
export async function hasProjectBeenShipped(projectId: number): Promise<boolean> {
	const date = await getProjectShippedDate(projectId)
	return date !== null
}

/**
 * Compute effective hours for a project by subtracting overlapping shipped hours.
 * Only deducts from projects that were shipped BEFORE the current project.
 *
 * @param project - The project to compute effective hours for
 * @param allShipped - All shipped projects (must include shippedDate from activity table)
 */
export function computeEffectiveHours(
	project: { id: number; userId: number; hours: number | null; hoursOverride: number | null; hackatimeProject: string | null; shippedDate: Date | null },
	allShipped: { id: number; userId: number; hours: number | null; hoursOverride: number | null; hackatimeProject: string | null; shippedDate: Date | null }[]
): number {
	const hours = project.hoursOverride ?? project.hours ?? 0
	if (!project.hackatimeProject || !project.shippedDate) return hours

	const hackatimeNames = project.hackatimeProject.split(',').map(n => n.trim()).filter(n => n.length > 0)
	if (hackatimeNames.length === 0) return hours

	let deducted = 0
	for (const op of allShipped) {
		if (op.id === project.id || op.userId !== project.userId) continue
		if (!op.hackatimeProject || !op.shippedDate) continue
		if (op.shippedDate >= project.shippedDate) continue
		const opNames = op.hackatimeProject.split(',').map(n => n.trim()).filter(n => n.length > 0)
		if (opNames.some(name => hackatimeNames.includes(name))) {
			deducted += op.hoursOverride ?? op.hours ?? 0
		}
	}

	return Math.max(0, hours - deducted)
}

/**
 * Compute effective hours with deduction details for a single project.
 * Fetches overlapping shipped projects from the DB and the shipped dates from activity.
 * Used in review detail pages.
 */
export async function computeEffectiveHoursForProject(
	project: { id: number; userId: number; hours: number | null; hoursOverride: number | null; hackatimeProject: string | null }
): Promise<{ overlappingProjects: { id: number; name: string; hours: number }[]; deductedHours: number; effectiveHours: number }> {
	const projectHours = project.hoursOverride ?? project.hours ?? 0
	if (!project.hackatimeProject) return { overlappingProjects: [], deductedHours: 0, effectiveHours: projectHours }

	const hackatimeNames = project.hackatimeProject.split(',').map((p: string) => p.trim()).filter((p: string) => p.length > 0)
	if (hackatimeNames.length === 0) return { overlappingProjects: [], deductedHours: 0, effectiveHours: projectHours }

	// Get this project's first shipped date
	const projectShippedDate = await getProjectShippedDate(project.id)
	const deductBeforeDate = projectShippedDate || new Date()

	// Get all shipped projects by same user (excluding this one)
	const shipped = await db
		.select({
			id: projectsTable.id,
			name: projectsTable.name,
			hours: projectsTable.hours,
			hoursOverride: projectsTable.hoursOverride,
			hackatimeProject: projectsTable.hackatimeProject
		})
		.from(projectsTable)
		.where(and(
			eq(projectsTable.userId, project.userId),
			eq(projectsTable.status, 'shipped'),
			or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)),
			sql`${projectsTable.id} != ${project.id}`
		))

	if (shipped.length === 0) return { overlappingProjects: [], deductedHours: 0, effectiveHours: projectHours }

	// Get shipped dates for all these projects
	const shippedDates = await getProjectShippedDates(shipped.map(s => s.id))

	const overlapping = shipped.filter(op => {
		if (!op.hackatimeProject) return false
		const opShippedDate = shippedDates.get(op.id)
		if (!opShippedDate || opShippedDate >= deductBeforeDate) return false
		const opNames = op.hackatimeProject.split(',').map((p: string) => p.trim()).filter((p: string) => p.length > 0)
		return opNames.some((name: string) => hackatimeNames.includes(name))
	}).map(op => ({
		id: op.id,
		name: op.name,
		hours: op.hoursOverride ?? op.hours ?? 0
	}))

	const deductedHours = overlapping.reduce((sum, op) => sum + op.hours, 0)
	return {
		overlappingProjects: overlapping,
		deductedHours,
		effectiveHours: Math.max(0, projectHours - deductedHours)
	}
}
