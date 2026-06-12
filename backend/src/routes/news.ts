import { Elysia } from "elysia"
import { desc, eq } from "drizzle-orm"
import { db } from "../db"
import { newsTable } from "../schemas/news"

const news = new Elysia({
    prefix: "/news"
})

// GET /news - Get all active news items
news.get("/", async () => {
    const items = await db
        .select()
        .from(newsTable)
        .where(eq(newsTable.active, true))
        .orderBy(desc(newsTable.createdAt))

    return items
})

// GET /news/latest - Get the latest active news item
news.get("/latest", async () => {
    const items = await db
        .select()
        .from(newsTable)
        .where(eq(newsTable.active, true))
        .orderBy(desc(newsTable.createdAt))
        .limit(1)

    return items[0] || null
})

export default news
