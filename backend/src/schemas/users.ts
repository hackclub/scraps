import { integer, pgTable, varchar, text, timestamp, boolean } from 'drizzle-orm/pg-core'

export const usersTable = pgTable('users', {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),

  // OIDC identifiers
  sub: varchar().notNull().unique(),
  slackId: varchar('slack_id'),
  
  // Profile info (from Slack)
  username: varchar(),
  email: varchar().notNull(),
  avatar: varchar(),
  phone: varchar(),

  // OAuth tokens
  accessToken: text('access_token'),
  refreshToken: text('refresh_token'),
  idToken: text('id_token'),

  // user role
  role: varchar().notNull().default('member'),
  internalNotes: text('internal_notes'),

  // verification status from Hack Club Auth
  verificationStatus: varchar('verification_status'),

  // tutorial status
  tutorialCompleted: boolean('tutorial_completed').notNull().default(false),

  // language preference
  language: varchar().notNull().default('en'),

  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull()
})

export const userBonusesTable = pgTable('user_bonuses', {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  userId: integer('user_id').notNull().references(() => usersTable.id),
  amount: integer().notNull(),
  reason: text().notNull(),
  givenBy: integer('given_by').references(() => usersTable.id),
  createdAt: timestamp('created_at').defaultNow().notNull()
})
