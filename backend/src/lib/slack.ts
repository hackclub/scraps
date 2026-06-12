interface SlackProfile {
  avatar_hash: string;
  display_name: string;
  display_name_normalized: string;
  email: string;
  first_name: string;
  last_name: string;
  real_name: string;
  image_24: string;
  image_32: string;
  image_48: string;
  image_72: string;
  image_192: string;
  image_512: string;
}

interface SlackProfileResponse {
  ok: boolean;
  profile?: SlackProfile;
  error?: string;
}

export async function getSlackProfile(
  slackId: string,
  token: string,
): Promise<SlackProfile | null> {
  try {
    const response = await fetch(
      `https://slack.com/api/users.profile.get?user=${slackId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
      },
    );

    const data: SlackProfileResponse = await response.json();

    if (data.ok && data.profile) {
      return data.profile;
    }

    console.error("Slack API error:", data.error);
    return null;
  } catch (error) {
    console.error("Failed to fetch Slack profile:", error);
    return null;
  }
}

export function getAvatarUrl(profile: SlackProfile): string {
  return (
    profile.image_192 ||
    profile.image_512 ||
    profile.image_72 ||
    profile.image_48
  );
}

/**
 * Send a DM to a user on Slack using the bot token.
 * Uses conversations.open to get a DM channel, then chat.postMessage to send.
 */
export async function sendSlackDM(
  slackId: string,
  token: string,
  text: string,
  blocks?: unknown[],
): Promise<boolean> {
  try {
    // Open a DM channel with the user
    const openRes = await fetch("https://slack.com/api/conversations.open", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ users: slackId }),
    });

    const openData = (await openRes.json()) as {
      ok: boolean;
      channel?: { id: string };
      error?: string;
    };

    if (!openData.ok || !openData.channel) {
      console.error("Failed to open Slack DM channel:", openData.error);
      return false;
    }

    const channelId = openData.channel.id;

    // Send the message
    const payload: Record<string, unknown> = {
      channel: channelId,
      text,
      unfurl_links: false,
      unfurl_media: false,
    };
    if (blocks) {
      payload.blocks = blocks;
    }

    const msgRes = await fetch("https://slack.com/api/chat.postMessage", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const msgData = (await msgRes.json()) as { ok: boolean; error?: string };

    if (!msgData.ok) {
      console.error("Failed to send Slack DM:", msgData.error);
      return false;
    }

    return true;
  } catch (error) {
    console.error("Failed to send Slack DM:", error);
    return false;
  }
}

/**
 * Notify a user via Slack DM that their shop order has been fulfilled.
 */
export async function notifyOrderFulfilled({
  userSlackId,
  itemName,
  trackingNumber,
  token,
}: {
  userSlackId: string;
  itemName: string;
  trackingNumber?: string | null;
  token: string;
}): Promise<boolean> {
  const trackingLine = trackingNumber
    ? `\n\n*tracking number:* \`${trackingNumber}\``
    : '';

  const fallbackText = `:scraps: hey <@${userSlackId}>! your order for *${itemName}* has been fulfilled and is on its way!${trackingNumber ? ` tracking number: ${trackingNumber}` : ''} :blobhaj_party:`;

  const blocks = [
    {
      type: 'section',
      text: {
        type: 'mrkdwn',
        text: `:scraps: hey <@${userSlackId}>! :blobhaj_party:\n\nyour order for *${itemName}* has been fulfilled and is on its way!${trackingLine}`,
      },
    },
  ];

  return sendSlackDM(userSlackId, token, fallbackText, blocks);
}

/**
 * Notify a user via Slack DM that their project has been submitted for review.
 */
export async function notifyProjectSubmitted({
  userSlackId,
  projectName,
  projectId,
  frontendUrl,
  token,
}: {
  userSlackId: string;
  projectName: string;
  projectId: number;
  frontendUrl: string;
  token: string;
}): Promise<boolean> {
  const projectUrl = `${frontendUrl}/projects/${projectId}`;

  const fallbackText = `:scraps: hey <@${userSlackId}>! your scraps project ${projectName} is currently waiting for a review. a reviewer will take a look at it soon! :blobhaj_party:`;

  const blocks = [
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: `:scraps: hey <@${userSlackId}>! :blobhaj_party:\n\nyour scraps project *<${projectUrl}|${projectName}>* is currently waiting for a review. a reviewer will take a look at it soon!`,
      },
    },
    {
      type: "actions",
      elements: [
        {
          type: "button",
          text: {
            type: "plain_text",
            text: ":scraps: view your project",
            emoji: true,
          },
          url: projectUrl,
          action_id: "view_project",
        },
      ],
    },
  ];

  return sendSlackDM(userSlackId, token, fallbackText, blocks);
}

/**
 * Notify a user via Slack DM about their project review result.
 */
export async function notifyProjectReview({
  userSlackId,
  projectName,
  projectId,
  action,
  feedbackForAuthor,
  rejectionReason,
  reviewerSlackId,
  adminSlackIds,
  scrapsAwarded,
  frontendUrl,
  token,
}: {
  userSlackId: string;
  projectName: string;
  projectId: number;
  action: "approved" | "denied" | "permanently_rejected";
  feedbackForAuthor: string;
  rejectionReason?: string;
  reviewerSlackId?: string | null;
  adminSlackIds: string[];
  scrapsAwarded?: number;
  frontendUrl: string;
  token: string;
}): Promise<boolean> {
  const projectUrl = `${frontendUrl}/projects/${projectId}`;
  let fallbackText = "";
  let blocks: unknown[] = [];

  if (action === "approved") {
    fallbackText = `:scraps: hey <@${userSlackId}>! your scraps project ${projectName} has passed the review! you've been awarded ${scrapsAwarded ?? 0} scraps for your work. scraps are paid out every few days, so they may take a bit to appear in your balance. :blobhaj_party:`;

    blocks = [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `:scraps: hey <@${userSlackId}>! :blobhaj_party:\n\nyour scraps project *<${projectUrl}|${projectName}>* has passed the review! you've been awarded scraps for your work.\n\n*total scraps awarded:* ${scrapsAwarded ?? 0} scraps\n\n_scraps are paid out every few days, so they may take a bit to appear in your balance._\n\nkeep building and ship again for more scraps! :blobhaj_party:`,
        },
      },
      {
        type: "context",
        elements: [
          {
            type: "mrkdwn",
            text: `:scraps: *reviewer feedback:* ${feedbackForAuthor}`,
          },
        ],
      },
      {
        type: "actions",
        elements: [
          {
            type: "button",
            text: {
              type: "plain_text",
              text: ":scraps: view your project",
              emoji: true,
            },
            url: projectUrl,
            action_id: "view_project",
          },
        ],
      },
    ];
  } else if (action === "denied") {
    fallbackText = `:scraps: hey <@${userSlackId}>! your scraps project ${projectName} needs some changes before it can be approved for scraps. here's some feedback from your reviewer: ${feedbackForAuthor}`;

    blocks = [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `:scraps: hey <@${userSlackId}>! :scraps:\n\nyour scraps project *<${projectUrl}|${projectName}>* needs some changes before it can be approved for scraps. here's some feedback from your reviewer:\n\n> ${feedbackForAuthor}\n\ndon't worry — make the requested changes and resubmit! :scraps:`,
        },
      },
      {
        type: "actions",
        elements: [
          {
            type: "button",
            text: {
              type: "plain_text",
              text: ":scraps: view your project",
              emoji: true,
            },
            url: projectUrl,
            action_id: "view_project",
          },
        ],
      },
    ];
  } else if (action === "permanently_rejected") {
    const reasonSuffix = rejectionReason ? ` reason: ${rejectionReason}` : "";
    const reasonBlock = rejectionReason
      ? `\n\n*reason:* ${rejectionReason}`
      : "";

    fallbackText = `:scraps: hey <@${userSlackId}>! your scraps project ${projectName} has been unshipped by an admin.${reasonSuffix}`;

    blocks = [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: `:scraps: hey <@${userSlackId}>!\n\nyour scraps project *<${projectUrl}|${projectName}>* has been unshipped by an admin.${reasonBlock}`,
        },
      },
    ];
  }

  if (!fallbackText) return false;

  return sendSlackDM(userSlackId, token, fallbackText, blocks);
}
