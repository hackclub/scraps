import { integer, pgTable, varchar, timestamp, boolean } from 'drizzle-orm/pg-core'

export const newsTable = pgTable('news', {
	id: integer().primaryKey().generatedAlwaysAsIdentity(),
	title: varchar().notNull(),
	content: varchar().notNull(),
	active: boolean().notNull().default(true),
	createdAt: timestamp('created_at').defaultNow().notNull(),
	updatedAt: timestamp('updated_at').defaultNow().notNull()
})
