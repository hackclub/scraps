import { Elysia } from 'elysia'
import { eq, and, inArray, sql, desc, asc, or, isNull } from 'drizzle-orm'
import { db } from '../db'
import { usersTable, userBonusesTable } from '../schemas/users'
import { projectsTable } from '../schemas/projects'
import { reviewsTable } from '../schemas/reviews'
import { shopItemsTable, shopOrdersTable, shopHeartsTable, shopRollsTable, refineryOrdersTable, shopPenaltiesTable, refinerySpendingHistoryTable, lootboxesTable, lootboxItemsTable, lootboxRollsTable, lootboxHeartsTable } from '../schemas/shop'
import { newsTable } from '../schemas/news'
import { projectActivityTable } from '../schemas/activity'
import { getUserFromSession } from '../lib/auth'
import { calculateScrapsFromHours, getUserScrapsBalance } from '../lib/scraps'
import { payoutPendingScraps, getNextPayoutDate } from '../lib/scraps-payout'
import { syncSingleProject } from '../lib/hackatime-sync'
import { submitProjectToYSWS } from '../lib/ysws'
import { notifyProjectReview } from '../lib/slack'
import { config } from '../config'
import { computeEffectiveHours, getProjectShippedDates, hasProjectBeenShipped, computeEffectiveHoursForProject } from '../lib/effective-hours'

const admin = new Elysia({ prefix: '/admin' })

async function requireReviewer(headers: Record<string, string>) {
    const user = await getUserFromSession(headers)
    if (!user) return null
    if (user.role !== 'reviewer' && user.role !== 'admin') return null
    return user
}

async function requireAdmin(headers: Record<string, string>) {
    const user = await getUserFromSession(headers)
    if (!user) return null
    if (user.role !== 'admin') return null
    return user
}

// Get admin stats (info page)
admin.get('/stats', async ({ headers, status }) => {
    const user = await requireReviewer(headers as Record<string, string>)
    if (!user) {
        return status(401, { error: 'Unauthorized' })
    }

    const [usersCount, projectsCount, allProjects] = await Promise.all([
        db.select({ count: sql<number>`count(*)` }).from(usersTable),
        db.select({ count: sql<number>`count(*)` })
            .from(projectsTable)
            .where(or(eq(projectsTable.deleted, 0), sql`${projectsTable.deleted} IS NULL`)),
        db.select({
            id: projectsTable.id,
            userId: projectsTable.userId,
            hours: projectsTable.hours,
            hoursOverride: projectsTable.hoursOverride,
            hackatimeProject: projectsTable.hackatimeProject,
            status: projectsTable.status
        })
            .from(projectsTable)
            .where(or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)))
    ])

    const shipped = allProjects.filter(p => p.status === 'shipped')
    const pending = allProjects.filter(p => p.status === 'waiting_for_review')
    const inProgress = allProjects.filter(p => p.status === 'in_progress')

    // Get shipped dates from activity table for all projects
    const allProjectIds = allProjects.map(p => p.id)
    const shippedDates = await getProjectShippedDates(allProjectIds)

    // Attach shippedDate to each project for computeEffectiveHours
    const shippedWithDates = shipped.map(p => ({ ...p, shippedDate: shippedDates.get(p.id) ?? null }))
    const pendingWithDates = pending.map(p => ({ ...p, shippedDate: shippedDates.get(p.id) ?? null }))
    const inProgressWithDates = inProgress.map(p => ({ ...p, shippedDate: shippedDates.get(p.id) ?? null }))

    // Compute effective hours for each category (deducting overlapping shipped project hours)
    const totalHours = shippedWithDates.reduce((sum, p) => sum + computeEffectiveHours(p, shippedWithDates), 0)
    const pendingHours = pendingWithDates.reduce((sum, p) => sum + computeEffectiveHours(p, shippedWithDates), 0)
    const inProgressHours = inProgressWithDates.reduce((sum, p) => sum + computeEffectiveHours(p, shippedWithDates), 0)

    const totalUsers = Number(usersCount[0]?.count || 0)
    const totalProjects = Number(projectsCount[0]?.count || 0)
    const weightedGrants = Math.round(totalHours / 10 * 100) / 100
    const pendingWeightedGrants = Math.round(pendingHours / 10 * 100) / 100
    const inProgressWeightedGrants = Math.round(inProgressHours / 10 * 100) / 100

    return {
        totalUsers,
        totalProjects,
        totalHours: Math.round(totalHours * 10) / 10,
        weightedGrants,
        pendingHours: Math.round(pendingHours * 10) / 10,
        pendingWeightedGrants,
        inProgressHours: Math.round(inProgressHours * 10) / 10,
        inProgressWeightedGrants
    }
})

// Get all users (reviewers see limited info)
admin.get('/users', async ({ headers, query, status }) => {
    try {
        const user = await requireReviewer(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const page = parseInt(query.page as string) || 1
        const limit = Math.min(parseInt(query.limit as string) || 20, 100)
        const offset = (page - 1) * limit
        const search = (query.search as string)?.trim() || ''

        const searchIsNumeric = search && /^\d+$/.test(search)
        const searchCondition = search
            ? or(
                ...(searchIsNumeric ? [eq(usersTable.id, parseInt(search))] : []),
                sql`${usersTable.username} ILIKE ${'%' + search + '%'}`,
                sql`${usersTable.email} ILIKE ${'%' + search + '%'}`,
                sql`${usersTable.slackId} ILIKE ${'%' + search + '%'}`
            )
            : undefined

        // Sort ID exact matches first, then by created date
        const orderClause = searchIsNumeric
            ? [sql`CASE WHEN ${usersTable.id} = ${parseInt(search)} THEN 0 ELSE 1 END`, desc(usersTable.createdAt)]
            : [desc(usersTable.createdAt)]

        const [userIds, countResult] = await Promise.all([
            db.select({
                id: usersTable.id,
                username: usersTable.username,
                avatar: usersTable.avatar,
                slackId: usersTable.slackId,
                email: usersTable.email,
                role: usersTable.role,
                internalNotes: usersTable.internalNotes,
                createdAt: usersTable.createdAt
            }).from(usersTable).where(searchCondition).orderBy(...orderClause).limit(limit).offset(offset),
            db.select({ count: sql<number>`count(*)` }).from(usersTable).where(searchCondition)
        ])

        const total = Number(countResult[0]?.count || 0)
        
        // Get scraps balance for each user
        const usersWithScraps = await Promise.all(
            userIds.map(async (u) => {
                const balance = await getUserScrapsBalance(u.id)
                return {
                    ...u,
                    scraps: balance.balance
                }
            })
        )
        
        return {
            data: usersWithScraps.map(u => ({
                id: u.id,
                username: u.username,
                avatar: u.avatar,
                slackId: u.slackId,
                email: user.role === 'admin' ? u.email : undefined,
                scraps: u.scraps,
                role: u.role,
                internalNotes: u.internalNotes,
                createdAt: u.createdAt
            })),
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit)
            }
        }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to fetch users' })
    }
})

// Get single user details (for admin/users/[id] page)
admin.get('/users/:id', async ({ params, headers, status }) => {
    try {
        const user = await requireReviewer(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const targetUserId = parseInt(params.id)

        const targetUser = await db
            .select({
                id: usersTable.id,
                username: usersTable.username,
                avatar: usersTable.avatar,
                slackId: usersTable.slackId,
                email: usersTable.email,
                role: usersTable.role,
                internalNotes: usersTable.internalNotes,
                createdAt: usersTable.createdAt
            })
            .from(usersTable)
            .where(eq(usersTable.id, targetUserId))
            .limit(1)

        if (!targetUser[0]) return { error: 'User not found' }

        const projects = await db
            .select()
            .from(projectsTable)
            .where(eq(projectsTable.userId, targetUserId))
            .orderBy(desc(projectsTable.updatedAt))

        const projectStats = {
            total: projects.length,
            shipped: projects.filter(p => p.status === 'shipped').length,
            inProgress: projects.filter(p => p.status === 'in_progress').length,
            waitingForReview: projects.filter(p => p.status === 'waiting_for_review').length,
            rejected: projects.filter(p => p.status === 'permanently_rejected').length
        }

        const totalHours = projects.reduce((sum, p) => sum + (p.hoursOverride ?? p.hours ?? 0), 0)

        const scrapsBalance = await getUserScrapsBalance(targetUserId) || 0;

        return {
            user: {
                id: targetUser[0].id,
                username: targetUser[0].username,
                avatar: targetUser[0].avatar,
                slackId: targetUser[0].slackId,
                email: user.role === 'admin' ? targetUser[0].email : undefined,
                scraps: scrapsBalance.balance,
                role: targetUser[0].role,
                internalNotes: targetUser[0].internalNotes,
                createdAt: targetUser[0].createdAt
            },
            projects,
            stats: {
                ...projectStats,
                totalHours
            }
        }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to fetch user details' })
    }
})

// Update user role (admin only)
admin.put('/users/:id/role', async ({ params, body, headers, status }) => {
    const user = await requireAdmin(headers as Record<string, string>)
    if (!user) {
        return status(401, { error: 'Unauthorized' })
    }

    const { role } = body as { role: string }
    if (!['member', 'reviewer', 'admin', 'banned'].includes(role)) {
        return status(400, { error: 'Invalid role' })
    }

    if (user.id === parseInt(params.id)) {
        return status(400, { error: 'Cannot change your own role' })
    }

    try {
        const updated = await db
            .update(usersTable)
            .set({ role, updatedAt: new Date() })
            .where(eq(usersTable.id, parseInt(params.id)))
            .returning()

        if (!updated[0]) {
            return status(404, { error: "Not Found" })
        }
        return { success: true }
    } catch (err) {
        console.error(err);
        return status(500, { error: "Failed to update user role" })
    }
})

// Update user internal notes
admin.put('/users/:id/notes', async ({ params, body, headers, status }) => {
    const user = await requireReviewer(headers as Record<string, string>)
    if (!user) {
        return status(401, { error: 'Unauthorized' })
    }

    const { internalNotes } = body as { internalNotes: string }

    if (typeof internalNotes != "string" || internalNotes.length > 2500) {
        return status(400, { error: "Note is too long or it's malformed!" })
    }

    try {
        const updated = await db
            .update(usersTable)
            .set({ internalNotes, updatedAt: new Date() })
            .where(eq(usersTable.id, parseInt(params.id)))
            .returning()

        if (!updated[0]) {
            return status(404, { error: "Not Found" })
        }
        return { success: true }
    } catch (err) {
        console.error(err);
        return status(500, { error: "Failed to update user internal notes" })
    }
})

// Give bonus scraps to user (admin only)
admin.post('/users/:id/bonus', async ({ params, body, headers, status }) => {
    try {
        const admin = await requireAdmin(headers as Record<string, string>)
        if (!admin) {
            return status(401, { error: 'Unauthorized' })
        }

        const { amount, reason } = body as { amount: number; reason: string }

        if (!amount || typeof amount !== 'number' || !Number.isFinite(amount) || !Number.isInteger(amount) || amount === 0) {
            return status(400, { error: 'Amount is required and must be a non-zero integer' })
        }

        if (!reason || typeof reason !== 'string' || reason.trim().length === 0) {
            return status(400, { error: 'Reason is required' })
        }

        if (reason.length > 500) {
            return status(400, { error: 'Reason is too long (max 500 characters)' })
        }

        const targetUserId = parseInt(params.id)

        const targetUser = await db
            .select({ id: usersTable.id })
            .from(usersTable)
            .where(eq(usersTable.id, targetUserId))
            .limit(1)

        if (!targetUser[0]) {
            return status(404, { error: 'User not found' })
        }

        const bonus = await db
            .insert(userBonusesTable)
            .values({
                userId: targetUserId,
                amount,
                reason: reason.trim(),
                givenBy: admin.id
            })
            .returning({
                id: userBonusesTable.id,
                amount: userBonusesTable.amount,
                reason: userBonusesTable.reason,
                givenBy: userBonusesTable.givenBy,
                createdAt: userBonusesTable.createdAt
            })

        return bonus[0]
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to create user bonus' })
    }
})

// Get user bonuses (admin only)
admin.get('/users/:id/bonuses', async ({ params, headers }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const targetUserId = parseInt(params.id)

        const bonuses = await db
            .select({
                id: userBonusesTable.id,
            amount: userBonusesTable.amount,
            reason: userBonusesTable.reason,
            givenBy: userBonusesTable.givenBy,
            givenByUsername: usersTable.username,
            createdAt: userBonusesTable.createdAt
        })
        .from(userBonusesTable)
        .leftJoin(usersTable, eq(userBonusesTable.givenBy, usersTable.id))
        .where(eq(userBonusesTable.userId, targetUserId))
        .orderBy(desc(userBonusesTable.createdAt))

        return bonuses
    } catch (err) {
        console.error(err)
        return { error: 'Failed to fetch user bonuses' }
    }
})

// Get projects waiting for review
admin.get('/reviews', async ({ headers, query }) => {
    try {
        const user = await requireReviewer(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const page = parseInt(query.page as string) || 1
        const limit = Math.min(parseInt(query.limit as string) || 20, 100)
        const offset = (page - 1) * limit
        const sort = (query.sort as string) || 'oldest'

        const orderClause = sort === 'newest'
            ? desc(projectsTable.updatedAt)
            : asc(projectsTable.updatedAt)

        const [projects, countResult] = await Promise.all([
            db.select({
                id: projectsTable.id,
                userId: projectsTable.userId,
                name: projectsTable.name,
                description: projectsTable.description,
                image: projectsTable.image,
                githubUrl: projectsTable.githubUrl,
                playableUrl: projectsTable.playableUrl,
                hours: projectsTable.hours,
                hoursOverride: projectsTable.hoursOverride,
                hackatimeProject: projectsTable.hackatimeProject,
                tier: projectsTable.tier,
                tierOverride: projectsTable.tierOverride,
                status: projectsTable.status,
                deleted: projectsTable.deleted,
                scrapsAwarded: projectsTable.scrapsAwarded,
                scrapsPaidAt: projectsTable.scrapsPaidAt,
                views: projectsTable.views,
                updateDescription: projectsTable.updateDescription,
                aiDescription: projectsTable.aiDescription,
                feedbackSource: projectsTable.feedbackSource,
                feedbackGood: projectsTable.feedbackGood,
                feedbackImprove: projectsTable.feedbackImprove,
                createdAt: projectsTable.createdAt,
                updatedAt: projectsTable.updatedAt
            }).from(projectsTable)
                .where(eq(projectsTable.status, 'waiting_for_review'))
                .orderBy(orderClause)
                .limit(limit)
                .offset(offset),
            db.select({ count: sql<number>`count(*)` }).from(projectsTable)
                .where(eq(projectsTable.status, 'waiting_for_review'))
        ])

        const total = Number(countResult[0]?.count || 0)

        // Compute effective hours for each project (subtract overlapping shipped hours)
        const projectsWithEffective = await Promise.all(projects.map(async (p) => {
            const result = await computeEffectiveHoursForProject(p)
            return { ...p, effectiveHours: result.effectiveHours, deductedHours: result.deductedHours }
        }))

        return {
            data: projectsWithEffective,
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit)
            }
        }
    } catch (err) {
        console.error(err)
        return { error: 'Failed to fetch reviews' }
    }
})

// Get single project for review (with user info and previous reviews)
admin.get('/reviews/:id', async ({ params, headers }) => {
    const user = await requireReviewer(headers as Record<string, string>)
    if (!user) return { error: 'Unauthorized' }

    try {
        const project = await db
            .select()
            .from(projectsTable)
            .where(eq(projectsTable.id, parseInt(params.id)))
            .limit(1)

        if (project.length <= 0) return { error: "Project not found!" };

        const projectUser = await db
            .select({
                id: usersTable.id,
                username: usersTable.username,
                email: usersTable.email,
                avatar: usersTable.avatar,
                internalNotes: usersTable.internalNotes
            })
            .from(usersTable)
            .where(eq(usersTable.id, project[0].userId))
            .limit(1)

        const reviews = await db
            .select()
            .from(reviewsTable)
            .where(eq(reviewsTable.projectId, parseInt(params.id)))

        const reviewerIds = reviews.map(r => r.reviewerId)
        let reviewers: { id: number; username: string | null; avatar: string | null }[] = []
        if (reviewerIds.length > 0) {
            reviewers = await db
                .select({ id: usersTable.id, username: usersTable.username, avatar: usersTable.avatar })
                .from(usersTable)
                .where(inArray(usersTable.id, reviewerIds))
        }

        // Look up Hackatime user ID by email
        let hackatimeUserId: number | null = null
        if (projectUser[0]?.email) {
            try {
                const htResponse = await fetch('https://hackatime.hackclub.com/api/admin/v1/user/get_user_by_email', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${config.hackatimeAdminKey}`,
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    body: JSON.stringify({ email: projectUser[0].email })
                })
                if (htResponse.ok) {
                    const htData = await htResponse.json() as { user_id: number }
                    hackatimeUserId = htData.user_id
                }
            } catch (e) {
                console.error('[ADMIN] Failed to look up hackatime user:', e)
            }
        }

        const isAdmin = user.role === 'admin'
        // Hide pending_admin_approval from non-admin reviewers
        const maskedProject = (!isAdmin && project[0].status === 'pending_admin_approval')
            ? { ...project[0], status: 'waiting_for_review' }
            : project[0]

        // Hide approval reviews from non-admin reviewers when project is pending admin approval
        const visibleReviews = (!isAdmin && project[0].status === 'pending_admin_approval')
            ? reviews.filter(r => r.action !== 'approved')
            : reviews

        return {
            project: maskedProject,
            hackatimeUserId,
            user: projectUser[0] ? {
                id: projectUser[0].id,
                username: projectUser[0].username,
                email: projectUser[0].email,
                avatar: projectUser[0].avatar,
                internalNotes: projectUser[0].internalNotes
            } : null,
            reviews: visibleReviews.map(r => {
                const reviewer = reviewers.find(rv => rv.id === r.reviewerId)
                return {
                    ...r,
                    reviewerName: reviewer?.username,
                    reviewerAvatar: reviewer?.avatar,
                    reviewerId: r.reviewerId
                }
            }),
            ...await computeEffectiveHoursForProject(project[0])
        }
    } catch (err) {
        console.error(err);
        return { error: "Something went wrong while trying to get project" }
    }
})

// Submit a review
admin.post('/reviews/:id', async ({ params, body, headers }) => {
    try {
        const user = await requireReviewer(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const { action, feedbackForAuthor, internalJustification, hoursOverride, tierOverride, userInternalNotes } = body as {
            action: 'approved' | 'denied' | 'permanently_rejected'
            feedbackForAuthor: string
            internalJustification?: string
            hoursOverride?: number
            tierOverride?: number
            userInternalNotes?: string
        }

        if (!['approved', 'denied', 'permanently_rejected'].includes(action)) {
            return { error: 'Invalid action' }
        }

        if (!feedbackForAuthor?.trim()) {
            return { error: 'Feedback for author is required' }
        }

        const projectId = parseInt(params.id)

        // Get project to find user
        const project = await db
            .select()
            .from(projectsTable)
            .where(eq(projectsTable.id, projectId))
            .limit(1)

        if (!project[0]) return { error: 'Project not found' }

        // Validate hours override doesn't exceed project hours
        if (hoursOverride !== undefined && hoursOverride > (project[0].hours ?? 0)) {
            return { error: `Hours override (${hoursOverride}) cannot exceed project hours (${project[0].hours})` }
        }

        // Reject if project is deleted or not waiting for review
        if (project[0].deleted) {
            return { error: 'Cannot review a deleted project' }
        }
        if (project[0].status !== 'waiting_for_review') {
            return { error: 'Project is not marked for review' }
        }

        // Create review record
        await db.insert(reviewsTable).values({
            projectId,
            reviewerId: user.id,
            action,
            feedbackForAuthor,
            internalJustification
        })

        // Check for duplicate Code URL if approving
        if (action === 'approved' && project[0].githubUrl) {
            const duplicates = await db
                .select({ id: projectsTable.id })
                .from(projectsTable)
                .where(and(
                    eq(projectsTable.githubUrl, project[0].githubUrl),
                    eq(projectsTable.status, 'shipped'),
                    or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted))
                ))
                .limit(1)

            if (duplicates.length > 0) {
                return { error: 'A shipped project with this Code URL already exists. This project has been kept in review.', duplicateCodeUrl: true }
            }
        }

        // Update project status
        let newStatus = 'in_progress'
        const isAdmin = user.role === 'admin'

        switch (action) {
            case "approved":
                // If reviewer (not admin) approves, send to second-pass review
                // If admin approves, ship directly
                newStatus = isAdmin ? "shipped" : "pending_admin_approval";
                break;
            case "denied":
                newStatus = "in_progress";
                break;
            case "permanently_rejected":
                newStatus = "permanently_rejected";
                break;
            default:
                newStatus = "in_progress";
        }

        const updateData: Record<string, unknown> = {
            status: newStatus,
            updatedAt: new Date()
        }

        if (hoursOverride !== undefined) {
            updateData.hoursOverride = hoursOverride
        }

        if (tierOverride !== undefined) {
            updateData.tierOverride = tierOverride
        }

        let scrapsAwarded = 0
        if (action === 'approved') {
            const hours = hoursOverride ?? project[0].hours ?? 0
            const tier = tierOverride ?? project[0].tier ?? 1

            // Compute effective hours using activity-derived shipped dates
            const { effectiveHours } = await computeEffectiveHoursForProject({
                ...project[0],
                hoursOverride: hoursOverride ?? project[0].hoursOverride
            })
            const newScrapsAwarded = calculateScrapsFromHours(effectiveHours, tier)

            // Only set scrapsAwarded if admin is approving
            // Reviewer approvals just go to pending_admin_approval without awarding scraps yet
            if (isAdmin) {
                const previouslyShipped = await hasProjectBeenShipped(projectId)
                // If this is an update to an already-shipped project, calculate ADDITIONAL scraps
                // (difference between new award and previous award)
                if (previouslyShipped && project[0].scrapsAwarded > 0) {
                    scrapsAwarded = Math.max(0, newScrapsAwarded - project[0].scrapsAwarded)
                } else {
                    scrapsAwarded = newScrapsAwarded
                }

                updateData.scrapsAwarded = newScrapsAwarded
            }
        }

        await db
            .update(projectsTable)
            .set(updateData)
            .where(eq(projectsTable.id, projectId))

        if (action === 'approved') {
            const previouslyShipped = await hasProjectBeenShipped(projectId)

            if (scrapsAwarded > 0) {
                await db.insert(projectActivityTable).values({
                    userId: project[0].userId,
                    projectId,
                    action: previouslyShipped ? `earned ${scrapsAwarded} additional scraps (update)` : `earned ${scrapsAwarded} scraps`
                })
            }

            // Only log shipping activity if admin approved (not pending second-pass)
            if (isAdmin) {
                await db.insert(projectActivityTable).values({
                    userId: project[0].userId,
                    projectId,
                    action: previouslyShipped ? 'project_updated' : 'project_shipped'
                })
            }
        }

        // Update user internal notes if provided
        if (userInternalNotes !== undefined) {
            if (userInternalNotes.length <= 2500) {
                await db
                    .update(usersTable)
                    .set({ internalNotes: userInternalNotes, updatedAt: new Date() })
                    .where(eq(usersTable.id, project[0].userId))
            }
        }

        // Send Slack DM notification to the project author
        // Skip notification when a non-admin reviewer approves (goes to pending_admin_approval)
        // The second-pass flow sends its own notification when an admin accepts/rejects
        const shouldNotify = isAdmin || action !== 'approved'
        if (config.slackBotToken && shouldNotify) {
            try {
                // Get the project author's Slack ID
                const projectAuthor = await db
                    .select({ slackId: usersTable.slackId })
                    .from(usersTable)
                    .where(eq(usersTable.id, project[0].userId))
                    .limit(1)

                if (projectAuthor[0]?.slackId) {
                    // Get admin Slack IDs for permanently rejected projects
                    let adminSlackIds: string[] = []
                    if (action === 'permanently_rejected') {
                        const admins = await db
                            .select({ slackId: usersTable.slackId })
                            .from(usersTable)
                            .where(eq(usersTable.role, 'admin'))

                        adminSlackIds = admins
                            .map(a => a.slackId)
                            .filter((id): id is string => !!id)
                    }

                    // Get the reviewer's Slack ID
                    const reviewerSlackId = user.slackId ?? null

                    await notifyProjectReview({
                        userSlackId: projectAuthor[0].slackId,
                        projectName: project[0].name,
                        projectId,
                        action,
                        feedbackForAuthor,
                        reviewerSlackId,
                        adminSlackIds,
                        scrapsAwarded,
                        frontendUrl: config.frontendUrl,
                        token: config.slackBotToken
                    })
                }
            } catch (slackErr) {
                // Don't fail the review if Slack notification fails
                console.error('Failed to send Slack DM notification:', slackErr)
            }
        }

        return { success: true }
    } catch (err) {
        console.error(err)
        return { error: 'Failed to submit review' }
    }
})

// Second-pass review endpoints (admin only)
// Get projects pending admin approval (reviewer-approved projects)
admin.get('/second-pass', async ({ headers, query }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const page = parseInt(query.page as string) || 1
        const limit = Math.min(parseInt(query.limit as string) || 20, 100)
        const offset = (page - 1) * limit
        const sort = (query.sort as string) || 'oldest'

        const submittedAtOrderExpr = sql<Date | null>`COALESCE((
            SELECT MAX(pa.created_at)
            FROM project_activity pa
            WHERE pa.project_id = projects.id
              AND pa.action = 'project_submitted'
        ), ${projectsTable.updatedAt})`

        const [projects, countResult] = await Promise.all([
            db.select({
                id: projectsTable.id,
                userId: projectsTable.userId,
                name: projectsTable.name,
                description: projectsTable.description,
                image: projectsTable.image,
                githubUrl: projectsTable.githubUrl,
                playableUrl: projectsTable.playableUrl,
                hours: projectsTable.hours,
                hoursOverride: projectsTable.hoursOverride,
                hackatimeProject: projectsTable.hackatimeProject,
                tier: projectsTable.tier,
                tierOverride: projectsTable.tierOverride,
                status: projectsTable.status,
                deleted: projectsTable.deleted,
                scrapsAwarded: projectsTable.scrapsAwarded,
                scrapsPaidAt: projectsTable.scrapsPaidAt,
                views: projectsTable.views,
                updateDescription: projectsTable.updateDescription,
                aiDescription: projectsTable.aiDescription,
                feedbackSource: projectsTable.feedbackSource,
                feedbackGood: projectsTable.feedbackGood,
                feedbackImprove: projectsTable.feedbackImprove,
                createdAt: projectsTable.createdAt,
                updatedAt: projectsTable.updatedAt,
                submittedAt: sql<Date | null>`(
                    SELECT MAX(pa.created_at)
                    FROM project_activity pa
                    WHERE pa.project_id = projects.id
                      AND pa.action = 'project_submitted'
                )`
            }).from(projectsTable)
                .where(eq(projectsTable.status, 'pending_admin_approval'))
                .orderBy(sort === 'newest'
                    ? desc(submittedAtOrderExpr)
                    : asc(submittedAtOrderExpr))
                .limit(limit)
                .offset(offset),
            db.select({ count: sql<number>`count(*)` }).from(projectsTable)
                .where(eq(projectsTable.status, 'pending_admin_approval'))
        ])

        const total = Number(countResult[0]?.count || 0)

        // Compute effective hours for each project
        const projectsWithEffective = await Promise.all(projects.map(async (p) => {
            const result = await computeEffectiveHoursForProject(p)
            return { ...p, effectiveHours: result.effectiveHours, deductedHours: result.deductedHours }
        }))

        return {
            data: projectsWithEffective,
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit)
            }
        }
    } catch (err) {
        console.error(err)
        return { error: 'Failed to fetch second-pass reviews' }
    }
})

// Get single project for second-pass review
admin.get('/second-pass/:id', async ({ params, headers }) => {
    const user = await requireAdmin(headers as Record<string, string>)
    if (!user) return { error: 'Unauthorized' }

    try {
        const project = await db
            .select()
            .from(projectsTable)
            .where(eq(projectsTable.id, parseInt(params.id)))
            .limit(1)

        if (project.length <= 0) return { error: "Project not found!" }
        if (project[0].status !== 'pending_admin_approval') {
            return { error: "Project is not pending admin approval" }
        }

        const projectUser = await db
            .select({
                id: usersTable.id,
                username: usersTable.username,
                email: usersTable.email,
                avatar: usersTable.avatar,
                internalNotes: usersTable.internalNotes
            })
            .from(usersTable)
            .where(eq(usersTable.id, project[0].userId))
            .limit(1)

        const reviews = await db
            .select()
            .from(reviewsTable)
            .where(eq(reviewsTable.projectId, parseInt(params.id)))

        const reviewerIds = reviews.map(r => r.reviewerId)
        let reviewers: { id: number; username: string | null; avatar: string | null }[] = []
        if (reviewerIds.length > 0) {
            reviewers = await db
                .select({ id: usersTable.id, username: usersTable.username, avatar: usersTable.avatar })
                .from(usersTable)
                .where(inArray(usersTable.id, reviewerIds))
        }

        // Look up Hackatime user ID by email
        let hackatimeUserId: number | null = null
        if (projectUser[0]?.email) {
            try {
                const htResponse = await fetch('https://hackatime.hackclub.com/api/admin/v1/user/get_user_by_email', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${config.hackatimeAdminKey}`,
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    body: JSON.stringify({ email: projectUser[0].email })
                })
                if (htResponse.ok) {
                    const htData = await htResponse.json() as { user_id: number }
                    hackatimeUserId = htData.user_id
                }
            } catch (e) {
                console.error('[ADMIN] Failed to look up hackatime user:', e)
            }
        }

        // Calculate effective hours and overlapping projects
        const effectiveHoursData = await computeEffectiveHoursForProject(project[0])

        return {
            project: project[0],
            hackatimeUserId,
            user: projectUser[0] ? {
                id: projectUser[0].id,
                username: projectUser[0].username,
                email: projectUser[0].email,
                avatar: projectUser[0].avatar,
                internalNotes: projectUser[0].internalNotes
            } : null,
            reviews: reviews.map(r => {
                const reviewer = reviewers.find(rv => rv.id === r.reviewerId)
                return {
                    ...r,
                    reviewerName: reviewer?.username,
                    reviewerAvatar: reviewer?.avatar,
                    reviewerId: r.reviewerId
                }
            }),
            ...effectiveHoursData
        }
    } catch (err) {
        console.error(err)
        return { error: "Something went wrong while trying to get project" }
    }
})

// Accept or reject a second-pass review
admin.post('/second-pass/:id', async ({ params, body, headers }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const { action, feedbackForAuthor, hoursOverride } = body as {
            action: 'accept' | 'reject'
            feedbackForAuthor?: string
            hoursOverride?: number
        }

        if (!['accept', 'reject'].includes(action)) {
            return { error: 'Invalid action. Must be "accept" or "reject"' }
        }

        const projectId = parseInt(params.id)

        // Get project
        const project = await db
            .select()
            .from(projectsTable)
            .where(eq(projectsTable.id, projectId))
            .limit(1)

        if (!project[0]) return { error: 'Project not found' }
        if (project[0].status !== 'pending_admin_approval') {
            return { error: 'Project is not pending admin approval' }
        }

        if (action === 'accept') {
            // Accept the reviewer's approval and ship the project
            const tier = project[0].tierOverride ?? project[0].tier ?? 1

            // Apply hours override if provided
            if (hoursOverride !== undefined) {
                await db
                    .update(projectsTable)
                    .set({ hoursOverride })
                    .where(eq(projectsTable.id, projectId))
                project[0].hoursOverride = hoursOverride
            }

            // Compute effective hours using activity-derived shipped dates
            const { effectiveHours } = await computeEffectiveHoursForProject(project[0])
            const newScrapsAwarded = calculateScrapsFromHours(effectiveHours, tier)

            const previouslyShipped = await hasProjectBeenShipped(projectId)

            let scrapsAwarded = 0
            const updateData: Record<string, unknown> = {
                status: 'shipped',
                updatedAt: new Date()
            }

            // Calculate scraps
            if (previouslyShipped && project[0].scrapsAwarded > 0) {
                scrapsAwarded = Math.max(0, newScrapsAwarded - project[0].scrapsAwarded)
            } else {
                scrapsAwarded = newScrapsAwarded
            }

            updateData.scrapsAwarded = newScrapsAwarded

            // Update project
            await db
                .update(projectsTable)
                .set(updateData)
                .where(eq(projectsTable.id, projectId))

            // Log scraps earned
            if (scrapsAwarded > 0) {
                await db.insert(projectActivityTable).values({
                    userId: project[0].userId,
                    projectId,
                    action: previouslyShipped ? `earned ${scrapsAwarded} additional scraps (update)` : `earned ${scrapsAwarded} scraps`
                })
            }

            // Log project shipped
            await db.insert(projectActivityTable).values({
                userId: project[0].userId,
                projectId,
                action: previouslyShipped ? 'project_updated' : 'project_shipped'
            })

            // Send notification to project author
            if (config.slackBotToken) {
                try {
                    const projectAuthor = await db
                        .select({ slackId: usersTable.slackId })
                        .from(usersTable)
                        .where(eq(usersTable.id, project[0].userId))
                        .limit(1)

                    if (projectAuthor[0]?.slackId) {
                        await notifyProjectReview({
                            userSlackId: projectAuthor[0].slackId,
                            projectName: project[0].name,
                            projectId,
                            action: 'approved',
                            feedbackForAuthor: 'Your project has been approved and shipped!',
                            reviewerSlackId: user.slackId ?? null,
                            adminSlackIds: [],
                            scrapsAwarded,
                            frontendUrl: config.frontendUrl,
                            token: config.slackBotToken
                        })
                    }
                } catch (slackErr) {
                    console.error('Failed to send Slack notification:', slackErr)
                }
            }

            return { success: true, scrapsAwarded }
        } else {
            // Reject: Delete the approval review and add a denial review
            // Find and delete the approval review
            await db
                .delete(reviewsTable)
                .where(and(
                    eq(reviewsTable.projectId, projectId),
                    eq(reviewsTable.action, 'approved')
                ))

            // Add a denial review from the admin
            await db.insert(reviewsTable).values({
                projectId,
                reviewerId: user.id,
                action: 'denied',
                feedbackForAuthor: feedbackForAuthor || 'The admin has rejected the initial approval. Please make improvements and resubmit.',
                internalJustification: 'Second-pass rejection'
            })

            // Set project back to in_progress
            await db
                .update(projectsTable)
                .set({ status: 'in_progress', updatedAt: new Date() })
                .where(eq(projectsTable.id, projectId))

            // Send notification to project author
            if (config.slackBotToken) {
                try {
                    const projectAuthor = await db
                        .select({ slackId: usersTable.slackId })
                        .from(usersTable)
                        .where(eq(usersTable.id, project[0].userId))
                        .limit(1)

                    if (projectAuthor[0]?.slackId) {
                        await notifyProjectReview({
                            userSlackId: projectAuthor[0].slackId,
                            projectName: project[0].name,
                            projectId,
                            action: 'denied',
                            feedbackForAuthor: feedbackForAuthor || 'The admin has rejected the initial approval. Please make improvements and resubmit.',
                            reviewerSlackId: user.slackId ?? null,
                            adminSlackIds: [],
                            scrapsAwarded: 0,
                            frontendUrl: config.frontendUrl,
                            token: config.slackBotToken
                        })
                    }
                } catch (slackErr) {
                    console.error('Failed to send Slack notification:', slackErr)
                }
            }

            return { success: true }
        }
    } catch (err) {
        console.error(err)
        return { error: 'Failed to process second-pass review' }
    }
})

// Get pending scraps payout info (admin only)
admin.get('/scraps-payout', async ({ headers }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const pendingProjects = await db
            .select({
                id: projectsTable.id,
                name: projectsTable.name,
                image: projectsTable.image,
                scrapsAwarded: projectsTable.scrapsAwarded,
                hours: projectsTable.hours,
                hoursOverride: projectsTable.hoursOverride,
                userId: projectsTable.userId,
                status: projectsTable.status,
                createdAt: projectsTable.createdAt
            })
            .from(projectsTable)
            .where(and(
                eq(projectsTable.status, 'shipped'),
                sql`${projectsTable.scrapsAwarded} > 0`,
                isNull(projectsTable.scrapsPaidAt),
                or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted))
            ))

        // Get user info for each pending project
        const userIds = [...new Set(pendingProjects.map(p => p.userId))]
        let users: { id: number; username: string | null; avatar: string | null }[] = []
        if (userIds.length > 0) {
            users = await db
                .select({ id: usersTable.id, username: usersTable.username, avatar: usersTable.avatar })
                .from(usersTable)
                .where(inArray(usersTable.id, userIds))
        }

        const projectsWithUsers = pendingProjects.map(p => {
            const owner = users.find(u => u.id === p.userId)
            return {
                ...p,
                owner: owner ? { id: owner.id, username: owner.username, avatar: owner.avatar } : null
            }
        })

        return {
            pendingProjects: pendingProjects.length,
            pendingScraps: pendingProjects.reduce((sum, p) => sum + p.scrapsAwarded, 0),
            projects: projectsWithUsers,
            nextPayoutDate: getNextPayoutDate().toISOString()
        }
    } catch (err) {
        console.error(err)
        return { error: 'Failed to fetch payout info' }
    }
})

// Manually trigger scraps payout (admin only)
admin.post('/scraps-payout', async ({ headers }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const { paidCount, totalScraps } = await payoutPendingScraps()
        return { success: true, paidCount, totalScraps }
    } catch (err) {
        console.error(err)
        return { error: 'Failed to trigger payout' }
    }
})

// Reject a project's payout (admin only)
admin.post('/scraps-payout/reject', async ({ headers, body, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return status(401, { error: 'Unauthorized' })

        const { projectId, reason } = body as { projectId: number; reason: string }

        if (!projectId || typeof projectId !== 'number') {
            return status(400, { error: 'Project ID is required' })
        }

        if (!reason?.trim()) {
            return status(400, { error: 'A reason is required' })
        }

        // Find the project
        const project = await db
            .select({
                id: projectsTable.id,
                userId: projectsTable.userId,
                scrapsAwarded: projectsTable.scrapsAwarded,
                scrapsPaidAt: projectsTable.scrapsPaidAt,
                status: projectsTable.status,
                name: projectsTable.name
            })
            .from(projectsTable)
            .where(eq(projectsTable.id, projectId))
            .limit(1)

        if (!project[0]) {
            return status(404, { error: 'Project not found' })
        }

        if (project[0].scrapsPaidAt) {
            return status(400, { error: 'Scraps have already been paid out for this project' })
        }

        if (project[0].scrapsAwarded <= 0) {
            return status(400, { error: 'No scraps to reject for this project' })
        }

        const previousScraps = project[0].scrapsAwarded

        // Set scrapsAwarded to 0 and status back to in_progress
        await db
            .update(projectsTable)
            .set({ scrapsAwarded: 0, status: 'in_progress', updatedAt: new Date() })
            .where(eq(projectsTable.id, projectId))

        // Add a proper review record so it shows like a regular review card
        await db.insert(reviewsTable).values({
            projectId,
            reviewerId: user.id,
            action: 'scraps_unawarded',
            feedbackForAuthor: `Payout rejected (${previousScraps} scraps): ${reason.trim()}`
        })

        return { success: true, previousScraps }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to reject payout' })
    }
})

// Shop admin endpoints (admin only)
admin.get('/shop/items', async ({ headers }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return { error: 'Unauthorized' }

        const items = await db
            .select()
            .from(shopItemsTable)
            .orderBy(desc(shopItemsTable.createdAt))

        return items
    } catch (err) {
        console.error(err)
        return { error: 'Failed to fetch shop items' }
    }
})

admin.post('/shop/items', async ({ headers, body, status }) => {
    const user = await requireAdmin(headers as Record<string, string>)
    if (!user) {
        return status(401, { error: 'Unauthorized' })
    }

    const { name, image, description, price, category, count, baseProbability, baseUpgradeCost, costMultiplier, boostAmount } = body as {
        name: string
        image: string
        description: string
        price: number
        category: string
        count: number
        baseProbability?: number
        baseUpgradeCost?: number
        costMultiplier?: number
        boostAmount?: number
    }

    if (!name?.trim() || !image?.trim() || !description?.trim() || !category?.trim()) {
        return status(400, { error: 'All fields are required' })
    }

    if (typeof price !== 'number' || price < 0) {
        return status(400, { error: 'Invalid price' })
    }

    if (baseProbability !== undefined && (typeof baseProbability !== 'number' || !Number.isInteger(baseProbability) || baseProbability < 0 || baseProbability > 100)) {
        return status(400, { error: 'Base probability must be an integer between 0 and 100' })
    }

    try {
        await db
            .insert(shopItemsTable)
            .values({
                name: name.trim(),
                image: image.trim(),
                description: description.trim(),
                price,
                category: category.trim(),
                count: count || 0,
                baseProbability: baseProbability ?? 50,
                baseUpgradeCost: baseUpgradeCost ?? 10,
                costMultiplier: costMultiplier ?? 115,
                boostAmount: boostAmount ?? 1
            });

        return { success: true };
    } catch (err) {
        console.error(err);
        return status(500, { error: "Failed to create shop item" })
    }
})

admin.put('/shop/items/:id', async ({ params, headers, body, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const { name, image, description, price, category, count, baseProbability, baseUpgradeCost, costMultiplier, boostAmount } = body as {
            name?: string
            image?: string
            description?: string
            price?: number
            category?: string
            count?: number
            baseProbability?: number
            baseUpgradeCost?: number
            costMultiplier?: number
            boostAmount?: number
        }

        if (baseProbability !== undefined && (typeof baseProbability !== 'number' || !Number.isInteger(baseProbability) || baseProbability < 0 || baseProbability > 100)) {
            return status(400, { error: 'Base probability must be an integer between 0 and 100' })
        }

        const updateData: Record<string, unknown> = { updatedAt: new Date() }

        if (name !== undefined) updateData.name = name.trim()
        if (image !== undefined) updateData.image = image.trim()
        if (description !== undefined) updateData.description = description.trim()
        if (price !== undefined) updateData.price = price
        if (category !== undefined) updateData.category = category.trim()
        if (count !== undefined) updateData.count = count
        if (baseProbability !== undefined) updateData.baseProbability = baseProbability
        if (baseUpgradeCost !== undefined) updateData.baseUpgradeCost = baseUpgradeCost
        if (costMultiplier !== undefined) updateData.costMultiplier = costMultiplier
        if (boostAmount !== undefined) updateData.boostAmount = boostAmount

        const updated = await db
            .update(shopItemsTable)
            .set(updateData)
            .where(eq(shopItemsTable.id, parseInt(params.id)))
            .returning()

        if (!updated[0]) {
            return status(404, { error: 'Not found' })
        }
        return { success: true }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to update shop item' })
    }
})

admin.delete('/shop/items/:id', async ({ params, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const itemId = parseInt(params.id)

        // Delete all related records first (cascade manually)
        await db.delete(lootboxItemsTable).where(eq(lootboxItemsTable.shopItemId, itemId))
        await db.delete(shopHeartsTable).where(eq(shopHeartsTable.shopItemId, itemId))
        await db.delete(shopRollsTable).where(eq(shopRollsTable.shopItemId, itemId))
        await db.delete(refineryOrdersTable).where(eq(refineryOrdersTable.shopItemId, itemId))
        await db.delete(shopPenaltiesTable).where(eq(shopPenaltiesTable.shopItemId, itemId))
        await db.delete(shopOrdersTable).where(eq(shopOrdersTable.shopItemId, itemId))

        // Now delete the item itself
        await db.delete(shopItemsTable).where(eq(shopItemsTable.id, itemId))

        return { success: true }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to delete shop item' })
    }
})

// Lootbox admin endpoints (admin only)
admin.get('/lootboxes', async ({ headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const lootboxes = await db
            .select()
            .from(lootboxesTable)
            .orderBy(desc(lootboxesTable.createdAt))

        const lootboxIds = lootboxes.map(lb => lb.id)
        if (lootboxIds.length === 0) return []

        const items = await db
            .select({
                lootboxId: lootboxItemsTable.lootboxId,
                shopItemId: lootboxItemsTable.shopItemId,
                percentage: lootboxItemsTable.percentage,
                itemName: shopItemsTable.name,
                itemImage: shopItemsTable.image,
                itemPrice: shopItemsTable.price,
                itemCount: shopItemsTable.count
            })
            .from(lootboxItemsTable)
            .innerJoin(shopItemsTable, eq(lootboxItemsTable.shopItemId, shopItemsTable.id))
            .where(inArray(lootboxItemsTable.lootboxId, lootboxIds))

        const itemsByLootbox = new Map<number, typeof items>()
        for (const item of items) {
            const existing = itemsByLootbox.get(item.lootboxId) ?? []
            existing.push(item)
            itemsByLootbox.set(item.lootboxId, existing)
        }

        return lootboxes.map(lb => ({
            ...lb,
            items: itemsByLootbox.get(lb.id) ?? []
        }))
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to fetch lootboxes' })
    }
})

admin.post('/lootboxes', async ({ headers, body, status }) => {
    const user = await requireAdmin(headers as Record<string, string>)
    if (!user) {
        return status(401, { error: 'Unauthorized' })
    }

    const { name, image, description, price, category, items } = body as {
        name: string
        image: string
        description: string
        price: number
        category: string
        items: { shopItemId: number; percentage: number }[]
    }

    if (!name?.trim() || !image?.trim() || !description?.trim() || !category?.trim()) {
        return status(400, { error: 'All fields are required' })
    }

    if (typeof price !== 'number' || price < 1) {
        return status(400, { error: 'Invalid price' })
    }

    if (!Array.isArray(items) || items.length < 2) {
        return status(400, { error: 'At least 2 items are required' })
    }

    const totalPercentage = items.reduce((sum, i) => sum + i.percentage, 0)
    if (totalPercentage !== 100) {
        return status(400, { error: 'Percentages must sum to 100' })
    }

    for (const item of items) {
        if (!Number.isInteger(item.percentage) || item.percentage < 1) {
            return status(400, { error: 'Each item must have a percentage of at least 1' })
        }
    }

    try {
        const result = await db.transaction(async (tx) => {
            const shopItemIds = items.map(i => i.shopItemId)
            const existingItems = await tx
                .select({ id: shopItemsTable.id })
                .from(shopItemsTable)
                .where(inArray(shopItemsTable.id, shopItemIds))

            if (existingItems.length !== shopItemIds.length) {
                throw { type: 'invalid_items' }
            }

            const [lootbox] = await tx
                .insert(lootboxesTable)
                .values({
                    name: name.trim(),
                    image: image.trim(),
                    description: description.trim(),
                    price,
                    category: category.trim()
                })
                .returning()

            await tx.insert(lootboxItemsTable).values(
                items.map(i => ({
                    lootboxId: lootbox.id,
                    shopItemId: i.shopItemId,
                    percentage: i.percentage
                }))
            )

            return lootbox
        })

        return { success: true, id: result.id }
    } catch (err) {
        const e = err as { type?: string }
        if (e.type === 'invalid_items') {
            return status(400, { error: 'One or more items do not exist' })
        }
        console.error(err)
        return status(500, { error: 'Failed to create lootbox' })
    }
})

admin.put('/lootboxes/:id', async ({ params, headers, body, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const lootboxId = parseInt(params.id)
        const { name, image, description, price, category, items } = body as {
            name?: string
            image?: string
            description?: string
            price?: number
            category?: string
            items?: { shopItemId: number; percentage: number }[]
        }

        const updateData: Record<string, unknown> = { updatedAt: new Date() }
        if (name !== undefined) updateData.name = name.trim()
        if (image !== undefined) updateData.image = image.trim()
        if (description !== undefined) updateData.description = description.trim()
        if (price !== undefined) updateData.price = price
        if (category !== undefined) updateData.category = category.trim()

        await db.transaction(async (tx) => {
            const updated = await tx
                .update(lootboxesTable)
                .set(updateData)
                .where(eq(lootboxesTable.id, lootboxId))
                .returning()

            if (!updated[0]) {
                throw { type: 'not_found' }
            }

            if (items) {
                if (items.length < 2) {
                    throw { type: 'too_few_items' }
                }

                const totalPercentage = items.reduce((sum, i) => sum + i.percentage, 0)
                if (totalPercentage !== 100) {
                    throw { type: 'invalid_percentages' }
                }

                const shopItemIds = items.map(i => i.shopItemId)
                const existingItems = await tx
                    .select({ id: shopItemsTable.id })
                    .from(shopItemsTable)
                    .where(inArray(shopItemsTable.id, shopItemIds))

                if (existingItems.length !== shopItemIds.length) {
                    throw { type: 'invalid_items' }
                }

                await tx.delete(lootboxItemsTable).where(eq(lootboxItemsTable.lootboxId, lootboxId))
                await tx.insert(lootboxItemsTable).values(
                    items.map(i => ({
                        lootboxId,
                        shopItemId: i.shopItemId,
                        percentage: i.percentage
                    }))
                )
            }
        })

        return { success: true }
    } catch (err) {
        const e = err as { type?: string }
        if (e.type === 'not_found') return status(404, { error: 'Lootbox not found' })
        if (e.type === 'too_few_items') return status(400, { error: 'At least 2 items required' })
        if (e.type === 'invalid_percentages') return status(400, { error: 'Percentages must sum to 100' })
        if (e.type === 'invalid_items') return status(400, { error: 'One or more items do not exist' })
        console.error(err)
        return status(500, { error: 'Failed to update lootbox' })
    }
})

admin.delete('/lootboxes/:id', async ({ params, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const lootboxId = parseInt(params.id)

        await db.delete(lootboxItemsTable).where(eq(lootboxItemsTable.lootboxId, lootboxId))
        await db.delete(lootboxRollsTable).where(eq(lootboxRollsTable.lootboxId, lootboxId))
        await db.delete(lootboxHeartsTable).where(eq(lootboxHeartsTable.lootboxId, lootboxId))
        await db.delete(lootboxesTable).where(eq(lootboxesTable.id, lootboxId))

        return { success: true }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to delete lootbox' })
    }
})

// News admin endpoints (admin only)
admin.get('/news', async ({ headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const items = await db
            .select()
            .from(newsTable)
            .orderBy(desc(newsTable.createdAt))

        return items
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to fetch news' })
    }
})

admin.post('/news', async ({ headers, body, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const { title, content, active } = body as {
            title: string
            content: string
            active?: boolean
        }

        if (!title?.trim() || !content?.trim()) {
            return status(400, { error: 'Title and content are required' })
        }

        const inserted = await db
            .insert(newsTable)
            .values({
                title: title.trim(),
                content: content.trim(),
                active: active ?? true
            })
            .returning({
                id: newsTable.id,
                title: newsTable.title,
                content: newsTable.content,
                active: newsTable.active,
                createdAt: newsTable.createdAt,
                updatedAt: newsTable.updatedAt
            })

        return inserted[0]
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to create news' })
    }
})

admin.put('/news/:id', async ({ params, headers, body, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const { title, content, active } = body as {
            title?: string
            content?: string
            active?: boolean
        }

        const updateData: Record<string, unknown> = { updatedAt: new Date() }

        if (title !== undefined) updateData.title = title.trim()
        if (content !== undefined) updateData.content = content.trim()
        if (active !== undefined) updateData.active = active

        const updated = await db
            .update(newsTable)
            .set(updateData)
            .where(eq(newsTable.id, parseInt(params.id)))
            .returning({
                id: newsTable.id,
                title: newsTable.title,
                content: newsTable.content,
                active: newsTable.active,
                createdAt: newsTable.createdAt,
                updatedAt: newsTable.updatedAt
            })

        if (!updated[0]) {
            return status(404, { error: 'Not found' })
        }
        return updated[0]
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to update news' })
    }
})

admin.delete('/news/:id', async ({ params, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        await db
            .delete(newsTable)
            .where(eq(newsTable.id, parseInt(params.id)))

        return { success: true }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to delete news' })
    }
})

admin.get('/orders', async ({ headers, query, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const orderStatus = query.status as string | undefined

        let ordersQuery = db
            .select({
                id: shopOrdersTable.id,
                quantity: shopOrdersTable.quantity,
                pricePerItem: shopOrdersTable.pricePerItem,
                totalPrice: shopOrdersTable.totalPrice,
                status: shopOrdersTable.status,
                orderType: shopOrdersTable.orderType,
                notes: shopOrdersTable.notes,
                isFulfilled: shopOrdersTable.isFulfilled,
                shippingAddress: shopOrdersTable.shippingAddress,
                phone: shopOrdersTable.phone,
                createdAt: shopOrdersTable.createdAt,
                itemId: shopItemsTable.id,
                itemName: shopItemsTable.name,
                itemImage: shopItemsTable.image,
                userId: usersTable.id,
                username: usersTable.username
            })
            .from(shopOrdersTable)
            .innerJoin(shopItemsTable, eq(shopOrdersTable.shopItemId, shopItemsTable.id))
            .innerJoin(usersTable, eq(shopOrdersTable.userId, usersTable.id))
            .orderBy(desc(shopOrdersTable.createdAt))

        if (orderStatus) {
            ordersQuery = ordersQuery.where(eq(shopOrdersTable.status, orderStatus)) as typeof ordersQuery
        }

        return await ordersQuery
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to fetch orders' })
    }
})

admin.patch('/orders/:id', async ({ params, body, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) {
            return status(401, { error: 'Unauthorized' })
        }

        const { status: orderStatus, notes, isFulfilled } = body as { status?: string; notes?: string; isFulfilled?: boolean }

        const validStatuses = ['pending', 'processing', 'shipped', 'delivered', 'cancelled', 'deleted']
        if (orderStatus && !validStatuses.includes(orderStatus)) {
            return status(400, { error: 'Invalid status' })
        }

        const updateData: Record<string, unknown> = { updatedAt: new Date() }
        if (orderStatus) updateData.status = orderStatus
        if (notes !== undefined) updateData.notes = notes
        if (isFulfilled !== undefined) updateData.isFulfilled = isFulfilled

        const updated = await db
            .update(shopOrdersTable)
            .set(updateData)
            .where(eq(shopOrdersTable.id, parseInt(params.id)))
            .returning({
                id: shopOrdersTable.id,
                quantity: shopOrdersTable.quantity,
                pricePerItem: shopOrdersTable.pricePerItem,
                totalPrice: shopOrdersTable.totalPrice,
                status: shopOrdersTable.status,
                orderType: shopOrdersTable.orderType,
                notes: shopOrdersTable.notes,
                isFulfilled: shopOrdersTable.isFulfilled,
                shippingAddress: shopOrdersTable.shippingAddress,
                createdAt: shopOrdersTable.createdAt
            })

        if (!updated[0]) {
            return status(404, { error: 'Not found' })
        }
        return updated[0]
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to update order' })
    }
})

// Sync hours for a single project from Hackatime
admin.post('/projects/:id/sync-hours', async ({ headers, params, status }) => {
    const user = await requireReviewer(headers as Record<string, string>)
    if (!user) {
        return status(401, { error: 'Unauthorized' })
    }

    try {
        // Don't allow syncing shipped projects — their hours are frozen at approval time
        const [proj] = await db
            .select({ status: projectsTable.status })
            .from(projectsTable)
            .where(eq(projectsTable.id, parseInt(params.id)))
            .limit(1)

        if (!proj) {
            return status(404, { error: 'Project not found' })
        }

        if (proj.status === 'shipped') {
            return status(400, { error: 'Cannot sync hours for shipped projects — hours are frozen at approval time' })
        }

        const result = await syncSingleProject(parseInt(params.id))
        if (result.error) {
            return { hours: result.hours, updated: result.updated, error: result.error }
        }
        return { hours: result.hours, updated: result.updated }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to sync hours' })
    }
})

// Fix negative balances: give bonuses to all users with negative balance to bring them to 0
admin.post('/fix-negative-balances', async ({ headers, status }) => {
    const adminUser = await requireAdmin(headers as Record<string, string>)
    if (!adminUser) {
        return status(401, { error: 'Unauthorized' })
    }

    try {
        // Get all user IDs
        const allUsers = await db
            .select({ id: usersTable.id })
            .from(usersTable)

        const fixed: { userId: number; username: string | null; deficit: number }[] = []

        for (const u of allUsers) {
            const { balance } = await getUserScrapsBalance(u.id)
            if (balance < 0) {
                const deficit = Math.abs(balance)
                await db.insert(userBonusesTable).values({
                    userId: u.id,
                    amount: deficit,
                    reason: 'negative_balance_fix',
                    givenBy: adminUser.id
                })

                const userInfo = await db
                    .select({ username: usersTable.username })
                    .from(usersTable)
                    .where(eq(usersTable.id, u.id))
                    .limit(1)

                fixed.push({
                    userId: u.id,
                    username: userInfo[0]?.username ?? null,
                    deficit
                })
            }
        }

        return { success: true, fixedCount: fixed.length, fixed }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to fix negative balances' })
    }
})

// CSV export of projects under review for YSWS
admin.get('/export/review-csv', async ({ headers, status }) => {
	try {
		const user = await requireReviewer(headers as Record<string, string>)
		if (!user) {
			return status(401, { error: 'Unauthorized' })
		}

		const projects = await db
			.select({
				name: projectsTable.name,
				githubUrl: projectsTable.githubUrl,
				playableUrl: projectsTable.playableUrl,
				hackatimeProject: projectsTable.hackatimeProject,
				slackId: usersTable.slackId
			})
			.from(projectsTable)
			.innerJoin(usersTable, eq(projectsTable.userId, usersTable.id))
			.where(and(
				or(eq(projectsTable.status, 'waiting_for_review'), eq(projectsTable.status, 'pending_admin_approval')),
				or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted))
			))
			.orderBy(desc(projectsTable.updatedAt))

		const escapeCSV = (val: string | null | undefined): string => {
			if (!val) return ''
			if (val.includes(',') || val.includes('"') || val.includes('\n')) {
				return '"' + val.replace(/"/g, '""') + '"'
			}
			return val
		}

		const rows = ['name,code_link,demo_link,slack_id,hackatime_projects']
		for (const p of projects) {
			rows.push([
				escapeCSV(p.name),
				escapeCSV(p.githubUrl),
				escapeCSV(p.playableUrl),
				escapeCSV(p.slackId),
				escapeCSV(p.hackatimeProject)
			].join(','))
		}

		return new Response(rows.join('\n'), {
			headers: {
				'Content-Type': 'text/csv; charset=utf-8',
				'Content-Disposition': 'attachment; filename="scraps-review-projects.csv"'
			}
		})
	} catch (err) {
		console.error(err)
		return status(500, { error: 'Failed to export review CSV' })
	}
})

admin.get('/export/review-json', async ({ headers, status }) => {
	try {
		const user = await requireReviewer(headers as Record<string, string>)
		if (!user) {
			return status(401, { error: 'Unauthorized' })
		}

		const projects = await db
			.select({
				name: projectsTable.name,
				githubUrl: projectsTable.githubUrl,
				playableUrl: projectsTable.playableUrl,
				hackatimeProject: projectsTable.hackatimeProject,
				slackId: usersTable.slackId
			})
			.from(projectsTable)
			.innerJoin(usersTable, eq(projectsTable.userId, usersTable.id))
			.where(and(
				or(eq(projectsTable.status, 'waiting_for_review'), eq(projectsTable.status, 'pending_admin_approval')),
				or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted))
			))
			.orderBy(desc(projectsTable.updatedAt))

		return projects.map(p => {
			const hackatimeProjects = p.hackatimeProject
				? p.hackatimeProject.split(',').map((n: string) => n.trim()).filter((n: string) => n.length > 0)
				: []

			return {
				name: p.name,
				codeLink: p.githubUrl || '',
				demoLink: p.playableUrl || '',
				submitter: { slackId: p.slackId || '' },
				hackatimeProjects
			}
		})
	} catch (err) {
		console.error(err)
		return status(500, { error: 'Failed to export review JSON' })
	}
})

// Soft-delete a shop order (admin only) - marks the order as deleted
admin.post('/orders/:id/soft-delete', async ({ params, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return status(401, { error: 'Unauthorized' })

        const orderId = parseInt(params.id)

        const order = await db
            .select({ id: shopOrdersTable.id, status: shopOrdersTable.status })
            .from(shopOrdersTable)
            .where(eq(shopOrdersTable.id, orderId))
            .limit(1)

        if (!order[0]) return status(404, { error: 'Order not found' })
        if (order[0].status === 'deleted') return status(400, { error: 'Order is already deleted' })

        await db
            .update(shopOrdersTable)
            .set({ status: 'deleted', updatedAt: new Date() })
            .where(eq(shopOrdersTable.id, orderId))

        return { success: true }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to soft-delete order' })
    }
})

// Restore a soft-deleted shop order (admin only)
admin.post('/orders/:id/restore', async ({ params, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return status(401, { error: 'Unauthorized' })

        const orderId = parseInt(params.id)

        const order = await db
            .select({ id: shopOrdersTable.id, status: shopOrdersTable.status })
            .from(shopOrdersTable)
            .where(eq(shopOrdersTable.id, orderId))
            .limit(1)

        if (!order[0]) return status(404, { error: 'Order not found' })
        if (order[0].status !== 'deleted') return status(400, { error: 'Order is not deleted' })

        await db
            .update(shopOrdersTable)
            .set({ status: 'pending', updatedAt: new Date() })
            .where(eq(shopOrdersTable.id, orderId))

        return { success: true }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to restore order' })
    }
})

// Undo/refund a shop order (admin only) - must be soft-deleted first
// Adds a bonus to refund scraps, restores inventory, keeps order row for timeline
admin.delete('/orders/:id', async ({ params, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return status(401, { error: 'Unauthorized' })

        const orderId = parseInt(params.id)

        const order = await db
            .select({
                id: shopOrdersTable.id,
                status: shopOrdersTable.status,
                shopItemId: shopOrdersTable.shopItemId,
                quantity: shopOrdersTable.quantity,
                totalPrice: shopOrdersTable.totalPrice,
                userId: shopOrdersTable.userId,
                itemName: shopItemsTable.name
            })
            .from(shopOrdersTable)
            .innerJoin(shopItemsTable, eq(shopOrdersTable.shopItemId, shopItemsTable.id))
            .where(eq(shopOrdersTable.id, orderId))
            .limit(1)

        if (!order[0]) return status(404, { error: 'Order not found' })
        if (order[0].status !== 'deleted') return status(400, { error: 'Order must be marked as deleted before it can be refunded' })

        await db.transaction(async (tx) => {
            await tx.insert(userBonusesTable).values({
                userId: order[0].userId,
                amount: order[0].totalPrice,
                reason: `order refund: ${order[0].itemName} (order #${orderId})`,
                givenBy: user.id
            })

            await tx
                .update(shopItemsTable)
                .set({
                    count: sql`${shopItemsTable.count} + ${order[0].quantity}`,
                    updatedAt: new Date()
                })
                .where(eq(shopItemsTable.id, order[0].shopItemId))
        })

        return { success: true, refundedScraps: order[0].totalPrice }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to refund order' })
    }
})

// Unship a shipped project (admin only) - sets it back to in_progress and zeros scraps
admin.post('/projects/:id/unship', async ({ params, headers, body, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return status(401, { error: 'Unauthorized' })

        const projectId = parseInt(params.id)
        const { reason } = (body || {}) as { reason?: string }

        const project = await db
            .select({
                id: projectsTable.id,
                userId: projectsTable.userId,
                name: projectsTable.name,
                status: projectsTable.status,
                scrapsAwarded: projectsTable.scrapsAwarded,
                scrapsPaidAt: projectsTable.scrapsPaidAt
            })
            .from(projectsTable)
            .where(eq(projectsTable.id, projectId))
            .limit(1)

        if (!project[0]) {
            return status(404, { error: 'Project not found' })
        }

        if (project[0].status !== 'shipped') {
            return status(400, { error: 'Project is not shipped' })
        }

        const previousScraps = project[0].scrapsAwarded

        // Set project back to in_progress and zero out scraps
        await db
            .update(projectsTable)
            .set({
                status: 'in_progress',
                scrapsAwarded: 0,
                scrapsPaidAt: null,
                updatedAt: new Date()
            })
            .where(eq(projectsTable.id, projectId))

        // Add a review record so it shows in the review history
        await db.insert(reviewsTable).values({
            projectId,
            reviewerId: user.id,
            action: 'denied',
            feedbackForAuthor: reason?.trim() || 'Project has been unshipped by an admin.',
            internalJustification: `Unshipped: removed ${previousScraps} scraps`
        })

        return { success: true, previousScraps }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to unship project' })
    }
})

// Get detailed financial timeline for a user (admin only)
admin.get('/users/:id/timeline', async ({ params, headers, status }) => {
    try {
        const user = await requireAdmin(headers as Record<string, string>)
        if (!user) return status(401, { error: 'Unauthorized' })

        const targetUserId = parseInt(params.id)

        // Fetch all data sources in parallel
        const [
            paidProjects,
            bonusRows,
            shopOrders,
            refineryRows,
            refineryHistory
        ] = await Promise.all([
            db.select({
                id: projectsTable.id,
                name: projectsTable.name,
                scrapsAwarded: projectsTable.scrapsAwarded,
                scrapsPaidAt: projectsTable.scrapsPaidAt,
                status: projectsTable.status,
                createdAt: projectsTable.createdAt
            })
                .from(projectsTable)
                .where(and(
                    eq(projectsTable.userId, targetUserId),
                    sql`${projectsTable.scrapsAwarded} > 0`
                )),
            db.select({
                id: userBonusesTable.id,
                amount: userBonusesTable.amount,
                reason: userBonusesTable.reason,
                givenBy: userBonusesTable.givenBy,
                createdAt: userBonusesTable.createdAt
            })
                .from(userBonusesTable)
                .where(eq(userBonusesTable.userId, targetUserId)),
            db.select({
                id: shopOrdersTable.id,
                shopItemId: shopOrdersTable.shopItemId,
                totalPrice: shopOrdersTable.totalPrice,
                orderType: shopOrdersTable.orderType,
                status: shopOrdersTable.status,
                createdAt: shopOrdersTable.createdAt,
                itemName: shopItemsTable.name
            })
                .from(shopOrdersTable)
                .innerJoin(shopItemsTable, eq(shopOrdersTable.shopItemId, shopItemsTable.id))
                .where(eq(shopOrdersTable.userId, targetUserId)),
            db.select({
                id: refineryOrdersTable.id,
                shopItemId: refineryOrdersTable.shopItemId,
                cost: refineryOrdersTable.cost,
                boostAmount: refineryOrdersTable.boostAmount,
                createdAt: refineryOrdersTable.createdAt,
                itemName: shopItemsTable.name
            })
                .from(refineryOrdersTable)
                .innerJoin(shopItemsTable, eq(refineryOrdersTable.shopItemId, shopItemsTable.id))
                .where(eq(refineryOrdersTable.userId, targetUserId)),
            db.select({
                id: refinerySpendingHistoryTable.id,
                shopItemId: refinerySpendingHistoryTable.shopItemId,
                cost: refinerySpendingHistoryTable.cost,
                createdAt: refinerySpendingHistoryTable.createdAt,
                itemName: shopItemsTable.name
            })
                .from(refinerySpendingHistoryTable)
                .innerJoin(shopItemsTable, eq(refinerySpendingHistoryTable.shopItemId, shopItemsTable.id))
                .where(eq(refinerySpendingHistoryTable.userId, targetUserId))
        ])

        // Build a map of most recent purchase/win per item for lock detection
        const lastPurchaseByItem = new Map<number, Date>()
        for (const order of shopOrders) {
            if (order.orderType === 'purchase' || order.orderType === 'luck_win') {
                const existing = lastPurchaseByItem.get(order.shopItemId)
                const orderDate = new Date(order.createdAt)
                if (!existing || orderDate > existing) {
                    lastPurchaseByItem.set(order.shopItemId, orderDate)
                }
            }
        }

        type TimelineEvent = {
            type: string
            amount: number
            description: string
            date: string
            locked?: boolean
            itemName?: string
            paid?: boolean
            orderId?: number
        }

        const timeline: TimelineEvent[] = []

        // Earned scraps from projects
        for (const p of paidProjects) {
            timeline.push({
                type: 'earned',
                amount: p.scrapsAwarded,
                description: `project "${p.name}"`,
                date: (p.scrapsPaidAt ?? p.createdAt ?? new Date()).toISOString(),
                paid: !!p.scrapsPaidAt
            })
        }

        // Bonuses
        for (const b of bonusRows) {
            timeline.push({
                type: 'bonus',
                amount: b.amount,
                description: b.reason,
                date: b.createdAt.toISOString()
            })
        }

        // Shop orders
        for (const o of shopOrders) {
            timeline.push({
                type: `shop_${o.orderType}`,
                amount: -o.totalPrice,
                description: o.itemName,
                date: o.createdAt.toISOString(),
                itemName: o.itemName,
                orderId: o.id
            })
        }

        // Active refinery orders with lock status
        for (const r of refineryRows) {
            const lastPurchase = lastPurchaseByItem.get(r.shopItemId)
            const locked = !!lastPurchase && new Date(r.createdAt) <= lastPurchase

            timeline.push({
                type: 'refinery_upgrade',
                amount: -r.cost,
                description: `+${r.boostAmount}% boost for "${r.itemName}"`,
                date: r.createdAt.toISOString(),
                locked,
                itemName: r.itemName
            })
        }

        // Consumed refinery entries (in spending history but no matching active order)
        // When a user wins, refinery orders are deleted but spending history stays
        // When undone, both order AND history are deleted (no trace remains)
        // So: history entries without a matching active order = consumed by a win
        const orderCountByItem = new Map<number, number>()
        for (const r of refineryRows) {
            orderCountByItem.set(r.shopItemId, (orderCountByItem.get(r.shopItemId) || 0) + 1)
        }

        const historyByItem = new Map<number, typeof refineryHistory>()
        for (const h of refineryHistory) {
            const list = historyByItem.get(h.shopItemId) || []
            list.push(h)
            historyByItem.set(h.shopItemId, list)
        }

        for (const [itemId, entries] of historyByItem) {
            const activeCount = orderCountByItem.get(itemId) || 0
            // Sort oldest first - oldest entries beyond active count were consumed
            entries.sort((a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime())
            const consumedCount = Math.max(0, entries.length - activeCount)
            for (let i = 0; i < consumedCount; i++) {
                const h = entries[i]
                timeline.push({
                    type: 'refinery_consumed',
                    amount: -h.cost,
                    description: `upgrade consumed by win for "${h.itemName}"`,
                    date: h.createdAt.toISOString(),
                    itemName: h.itemName
                })
            }
        }

        // Sort newest first
        timeline.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())

        const balance = await getUserScrapsBalance(targetUserId)

        return { timeline, balance }
    } catch (err) {
        console.error(err)
        return status(500, { error: 'Failed to fetch user timeline' })
    }
})

// Sync all submitted/pending projects to YSWS
admin.post('/sync-ysws', async ({ headers, set }) => {
    const user = await requireAdmin(headers as Record<string, string>)
    if (!user) return { error: 'Unauthorized' }

    try {
        const projects = await db
            .select({
                id: projectsTable.id,
                name: projectsTable.name,
                githubUrl: projectsTable.githubUrl,
                playableUrl: projectsTable.playableUrl,
                hackatimeProject: projectsTable.hackatimeProject,
                userId: projectsTable.userId
            })
            .from(projectsTable)
            .where(and(
                or(
                    eq(projectsTable.status, 'waiting_for_review'),
                    eq(projectsTable.status, 'pending_admin_approval'),
                    eq(projectsTable.status, 'shipped')
                ),
                or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted))
            ))

        // Get emails for all project owners
        const userIds = [...new Set(projects.map(p => p.userId))]
        const users = userIds.length > 0
            ? await db
                .select({ id: usersTable.id, email: usersTable.email })
                .from(usersTable)
                .where(inArray(usersTable.id, userIds))
            : []
        const emailMap = new Map(users.map(u => [u.id, u.email]))

        let synced = 0
        let failed = 0

        for (const project of projects) {
            const email = emailMap.get(project.userId)
            if (!email) {
                failed++
                continue
            }

            try {
                await submitProjectToYSWS({
                    name: project.name,
                    githubUrl: project.githubUrl,
                    playableUrl: project.playableUrl,
                    hackatimeProject: project.hackatimeProject,
                    email
                })
                synced++
            } catch {
                failed++
            }
        }

        console.log(`[ADMIN] YSWS sync complete: ${synced} synced, ${failed} failed out of ${projects.length} projects`)
        return { synced, failed, total: projects.length }
    } catch (err) {
        console.error('[ADMIN] YSWS sync error:', err)
        return { error: 'Failed to sync projects to YSWS' }
    }
})

export default admin
