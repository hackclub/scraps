import { Elysia } from 'elysia'
import { eq, inArray, sql, and } from 'drizzle-orm'
import { getUserFromSession, checkUserEligibility } from '../lib/auth'
import { db } from '../db'
import { usersTable, userBonusesTable } from '../schemas/users'
import { projectsTable } from '../schemas/projects'
import { shopHeartsTable, shopItemsTable, refineryOrdersTable } from '../schemas/shop'
import { userActivityTable } from '../schemas/user-emails'
import { getUserScrapsBalance } from '../lib/scraps'

const user = new Elysia({ prefix: '/user' })

user.get('/me', async ({ headers }) => {
    const userData = await getUserFromSession(headers as Record<string, string>)
    if (!userData) return { error: 'Unauthorized' }

    let yswsEligible = false
    let verificationStatus = 'unknown'

    if (userData.accessToken) {
        const eligibility = await checkUserEligibility(userData.accessToken)
        if (eligibility) {
            yswsEligible = eligibility.yswsEligible
            verificationStatus = eligibility.verificationStatus
        }
    }

    const scrapsBalance = await getUserScrapsBalance(userData.id)

    return {
        id: userData.id,
        username: userData.username,
        email: userData.email,
        avatar: userData.avatar,
        slackId: userData.slackId,
        scraps: scrapsBalance.balance,
        scrapsEarned: scrapsBalance.earned,
        scrapsSpent: scrapsBalance.spent,
        scrapsPending: scrapsBalance.pending,
        yswsEligible,
        verificationStatus,
        tutorialCompleted: userData.tutorialCompleted,
        language: userData.language
    }
})

// Update user language preference
user.put('/language', async ({ headers, body }) => {
    const userData = await getUserFromSession(headers as Record<string, string>)
    if (!userData) return { error: 'Unauthorized' }

    const { language } = body as { language: string }
    if (!language || typeof language !== 'string') return { error: 'Language is required' }

    await db.update(usersTable)
        .set({ language, updatedAt: new Date() })
        .where(eq(usersTable.id, userData.id))

    // Log language change activity
    await db.insert(userActivityTable).values({
        userId: userData.id,
        email: userData.email,
        action: 'language_changed',
        metadata: language
    })

    return { success: true }
})

user.post('/complete-tutorial', async ({ headers }) => {
    const userData = await getUserFromSession(headers as Record<string, string>)
    if (!userData) return { error: 'Unauthorized' }

    if (userData.tutorialCompleted) {
        return { success: true, alreadyCompleted: true }
    }

    const result = await db.transaction(async (tx) => {
        await tx.execute(sql`SELECT 1 FROM users WHERE id = ${userData.id} FOR UPDATE`)

        // re-check inside transaction
        const freshUser = await tx
            .select({ tutorialCompleted: usersTable.tutorialCompleted })
            .from(usersTable)
            .where(eq(usersTable.id, userData.id))
            .limit(1)

        if (freshUser[0]?.tutorialCompleted) {
            return { alreadyCompleted: true }
        }

        const existingBonus = await tx
            .select({ id: userBonusesTable.id })
            .from(userBonusesTable)
            .where(and(
                eq(userBonusesTable.userId, userData.id),
                eq(userBonusesTable.reason, 'tutorial_completion')
            ))
            .limit(1)

        if (existingBonus.length > 0) {
            await tx
                .update(usersTable)
                .set({ tutorialCompleted: true, updatedAt: new Date() })
                .where(eq(usersTable.id, userData.id))
            return { alreadyCompleted: true }
        }

        await tx
            .update(usersTable)
            .set({ tutorialCompleted: true, updatedAt: new Date() })
            .where(eq(usersTable.id, userData.id))

        await tx.insert(userBonusesTable).values({
            userId: userData.id,
            reason: 'tutorial_completion',
            amount: 5
        })

        return { bonusAwarded: 5 }
    })

    if (result.alreadyCompleted) {
        return { success: true, alreadyCompleted: true }
    }

    // Log tutorial_completed activity
    await db.insert(userActivityTable).values({
        userId: userData.id,
        email: userData.email,
        action: 'tutorial_completed'
    })

    return { success: true, bonusAwarded: result.bonusAwarded }
})

// Public profile - anyone logged in can view
user.get('/profile/:id', async ({ params, headers }) => {
    const currentUser = await getUserFromSession(headers as Record<string, string>)
    if (!currentUser) return { error: 'Unauthorized' }

    const targetUser = await db
        .select({
            id: usersTable.id,
            username: usersTable.username,
            avatar: usersTable.avatar,
            role: usersTable.role,
            createdAt: usersTable.createdAt
        })
        .from(usersTable)
        .where(eq(usersTable.id, parseInt(params.id)))
        .limit(1)

    if (!targetUser[0]) return { error: 'User not found' }

    const allProjects = await db
        .select()
        .from(projectsTable)
        .where(eq(projectsTable.userId, parseInt(params.id)))

    // Only show shipped, in_progress, and waiting_for_review projects to other users, exclude deleted
    const visibleProjects = allProjects.filter(p => !p.deleted && (p.status === 'shipped' || p.status === 'in_progress' || p.status === 'waiting_for_review'))
    const shippedCount = allProjects.filter(p => !p.deleted && p.status === 'shipped').length
    const inProgressCount = allProjects.filter(p => !p.deleted && (p.status === 'in_progress' || p.status === 'waiting_for_review')).length
    const shippedHours = allProjects
        .filter(p => !p.deleted && p.status === 'shipped')
        .reduce((sum, p) => sum + (p.hoursOverride ?? p.hours ?? 0), 0)
    const inProgressHours = allProjects
        .filter(p => !p.deleted && (p.status === 'in_progress' || p.status === 'waiting_for_review'))
        .reduce((sum, p) => sum + (p.hoursOverride ?? p.hours ?? 0), 0)
    const totalHours = Math.round((shippedHours + inProgressHours) * 10) / 10

    // Get user's hearted shop items
    const userHearts = await db
        .select({ shopItemId: shopHeartsTable.shopItemId })
        .from(shopHeartsTable)
        .where(eq(shopHeartsTable.userId, parseInt(params.id)))

    const heartedItemIds = userHearts.map(h => h.shopItemId)
    let heartedItems: { id: number; name: string; image: string; price: number }[] = []
    if (heartedItemIds.length > 0) {
        heartedItems = await db
            .select({
                id: shopItemsTable.id,
                name: shopItemsTable.name,
                image: shopItemsTable.image,
                price: shopItemsTable.price
            })
            .from(shopItemsTable)
            .where(inArray(shopItemsTable.id, heartedItemIds))
    }

    const scrapsBalance = await getUserScrapsBalance(parseInt(params.id))

    // Get user's refinery boosts
    const refinements = await db
        .select({
            shopItemId: refineryOrdersTable.shopItemId,
            itemName: shopItemsTable.name,
            itemImage: shopItemsTable.image,
            baseProbability: shopItemsTable.baseProbability,
            totalBoost: sql<number>`COALESCE(SUM(${refineryOrdersTable.boostAmount}), 0)`
        })
        .from(refineryOrdersTable)
        .innerJoin(shopItemsTable, eq(refineryOrdersTable.shopItemId, shopItemsTable.id))
        .where(eq(refineryOrdersTable.userId, parseInt(params.id)))
        .groupBy(refineryOrdersTable.shopItemId, shopItemsTable.name, shopItemsTable.image, shopItemsTable.baseProbability)
        .having(sql`COALESCE(SUM(${refineryOrdersTable.boostAmount}), 0) > 0`)

        return {
        user: {
            id: targetUser[0].id,
            username: targetUser[0].username,
            avatar: targetUser[0].avatar,
            role: targetUser[0].role,
            scraps: scrapsBalance.balance,
            scrapsPending: scrapsBalance.pending,
            createdAt: targetUser[0].createdAt
        },
        isAdmin: currentUser.role === 'admin',
        projects: visibleProjects.map(p => ({
            id: p.id,
            name: p.name,
            description: p.description,
            image: p.image,
            githubUrl: p.githubUrl,
            hours: p.hoursOverride ?? p.hours,
            status: p.status,
            createdAt: p.createdAt
        })),
        heartedItems,
        refinements: refinements.map(r => ({
            shopItemId: r.shopItemId,
            itemName: r.itemName,
            itemImage: r.itemImage,
            baseProbability: r.baseProbability,
            totalBoost: Number(r.totalBoost),
            effectiveProbability: Math.min(r.baseProbability + Number(r.totalBoost), 100)
        })),
        stats: {
            projectCount: shippedCount,
            inProgressCount,
            totalHours
        }
    }
})

export default user
