import { integer, pgTable, varchar, timestamp } from 'drizzle-orm/pg-core'
import { usersTable } from './users'

export const sessionsTable = pgTable('sessions', {
  token: varchar().primaryKey(),
  userId: integer('user_id').notNull().references(() => usersTable.id),
  expiresAt: timestamp('expires_at').notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull()
})
