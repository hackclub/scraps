import { integer, pgTable, varchar, text, timestamp, real } from 'drizzle-orm/pg-core'
import { usersTable } from './users'

export const projectsTable = pgTable('projects', {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  userId: integer('user_id').notNull().references(() => usersTable.id),

  name: varchar().notNull(),
  description: varchar().notNull(),
  
  // Optional fields (required for submission but not creation)
  image: text(),
  githubUrl: varchar('github_url'),
  playableUrl: varchar('playable_url'),
  hackatimeProject: varchar('hackatime_project'),
  hours: real().default(0),
  hoursOverride: real('hours_override'),
  tier: integer().notNull().default(1),
  tierOverride: integer('tier_override'),
  status: varchar().notNull().default('in_progress'),
  deleted: integer('deleted').default(0),
  scrapsAwarded: integer('scraps_awarded').notNull().default(0),
  scrapsPaidAmount: integer('scraps_paid_amount').notNull().default(0),
  scrapsPaidAt: timestamp('scraps_paid_at'),
  views: integer().notNull().default(0),

  // Update fields
  updateDescription: text('update_description'),

  // AI usage fields
  aiDescription: text('ai_description'),

  // Notes for reviewer
  reviewerNotes: text('reviewer_notes'),

  // Feedback fields (filled on submission)
  feedbackSource: text('feedback_source'),
  feedbackGood: text('feedback_good'),
  feedbackImprove: text('feedback_improve'),

  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull()
})

// last ship date
// what we can improve
// first ship date
// github repository

// under review

// current_hours
// approved_hours
