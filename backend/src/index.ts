import { Elysia } from 'elysia'
import { cors } from '@elysiajs/cors'
import { config } from './config'
import projects from './routes/projects'
import news from './routes/news'
import authRoutes from './routes/auth'
import user from './routes/user'
import shop from './routes/shop'
import leaderboard from './routes/leaderboard'
import hackatime from './routes/hackatime'
import upload from './routes/upload'
import admin from './routes/admin'
import slack from './routes/slack'
import { startHackatimeSync } from './lib/hackatime-sync'
import { startAirtableSync } from './lib/airtable-sync'
import { startScrapsPayout } from './lib/scraps-payout'

const api = new Elysia()
    .use(authRoutes)
    .use(projects)
    .use(news)
    .use(user)
    .use(shop)
    .use(leaderboard)
    .use(hackatime)
    .use(upload)
    .use(admin)
    .use(slack)
    .get("/", () => "if you dm @notaroomba abt finding this you may get cool stickers")

const app = new Elysia()
    .use(cors({
        origin: [config.frontendUrl],
        credentials: true
    }))
    .use(api)
    .listen(config.port)

console.log(
  `🦊 Elysia is running at ${app.server?.hostname}:${app.server?.port}`
)

// Start background syncs (skip in dev mode)
if (process.env.NODE_ENV !== 'development') {
	startHackatimeSync()
	startAirtableSync()
	startScrapsPayout()
} else {
	console.log('[STARTUP] Skipping background syncs in development mode')
}