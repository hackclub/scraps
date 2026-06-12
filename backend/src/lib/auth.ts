import { eq, and, gt, sql } from "drizzle-orm";
import { db } from "../db";
import { usersTable } from "../schemas/users";
import { sessionsTable } from "../schemas/sessions";
import { getSlackProfile, getAvatarUrl } from "./slack";
import { config } from "../config";

const HACKCLUB_AUTH_URL = "https://auth.hackclub.com";
const CLIENT_ID = config.hcauth.clientId;
const CLIENT_SECRET = config.hcauth.clientSecret;
const REDIRECT_URI = config.hcauth.redirectUri;

interface OIDCTokenResponse {
  access_token: string;
  token_type: string;
  id_token: string;
  refresh_token?: string;
}

interface HackClubAddress {
  id: string;
  first_name?: string;
  last_name?: string;
  line_1?: string;
  line_2?: string;
  city?: string;
  state?: string;
  postal_code?: string;
  country?: string;
  phone_number?: string;
  primary?: boolean;
}

interface HackClubIdentity {
  id: string;
  ysws_eligible?: boolean;
  verification_status?: string;
  primary_email?: string;
  slack_id?: string;
  phone_number?: string;
  first_name?: string;
  last_name?: string;
  birthday?: string;
  legal_first_name?: string;
  legal_last_name?: string;
  addresses?: HackClubAddress[];
}

interface HackClubMeResponse {
  identity: HackClubIdentity;
  scopes: string[];
}

export function getAuthorizationUrl(): string {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    response_type: "code",
    scope:
      "openid email name profile birthdate address verification_status slack_id basic_info",
  });
  return `${HACKCLUB_AUTH_URL}/oauth/authorize?${params.toString()}`;
}

export async function exchangeCodeForTokens(
  code: string,
): Promise<OIDCTokenResponse | null> {
  try {
    const body = new URLSearchParams({
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: REDIRECT_URI,
      code,
      grant_type: "authorization_code",
    });

    const response = await fetch(`${HACKCLUB_AUTH_URL}/oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });

    if (!response.ok) {
      console.error("Token exchange failed:", await response.text());
      return null;
    }

    return await response.json();
  } catch (error) {
    console.error("Token exchange error:", error);
    return null;
  }
}

export async function fetchUserIdentity(
  accessToken: string,
): Promise<HackClubMeResponse | null> {
  try {
    const response = await fetch(`${HACKCLUB_AUTH_URL}/api/v1/me`, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    });

    if (!response.ok) {
      console.error(
        "[AUTH] Failed to fetch user identity:",
        await response.text(),
      );
      return null;
    }

    return await response.json();
  } catch (error) {
    console.error("[AUTH] Error fetching user identity:", error);
    return null;
  }
}

export interface UserInfoResponse {
  sub: string;
  email?: string;
  given_name?: string;
  family_name?: string;
  name?: string;
  birthdate?: string;
  address?: {
    street_address?: string;
    locality?: string;
    region?: string;
    postal_code?: string;
    country?: string;
  };
  slack_id?: string;
}

export async function fetchUserInfo(
  accessToken: string,
): Promise<UserInfoResponse | null> {
  try {
    const response = await fetch(`${HACKCLUB_AUTH_URL}/oauth/userinfo`, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    });

    if (!response.ok) {
      return null;
    }

    return await response.json();
  } catch {
    return null;
  }
}

export async function createOrUpdateUser(
  identity: HackClubIdentity,
  tokens: OIDCTokenResponse,
) {
  // Only block if explicitly false (undefined means pending verification)
  if (identity.ysws_eligible === false) {
    throw new Error("not-eligible");
  }

  let username: string | null = null;
  let avatarUrl: string | null = null;

  if (identity.slack_id && config.slackBotToken) {
    const slackProfile = await getSlackProfile(
      identity.slack_id,
      config.slackBotToken,
    );
    if (slackProfile) {
      username = slackProfile.display_name || slackProfile.real_name || null;
      avatarUrl = getAvatarUrl(slackProfile);
      console.log("[AUTH] Slack profile fetched:", { username, avatarUrl });
    }
  }

  // Use UPSERT to avoid race condition with concurrent logins
  const [user] = await db
    .insert(usersTable)
    .values({
      sub: identity.id,
      slackId: identity.slack_id,
      username,
      email: identity.primary_email || "",
      avatar: avatarUrl,
      phone: identity.phone_number || null,
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token,
      idToken: tokens.id_token,
      verificationStatus: identity.verification_status,
    })
    .onConflictDoUpdate({
      target: usersTable.sub,
      set: {
        username,
        email: sql`COALESCE(${identity.primary_email || null}, ${usersTable.email})`,
        slackId: identity.slack_id,
        avatar: sql`COALESCE(${avatarUrl}, ${usersTable.avatar})`,
        phone: sql`COALESCE(${identity.phone_number || null}, ${usersTable.phone})`,
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        idToken: tokens.id_token,
        verificationStatus: identity.verification_status,
        updatedAt: new Date(),
      },
    })
    .returning();

  return user;
}

export async function createSession(userId: number): Promise<string> {
  const token = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

  await db.insert(sessionsTable).values({
    token,
    userId,
    expiresAt,
  });

  return token;
}

export async function getSessionUserId(token: string): Promise<number | null> {
  const session = await db
    .select()
    .from(sessionsTable)
    .where(
      and(
        eq(sessionsTable.token, token),
        gt(sessionsTable.expiresAt, new Date()),
      ),
    )
    .limit(1);

  if (!session[0]) return null;
  return session[0].userId;
}

export async function deleteSession(token: string): Promise<void> {
  await db.delete(sessionsTable).where(eq(sessionsTable.token, token));
}

export async function getUserFromSession(
  headers: Record<string, string | undefined>,
) {
  const cookie = headers.cookie || "";
  const match = cookie.match(/(?:^|;\s*)session=([^;]+)/);
  if (!match) return null;

  const userId = await getSessionUserId(match[1]);
  if (!userId) return null;

  const user = await db
    .select()
    .from(usersTable)
    .where(eq(usersTable.id, userId))
    .limit(1);

  return user[0] || null;
}

export async function checkUserEligibility(
  accessToken: string,
): Promise<{ yswsEligible: boolean; verificationStatus: string } | null> {
  const identity = await fetchUserIdentity(accessToken);
  if (!identity) return null;

  return {
    yswsEligible: identity.identity.ysws_eligible ?? false,
    verificationStatus: identity.identity.verification_status ?? "unknown",
  };
}
