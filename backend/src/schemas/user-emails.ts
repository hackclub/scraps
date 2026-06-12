import { integer, pgTable, varchar, text, timestamp, serial } from 'drizzle-orm/pg-core'
import { usersTable } from './users'

export const userActivityTable = pgTable('user_activity', {
	id: serial().primaryKey(),
	userId: integer('user_id').references(() => usersTable.id),
	email: varchar(),
	action: varchar().notNull(), // 'login', 'signup', 'auth_started', 'auth_completed', 'language_changed'
	metadata: text(),
	createdAt: timestamp('created_at').defaultNow().notNull()
})
