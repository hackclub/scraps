import 'dotenv/config'

const isDev = process.env.NODE_ENV !== 'production'

export const config = {
	isDev,
	port: 3000,
	
	// Database (always from .env)
	databaseUrl: process.env.DATABASE_URL!,
	
	// Frontend
	frontendUrl: isDev
		? 'http://localhost:5173'
		: process.env.FRONTEND_URL!,
	
	// HackClub Auth
	hcauth: {
		clientId: process.env.HCAUTH_CLIENT_ID!,
		clientSecret: process.env.HCAUTH_CLIENT_SECRET!,
		redirectUri: isDev
			? 'http://localhost:3000/auth/callback'
			: process.env.HCAUTH_REDIRECT_URI!
	},
	
	// Slack
	slackBotToken: process.env.SLACK_BOT_TOKEN,
	
	// HCCDN
	hccdnKey: process.env.HCCDN_KEY,

	// Hackatime
	hackatimeAdminKey: process.env.HACKATIME_ADMIN,

	// Airtable
	airtableToken: process.env.AIRTABLE_TOKEN,
	airtableBaseId: process.env.AIRTABLE_BASE_ID,
	airtableProjectsTableId: process.env.AIRTABLE_PROJECTS_TABLE_ID!,
	airtableUsersTableId: process.env.AIRTABLE_USERS_TABLE_ID!,

	// Unified Airtable
	unifiedAirtableToken: process.env.UNIFIED_AIRTABLE_TOKEN,
	unifiedAirtableBaseId: process.env.UNIFIED_AIRTABLE_BASE_ID,
	unifiedAirtableTableId: process.env.UNIFIED_AIRTABLE_TABLE_ID,

	// YSWS
	fraudToken: process.env.FRAUD_TOKEN,

	// HCB
	hcbOrgSlug: 'ysws-scraps',

	// Theseus (mail.hackclub.com)
	theseusApiKey: process.env.THESEUS_API_KEY,
}
