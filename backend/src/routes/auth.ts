import { Elysia, t } from "elysia"
import {
    getAuthorizationUrl,
    exchangeCodeForTokens,
    fetchUserIdentity,
    createOrUpdateUser,
    createSession,
    deleteSession,
    getUserFromSession
} from "../lib/auth"
import { config } from "../config"
import { getUserScrapsBalance } from "../lib/scraps"
import { getNextPayoutDate } from "../lib/scraps-payout"
import { getHackatimeUser } from "../lib/hackatime-sync"
import { db } from "../db"
import { userActivityTable } from "../schemas/user-emails"
import { userBonusesTable } from "../schemas/users"
import { eq, and, sql } from "drizzle-orm"

const FRONTEND_URL = config.frontendUrl

const authRoutes = new Elysia({ prefix: "/auth" })

// POST /auth/collect-email - Store email before redirecting to auth
authRoutes.post("/collect-email", async ({ body }) => {
    const { email } = body as { email: string }
    console.log("[AUTH] Collecting email:", email)
    
    await db.insert(userActivityTable).values({ email, action: 'auth_started' })
    
    return { success: true }
}, {
    body: t.Object({
        email: t.String({ format: 'email' })
    })
})

// GET /auth/login - Redirect to Hack Club Auth
authRoutes.get("/login", ({ redirect }) => {
    console.log("[AUTH] Login initiated")
    return redirect(getAuthorizationUrl())
})

// GET /auth/callback - Handle OIDC callback
authRoutes.get("/callback", async ({ query, redirect }) => {
    console.log("[AUTH] Callback received")
    const code = query.code as string | undefined

    if (!code) {
        console.log("[AUTH] Callback error: no code provided")
        return redirect(`${FRONTEND_URL}/auth/error?reason=auth-failed`)
    }

    try {
        const tokens = await exchangeCodeForTokens(code)
        if (!tokens) {
            console.log("[AUTH] Callback error: token exchange failed")
            return redirect(`${FRONTEND_URL}/auth/error?reason=auth-failed`)
        }

        const meResponse = await fetchUserIdentity(tokens.access_token)
        if (!meResponse) {
            console.log("[AUTH] Callback error: failed to fetch user identity")
            return redirect(`${FRONTEND_URL}/auth/error?reason=auth-failed`)
        }

        const { identity } = meResponse
        console.log("[AUTH] Identity received:", {
            id: identity.id,
            email: identity.primary_email,
            slackId: identity.slack_id,
            yswsEligible: identity.ysws_eligible,
            verificationStatus: identity.verification_status
        })

        // Check verification status BEFORE creating user
        if (identity.verification_status === 'needs_submission') {
            console.log("[AUTH] User needs to verify identity")
            return redirect(`${FRONTEND_URL}/auth/error?reason=needs-verification`)
        }

        if (identity.verification_status === 'ineligible') {
            console.log("[AUTH] User is ineligible")
            return redirect(`${FRONTEND_URL}/auth/error?reason=not-eligible`)
        }

        const user = await createOrUpdateUser(identity, tokens)
        
        // Log auth completed activity
        await db.insert(userActivityTable).values({ 
            userId: user.id,
            email: identity.primary_email,
            action: 'auth_completed'
        })
        console.log("[AUTH] Logged auth_completed for:", identity.primary_email)
        
        if (user.role === 'banned') {
            console.log("[AUTH] Banned user attempted login:", { userId: user.id, username: user.username })
            return redirect('https://fraud.land')
        }

        // Check if user is banned on Hackatime
        try {
            const hackatimeUser = await getHackatimeUser(identity.primary_email, identity.slack_id)
            if (hackatimeUser?.banned) {
                console.log("[AUTH] Hackatime-banned user attempted login:", { userId: user.id, username: user.username, hackatimeUserId: hackatimeUser.user_id })
                return redirect('https://fraud.land')
            }
        } catch (e) {
            console.error("[AUTH] Failed to check Hackatime ban status:", e)
        }

        const sessionToken = await createSession(user.id)
        console.log("[AUTH] User authenticated successfully:", { userId: user.id, username: user.username })

        const cookieParts = [
            `session=${sessionToken}`,
            'HttpOnly',
            'Path=/',
            `Max-Age=${7 * 24 * 60 * 60}`,
            'SameSite=Lax'
        ]
        if (!config.isDev) cookieParts.push('Secure')

        const redirectUrl = `${FRONTEND_URL}/dashboard`
        return new Response(
            `<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=${redirectUrl}"></head><body>Redirecting...</body></html>`,
            {
                status: 200,
                headers: {
                    'Content-Type': 'text/html',
                    'Set-Cookie': cookieParts.join('; ')
                }
            }
        )
    } catch (error) {
        const msg = error instanceof Error ? error.message : "unknown"
        console.log("[AUTH] Callback error:", msg, error)
        if (msg === "not-eligible") {
            return redirect(`${FRONTEND_URL}/auth/error?reason=not-eligible`)
        }
        return redirect(`${FRONTEND_URL}/auth/error?reason=auth-failed`)
    }
})

// GET /auth/me - Get current user
authRoutes.get("/me", async ({ headers }) => {
    const user = await getUserFromSession(headers as Record<string, string>)
    console.log("[AUTH] /me check:", user ? { userId: user.id, username: user.username } : "no session")
    if (!user) return { user: null }
    if (user.role === 'banned') {
        return { user: null, banned: true }
    }

    // Auto-award tutorial bonus if tutorial is completed but bonus wasn't given
    if (user.tutorialCompleted) {
        await db.transaction(async (tx) => {
            await tx.execute(sql`SELECT 1 FROM users WHERE id = ${user.id} FOR UPDATE`)

            const existingBonus = await tx
                .select({ id: userBonusesTable.id })
                .from(userBonusesTable)
                .where(and(
                    eq(userBonusesTable.userId, user.id),
                    eq(userBonusesTable.reason, 'tutorial_completion')
                ))
                .limit(1)

            if (existingBonus.length === 0) {
                await tx.insert(userBonusesTable).values({
                    userId: user.id,
                    reason: 'tutorial_completion',
                    amount: 5
                })
                console.log("[AUTH] Auto-awarded tutorial bonus for user:", user.id)
            }
        })
    }

    const scrapsBalance = await getUserScrapsBalance(user.id)
    return {
        user: {
            id: user.id,
            username: user.username,
            email: user.email,
            avatar: user.avatar,
            slackId: user.slackId,
            scraps: scrapsBalance.balance,
            scrapsPending: scrapsBalance.pending,
            nextPayoutDate: getNextPayoutDate().toISOString(),
            role: user.role,
            tutorialCompleted: user.tutorialCompleted
        }
    }
})

// POST /auth/logout
authRoutes.post("/logout", async ({ cookie }) => {
    console.log("[AUTH] Logout requested")
    const token = cookie.session.value as string | undefined
    if (token) {
        await deleteSession(token)
        cookie.session.remove()
    }
    return { success: true }
})

export default authRoutes
