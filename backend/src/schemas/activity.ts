import { integer, pgTable, text, timestamp } from 'drizzle-orm/pg-core'
import { usersTable } from './users'
import { projectsTable } from './projects'

export const projectActivityTable = pgTable('project_activity', {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  userId: integer('user_id').notNull().references(() => usersTable.id),
  projectId: integer('project_id').references(() => projectsTable.id),
  action: text().notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull()
})
