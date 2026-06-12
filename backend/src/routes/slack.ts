import { Elysia } from 'elysia'
import { config } from '../config'
import { sendSlackDM } from '../lib/slack'

const slack = new Elysia({ prefix: '/slack' })

// Slack Events API endpoint
slack.post('/events', async ({ body, status }) => {
    const event = body as {
        type: string
        challenge?: string
        event?: {
            type: string
            channel: string
            user: string
            text: string
            ts: string
        }
    }

    // Handle Slack URL verification challenge
    if (event.type === 'url_verification') {
        return { challenge: event.challenge }
    }

    // Handle event callbacks
    if (event.type === 'event_callback' && event.event) {
        const { type, channel, user, ts } = event.event

        if (type === 'app_mention') {
            if (!config.slackBotToken) {
                console.error('No SLACK_BOT_TOKEN configured for app_mention response')
                return status(200, { ok: true })
            }

            try {
                await fetch('https://slack.com/api/chat.postMessage', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${config.slackBotToken}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        channel,
                        thread_ts: ts,
                        text: ':scraps: join scraps ---> <https://scraps.hackclub.com?utm_source=slack_mention|https://scraps.hackclub.com> :scraps:',
                        unfurl_links: false,
                        unfurl_media: false
                    })
                })
            } catch (err) {
                console.error('Failed to respond to app_mention:', err)
            }
        }
    }

    // Always return 200 to acknowledge receipt (Slack retries on non-200)
    return { ok: true }
})

export default slack
