import { integer, pgTable, varchar, text, timestamp } from 'drizzle-orm/pg-core'
import { projectsTable } from './projects'
import { usersTable } from './users'

export const reviewsTable = pgTable('reviews', {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  projectId: integer('project_id').notNull().references(() => projectsTable.id),
  reviewerId: integer('reviewer_id').notNull().references(() => usersTable.id),
  
  action: varchar().notNull(), // 'approved', 'denied', 'permanently_rejected'
  feedbackForAuthor: text('feedback_for_author').notNull(),
  internalJustification: text('internal_justification'),
  
  createdAt: timestamp('created_at').defaultNow().notNull()
})
