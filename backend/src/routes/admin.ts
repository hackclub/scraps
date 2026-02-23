import { Elysia } from "elysia";
import { eq, ne, and, inArray, sql, desc, asc, or, isNull } from "drizzle-orm";
import { db } from "../db";
import { usersTable, userBonusesTable } from "../schemas/users";
import { projectsTable } from "../schemas/projects";
import { reviewsTable } from "../schemas/reviews";
import {
  shopItemsTable,
  shopOrdersTable,
  shopHeartsTable,
  shopRollsTable,
  refineryOrdersTable,
  shopPenaltiesTable,
  refinerySpendingHistoryTable,
} from "../schemas/shop";
import { newsTable } from "../schemas/news";
import { projectActivityTable } from "../schemas/activity";
import { getUserFromSession } from "../lib/auth";
import {
  calculateScrapsFromHours,
  getUserScrapsBalance,
  TIER_MULTIPLIERS,
  DOLLARS_PER_HOUR,
  SCRAPS_PER_DOLLAR,
  calculateRollCost,
} from "../lib/scraps";
import { payoutPendingScraps, getNextPayoutDate } from "../lib/scraps-payout";
import { syncSingleProject, getHackatimeUser } from "../lib/hackatime-sync";
import { computeItemPricing, updateShopItemPricing } from "../lib/shop-pricing";
import { submitProjectToYSWS } from "../lib/ysws";
import { notifyProjectReview } from "../lib/slack";
import { config } from "../config";
import {
  computeEffectiveHours,
  getProjectShippedDates,
  hasProjectBeenShipped,
  computeEffectiveHoursForProject,
} from "../lib/effective-hours";

const admin = new Elysia({ prefix: "/admin" });

async function requireReviewer(headers: Record<string, string>) {
  const user = await getUserFromSession(headers);
  if (!user) return null;
  if (user.role !== "reviewer" && user.role !== "admin") return null;
  return user;
}

async function requireAdmin(headers: Record<string, string>) {
  const user = await getUserFromSession(headers);
  if (!user) return null;
  if (user.role !== "admin") return null;
  return user;
}

// Get admin stats (info page)
admin.get("/stats", async ({ headers, status }) => {
  const user = await requireReviewer(headers as Record<string, string>);
  if (!user) {
    return status(401, { error: "Unauthorized" });
  }

  const [usersCount, projectsCount, allProjects] = await Promise.all([
    db.select({ count: sql<number>`count(*)` }).from(usersTable),
    db
      .select({ count: sql<number>`count(*)` })
      .from(projectsTable)
      .where(
        or(eq(projectsTable.deleted, 0), sql`${projectsTable.deleted} IS NULL`),
      ),
    db
      .select({
        id: projectsTable.id,
        userId: projectsTable.userId,
        hours: projectsTable.hours,
        hoursOverride: projectsTable.hoursOverride,
        hackatimeProject: projectsTable.hackatimeProject,
        status: projectsTable.status,
        tier: projectsTable.tier,
        tierOverride: projectsTable.tierOverride,
      })
      .from(projectsTable)
      .where(or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted))),
  ]);

  const shipped = allProjects.filter((p) => p.status === "shipped");
  const pending = allProjects.filter((p) => p.status === "waiting_for_review");
  const inProgress = allProjects.filter((p) => p.status === "in_progress");

  // Get shipped dates from activity table for all projects
  const allProjectIds = allProjects.map((p) => p.id);
  const shippedDates = await getProjectShippedDates(allProjectIds);

  // Attach shippedDate to each project for computeEffectiveHours
  const shippedWithDates = shipped.map((p) => ({
    ...p,
    shippedDate: shippedDates.get(p.id) ?? null,
  }));
  const pendingWithDates = pending.map((p) => ({
    ...p,
    shippedDate: shippedDates.get(p.id) ?? null,
  }));
  const inProgressWithDates = inProgress.map((p) => ({
    ...p,
    shippedDate: shippedDates.get(p.id) ?? null,
  }));

  // Compute effective hours for each category (deducting overlapping shipped project hours)
  const totalHours = shippedWithDates.reduce(
    (sum, p) => sum + computeEffectiveHours(p, shippedWithDates),
    0,
  );
  const pendingHours = pendingWithDates.reduce(
    (sum, p) => sum + computeEffectiveHours(p, shippedWithDates),
    0,
  );
  const inProgressHours = inProgressWithDates.reduce(
    (sum, p) => sum + computeEffectiveHours(p, shippedWithDates),
    0,
  );

  const totalUsers = Number(usersCount[0]?.count || 0);
  const totalProjects = Number(projectsCount[0]?.count || 0);
  const weightedGrants = Math.round((totalHours / 10) * 100) / 100;
  const pendingWeightedGrants = Math.round((pendingHours / 10) * 100) / 100;
  const inProgressWeightedGrants =
    Math.round((inProgressHours / 10) * 100) / 100;

  // Compute per-tier hour breakdown for shipped projects
  const tierBreakdown: Record<number, { hours: number; projects: number }> = {};
  for (const p of shippedWithDates) {
    const effectiveTier = p.tierOverride ?? p.tier ?? 1;
    const effHours = computeEffectiveHours(p, shippedWithDates);
    if (!tierBreakdown[effectiveTier]) {
      tierBreakdown[effectiveTier] = { hours: 0, projects: 0 };
    }
    tierBreakdown[effectiveTier].hours += effHours;
    tierBreakdown[effectiveTier].projects += 1;
  }

  // Build tier cost breakdown: each tier has a different $/hr rate
  const tierCostBreakdown = Object.entries(tierBreakdown)
    .map(([tierStr, data]) => {
      const tier = Number(tierStr);
      const multiplier = TIER_MULTIPLIERS[tier] ?? 1.0;
      const dollarsPerHour = DOLLARS_PER_HOUR * multiplier;
      const totalCost = data.hours * dollarsPerHour;
      return {
        tier,
        multiplier,
        dollarsPerHour: Math.round(dollarsPerHour * 100) / 100,
        hours: Math.round(data.hours * 10) / 10,
        projects: data.projects,
        totalCost: Math.round(totalCost * 100) / 100,
      };
    })
    .sort((a, b) => a.tier - b.tier);

  // Shop spending stats
  const [shopSpending, refinerySpending] = await Promise.all([
    db
      .select({
        totalSpent: sql<number>`COALESCE(SUM(${shopOrdersTable.totalPrice}), 0)`,
        purchaseSpent: sql<number>`COALESCE(SUM(CASE WHEN ${shopOrdersTable.orderType} = 'purchase' THEN ${shopOrdersTable.totalPrice} ELSE 0 END), 0)`,
        consolationSpent: sql<number>`COALESCE(SUM(CASE WHEN ${shopOrdersTable.orderType} = 'consolation' THEN ${shopOrdersTable.totalPrice} ELSE 0 END), 0)`,
        luckWinSpent: sql<number>`COALESCE(SUM(CASE WHEN ${shopOrdersTable.orderType} = 'luck_win' THEN ${shopOrdersTable.totalPrice} ELSE 0 END), 0)`,
      })
      .from(shopOrdersTable),
    db
      .select({
        totalSpent: sql<number>`COALESCE(SUM(${refinerySpendingHistoryTable.cost}), 0)`,
      })
      .from(refinerySpendingHistoryTable),
  ]);

  const shopTotal = Number(shopSpending[0]?.totalSpent) || 0;
  const shopPurchases = Number(shopSpending[0]?.purchaseSpent) || 0;
  const shopConsolations = Number(shopSpending[0]?.consolationSpent) || 0;
  const shopLuckWins = Number(shopSpending[0]?.luckWinSpent) || 0;
  const refineryTotal = Number(refinerySpending[0]?.totalSpent) || 0;
  const totalScrapsSpent = shopTotal + refineryTotal;
  const roundedTotalHours = Math.round(totalHours * 10) / 10;
  const costPerHour =
    roundedTotalHours > 0
      ? Math.round((totalScrapsSpent / roundedTotalHours) * 100) / 100
      : 0;

  const totalTierCost = tierCostBreakdown.reduce(
    (sum, t) => sum + t.totalCost,
    0,
  );
  const avgCostPerHour =
    roundedTotalHours > 0
      ? Math.round((totalTierCost / roundedTotalHours) * 100) / 100
      : 0;

  // Real dollar cost from shop fulfillment
  const [luckWinOrders, consolationCount] = await Promise.all([
    db
      .select({
        itemPrice: shopItemsTable.price,
      })
      .from(shopOrdersTable)
      .innerJoin(
        shopItemsTable,
        eq(shopOrdersTable.shopItemId, shopItemsTable.id),
      )
      .where(eq(shopOrdersTable.orderType, "luck_win")),
    db
      .select({ count: sql<number>`count(*)` })
      .from(shopOrdersTable)
      .where(eq(shopOrdersTable.orderType, "consolation")),
  ]);

  const luckWinDollarCost = luckWinOrders.reduce(
    (sum, o) => sum + o.itemPrice / SCRAPS_PER_DOLLAR,
    0,
  );
  const consolationDollarCost = Number(consolationCount[0]?.count || 0) * 2;
  const totalRealCost = luckWinDollarCost + consolationDollarCost;
  const realCostPerHour =
    roundedTotalHours > 0
      ? Math.round((totalRealCost / roundedTotalHours) * 100) / 100
      : 0;

  return {
    totalUsers,
    totalProjects,
    totalHours: roundedTotalHours,
    weightedGrants,
    pendingHours: Math.round(pendingHours * 10) / 10,
    pendingWeightedGrants,
    inProgressHours: Math.round(inProgressHours * 10) / 10,
    inProgressWeightedGrants,
    shopStats: {
      totalScrapsSpent,
      shopPurchases,
      shopConsolations,
      shopLuckWins,
      refineryUpgrades: refineryTotal,
      costPerHour,
    },
    tierCostBreakdown,
    totalTierCost: Math.round(totalTierCost * 100) / 100,
    avgCostPerHour,
    shopRealCost: {
      luckWinItemsCost: Math.round(luckWinDollarCost * 100) / 100,
      luckWinCount: luckWinOrders.length,
      consolationShippingCost: Math.round(consolationDollarCost * 100) / 100,
      consolationCount: Number(consolationCount[0]?.count || 0),
      totalRealCost: Math.round(totalRealCost * 100) / 100,
      realCostPerHour,
    },
  };
});

// Get all users (reviewers see limited info)
admin.get("/users", async ({ headers, query, status }) => {
  try {
    const user = await requireReviewer(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const page = parseInt(query.page as string) || 1;
    const limit = Math.min(parseInt(query.limit as string) || 20, 100);
    const offset = (page - 1) * limit;
    const search = (query.search as string)?.trim() || "";

    const searchIsNumeric = search && /^\d+$/.test(search);
    const searchCondition = search
      ? or(
          ...(searchIsNumeric ? [eq(usersTable.id, parseInt(search))] : []),
          sql`${usersTable.username} ILIKE ${"%" + search + "%"}`,
          sql`${usersTable.email} ILIKE ${"%" + search + "%"}`,
          sql`${usersTable.slackId} ILIKE ${"%" + search + "%"}`,
        )
      : undefined;

    // Sort ID exact matches first, then by created date
    const orderClause = searchIsNumeric
      ? [
          sql`CASE WHEN ${usersTable.id} = ${parseInt(search)} THEN 0 ELSE 1 END`,
          desc(usersTable.createdAt),
        ]
      : [desc(usersTable.createdAt)];

    const [userIds, countResult] = await Promise.all([
      db
        .select({
          id: usersTable.id,
          username: usersTable.username,
          avatar: usersTable.avatar,
          slackId: usersTable.slackId,
          email: usersTable.email,
          role: usersTable.role,
          internalNotes: usersTable.internalNotes,
          createdAt: usersTable.createdAt,
        })
        .from(usersTable)
        .where(searchCondition)
        .orderBy(...orderClause)
        .limit(limit)
        .offset(offset),
      db
        .select({ count: sql<number>`count(*)` })
        .from(usersTable)
        .where(searchCondition),
    ]);

    const total = Number(countResult[0]?.count || 0);

    // Get scraps balance for each user
    const usersWithScraps = await Promise.all(
      userIds.map(async (u) => {
        const balance = await getUserScrapsBalance(u.id);
        return {
          ...u,
          scraps: balance.balance,
        };
      }),
    );

    return {
      data: usersWithScraps.map((u) => ({
        id: u.id,
        username: u.username,
        avatar: u.avatar,
        slackId: u.slackId,
        email: user.role === "admin" ? u.email : undefined,
        scraps: u.scraps,
        role: u.role,
        internalNotes: u.internalNotes,
        createdAt: u.createdAt,
      })),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to fetch users" });
  }
});

// Get single user details (for admin/users/[id] page)
admin.get("/users/:id", async ({ params, headers, status }) => {
  try {
    const user = await requireReviewer(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const targetUserId = parseInt(params.id);

    const targetUser = await db
      .select({
        id: usersTable.id,
        username: usersTable.username,
        avatar: usersTable.avatar,
        slackId: usersTable.slackId,
        email: usersTable.email,
        role: usersTable.role,
        internalNotes: usersTable.internalNotes,
        createdAt: usersTable.createdAt,
      })
      .from(usersTable)
      .where(eq(usersTable.id, targetUserId))
      .limit(1);

    if (!targetUser[0]) return { error: "User not found" };

    const projects = await db
      .select()
      .from(projectsTable)
      .where(eq(projectsTable.userId, targetUserId))
      .orderBy(desc(projectsTable.updatedAt));

    const projectStats = {
      total: projects.length,
      shipped: projects.filter((p) => p.status === "shipped").length,
      inProgress: projects.filter((p) => p.status === "in_progress").length,
      waitingForReview: projects.filter(
        (p) => p.status === "waiting_for_review",
      ).length,
      rejected: projects.filter((p) => p.status === "permanently_rejected")
        .length,
    };

    const totalHours = projects.reduce(
      (sum, p) => sum + (p.hoursOverride ?? p.hours ?? 0),
      0,
    );

    const scrapsBalance = (await getUserScrapsBalance(targetUserId)) || 0;

    // Look up Hackatime status for admin visibility
    let hackatimeSuspected = false;
    let hackatimeBanned = false;
    if (targetUser[0].email) {
      try {
        const htUser = await getHackatimeUser(targetUser[0].email);
        if (htUser) {
          hackatimeSuspected = htUser.suspected || false;
          hackatimeBanned = htUser.banned || false;
        }
      } catch (e) {
        console.error("[ADMIN] Failed to look up hackatime user status:", e);
      }
    }

    return {
      user: {
        id: targetUser[0].id,
        username: targetUser[0].username,
        avatar: targetUser[0].avatar,
        slackId: targetUser[0].slackId,
        email: user.role === "admin" ? targetUser[0].email : undefined,
        scraps: scrapsBalance.balance,
        role: targetUser[0].role,
        internalNotes: targetUser[0].internalNotes,
        createdAt: targetUser[0].createdAt,
      },
      hackatimeSuspected,
      hackatimeBanned,
      projects,
      stats: {
        ...projectStats,
        totalHours,
      },
    };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to fetch user details" });
  }
});

// Update user role (admin only)
admin.put("/users/:id/role", async ({ params, body, headers, status }) => {
  const user = await requireAdmin(headers as Record<string, string>);
  if (!user) {
    return status(401, { error: "Unauthorized" });
  }

  const { role } = body as { role: string };
  if (!["member", "reviewer", "admin", "banned"].includes(role)) {
    return status(400, { error: "Invalid role" });
  }

  if (user.id === parseInt(params.id)) {
    return status(400, { error: "Cannot change your own role" });
  }

  try {
    const updated = await db
      .update(usersTable)
      .set({ role, updatedAt: new Date() })
      .where(eq(usersTable.id, parseInt(params.id)))
      .returning();

    if (!updated[0]) {
      return status(404, { error: "Not Found" });
    }
    return { success: true };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to update user role" });
  }
});

// Update user internal notes
admin.put("/users/:id/notes", async ({ params, body, headers, status }) => {
  const user = await requireReviewer(headers as Record<string, string>);
  if (!user) {
    return status(401, { error: "Unauthorized" });
  }

  const { internalNotes } = body as { internalNotes: string };

  if (typeof internalNotes !== "string" || internalNotes.length > 2500) {
    return status(400, { error: "Note is too long or it's malformed!" });
  }

  try {
    const updated = await db
      .update(usersTable)
      .set({ internalNotes, updatedAt: new Date() })
      .where(eq(usersTable.id, parseInt(params.id)))
      .returning();

    if (!updated[0]) {
      return status(404, { error: "Not Found" });
    }
    return { success: true };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to update user internal notes" });
  }
});

// Give bonus scraps to user (admin only)
admin.post("/users/:id/bonus", async ({ params, body, headers, status }) => {
  try {
    const admin = await requireAdmin(headers as Record<string, string>);
    if (!admin) {
      return status(401, { error: "Unauthorized" });
    }

    const { amount, reason } = body as { amount: number; reason: string };

    if (
      !amount ||
      typeof amount !== "number" ||
      !Number.isFinite(amount) ||
      !Number.isInteger(amount) ||
      amount === 0
    ) {
      return status(400, {
        error: "Amount is required and must be a non-zero integer",
      });
    }

    if (!reason || typeof reason !== "string" || reason.trim().length === 0) {
      return status(400, { error: "Reason is required" });
    }

    if (reason.length > 500) {
      return status(400, { error: "Reason is too long (max 500 characters)" });
    }

    const targetUserId = parseInt(params.id);

    const targetUser = await db
      .select({ id: usersTable.id })
      .from(usersTable)
      .where(eq(usersTable.id, targetUserId))
      .limit(1);

    if (!targetUser[0]) {
      return status(404, { error: "User not found" });
    }

    const bonus = await db
      .insert(userBonusesTable)
      .values({
        userId: targetUserId,
        amount,
        reason: reason.trim(),
        givenBy: admin.id,
      })
      .returning({
        id: userBonusesTable.id,
        amount: userBonusesTable.amount,
        reason: userBonusesTable.reason,
        givenBy: userBonusesTable.givenBy,
        createdAt: userBonusesTable.createdAt,
      });

    return bonus[0];
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to create user bonus" });
  }
});

// Get user bonuses (admin only)
admin.get("/users/:id/bonuses", async ({ params, headers }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const targetUserId = parseInt(params.id);

    const bonuses = await db
      .select({
        id: userBonusesTable.id,
        amount: userBonusesTable.amount,
        reason: userBonusesTable.reason,
        givenBy: userBonusesTable.givenBy,
        givenByUsername: usersTable.username,
        createdAt: userBonusesTable.createdAt,
      })
      .from(userBonusesTable)
      .leftJoin(usersTable, eq(userBonusesTable.givenBy, usersTable.id))
      .where(eq(userBonusesTable.userId, targetUserId))
      .orderBy(desc(userBonusesTable.createdAt));

    return bonuses;
  } catch (err) {
    console.error(err);
    return { error: "Failed to fetch user bonuses" };
  }
});

// Get projects waiting for review
admin.get("/reviews", async ({ headers, query }) => {
  try {
    const user = await requireReviewer(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const page = parseInt(query.page as string) || 1;
    const limit = Math.min(parseInt(query.limit as string) || 20, 100);
    const offset = (page - 1) * limit;
    const sort = (query.sort as string) || "oldest";

    const orderClause =
      sort === "newest"
        ? desc(projectsTable.updatedAt)
        : asc(projectsTable.updatedAt);

    const [projects, countResult] = await Promise.all([
      db
        .select({
          id: projectsTable.id,
          userId: projectsTable.userId,
          name: projectsTable.name,
          description: projectsTable.description,
          image: projectsTable.image,
          githubUrl: projectsTable.githubUrl,
          playableUrl: projectsTable.playableUrl,
          hours: projectsTable.hours,
          hoursOverride: projectsTable.hoursOverride,
          hackatimeProject: projectsTable.hackatimeProject,
          tier: projectsTable.tier,
          tierOverride: projectsTable.tierOverride,
          status: projectsTable.status,
          deleted: projectsTable.deleted,
          scrapsAwarded: projectsTable.scrapsAwarded,
          scrapsPaidAt: projectsTable.scrapsPaidAt,
          views: projectsTable.views,
          updateDescription: projectsTable.updateDescription,
          aiDescription: projectsTable.aiDescription,
          feedbackSource: projectsTable.feedbackSource,
          feedbackGood: projectsTable.feedbackGood,
          feedbackImprove: projectsTable.feedbackImprove,
          createdAt: projectsTable.createdAt,
          updatedAt: projectsTable.updatedAt,
        })
        .from(projectsTable)
        .where(eq(projectsTable.status, "waiting_for_review"))
        .orderBy(orderClause)
        .limit(limit)
        .offset(offset),
      db
        .select({ count: sql<number>`count(*)` })
        .from(projectsTable)
        .where(eq(projectsTable.status, "waiting_for_review")),
    ]);

    const total = Number(countResult[0]?.count || 0);

    // Compute effective hours for each project (subtract overlapping shipped hours)
    const projectsWithEffective = await Promise.all(
      projects.map(async (p) => {
        const result = await computeEffectiveHoursForProject(p);
        return {
          ...p,
          effectiveHours: result.effectiveHours,
          deductedHours: result.deductedHours,
        };
      }),
    );

    return {
      data: projectsWithEffective,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  } catch (err) {
    console.error(err);
    return { error: "Failed to fetch reviews" };
  }
});

// Get single project for review (with user info and previous reviews)
admin.get("/reviews/:id", async ({ params, headers }) => {
  const user = await requireReviewer(headers as Record<string, string>);
  if (!user) return { error: "Unauthorized" };

  try {
    const project = await db
      .select()
      .from(projectsTable)
      .where(eq(projectsTable.id, parseInt(params.id)))
      .limit(1);

    if (project.length <= 0) return { error: "Project not found!" };

    const projectUser = await db
      .select({
        id: usersTable.id,
        username: usersTable.username,
        email: usersTable.email,
        avatar: usersTable.avatar,
        internalNotes: usersTable.internalNotes,
      })
      .from(usersTable)
      .where(eq(usersTable.id, project[0].userId))
      .limit(1);

    const reviews = await db
      .select()
      .from(reviewsTable)
      .where(eq(reviewsTable.projectId, parseInt(params.id)));

    const reviewerIds = reviews.map((r) => r.reviewerId);
    let reviewers: {
      id: number;
      username: string | null;
      avatar: string | null;
    }[] = [];
    if (reviewerIds.length > 0) {
      reviewers = await db
        .select({
          id: usersTable.id,
          username: usersTable.username,
          avatar: usersTable.avatar,
        })
        .from(usersTable)
        .where(inArray(usersTable.id, reviewerIds));
    }

    // Look up Hackatime user info by email
    let hackatimeUserId: number | null = null;
    let hackatimeSuspected = false;
    let hackatimeBanned = false;
    if (projectUser[0]?.email) {
      try {
        const htUser = await getHackatimeUser(projectUser[0].email);
        if (htUser) {
          hackatimeUserId = htUser.user_id;
          hackatimeSuspected = htUser.suspected || false;
          hackatimeBanned = htUser.banned || false;
        }
      } catch (e) {
        console.error("[ADMIN] Failed to look up hackatime user:", e);
      }
    }

    const isAdmin = user.role === "admin";
    // Hide pending_admin_approval from non-admin reviewers
    const maskedProject =
      !isAdmin && project[0].status === "pending_admin_approval"
        ? { ...project[0], status: "waiting_for_review" }
        : project[0];

    // Hide approval reviews from non-admin reviewers when project is pending admin approval
    const visibleReviews =
      !isAdmin && project[0].status === "pending_admin_approval"
        ? reviews.filter((r) => r.action !== "approved")
        : reviews;

    return {
      project: maskedProject,
      hackatimeUserId,
      hackatimeSuspected,
      hackatimeBanned,
      user: projectUser[0]
        ? {
            id: projectUser[0].id,
            username: projectUser[0].username,
            email: isAdmin ? projectUser[0].email : undefined,
            avatar: projectUser[0].avatar,
            internalNotes: projectUser[0].internalNotes,
          }
        : null,
      reviews: visibleReviews.map((r) => {
        const reviewer = reviewers.find((rv) => rv.id === r.reviewerId);
        return {
          ...r,
          reviewerName: reviewer?.username,
          reviewerAvatar: reviewer?.avatar,
          reviewerId: r.reviewerId,
        };
      }),
      ...(await computeEffectiveHoursForProject(project[0])),
    };
  } catch (err) {
    console.error(err);
    return { error: "Something went wrong while trying to get project" };
  }
});

// Submit a review
admin.post("/reviews/:id", async ({ params, body, headers }) => {
  try {
    const user = await requireReviewer(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const {
      action,
      feedbackForAuthor,
      internalJustification,
      hoursOverride,
      tierOverride,
      userInternalNotes,
    } = body as {
      action: "approved" | "denied" | "permanently_rejected";
      feedbackForAuthor: string;
      internalJustification?: string;
      hoursOverride?: number;
      tierOverride?: number;
      userInternalNotes?: string;
    };

    if (!["approved", "denied", "permanently_rejected"].includes(action)) {
      return { error: "Invalid action" };
    }

    if (!feedbackForAuthor?.trim()) {
      return { error: "Feedback for author is required" };
    }

    const projectId = parseInt(params.id);

    // Get project to find user
    const project = await db
      .select()
      .from(projectsTable)
      .where(eq(projectsTable.id, projectId))
      .limit(1);

    if (!project[0]) return { error: "Project not found" };

    // Validate hours override doesn't exceed project hours
    if (
      hoursOverride !== undefined &&
      hoursOverride > (project[0].hours ?? 0)
    ) {
      return {
        error: `Hours override (${hoursOverride}) cannot exceed project hours (${project[0].hours})`,
      };
    }

    // Reject if project is deleted or not waiting for review
    if (project[0].deleted) {
      return { error: "Cannot review a deleted project" };
    }
    if (project[0].status !== "waiting_for_review") {
      return { error: "Project is not marked for review" };
    }

    // Check for duplicate Code URL before creating review record (only block
    // cross-user duplicates; same-user duplicates are project updates)
    if (action === "approved" && project[0].githubUrl) {
      const duplicates = await db
        .select({ id: projectsTable.id })
        .from(projectsTable)
        .where(
          and(
            eq(projectsTable.githubUrl, project[0].githubUrl),
            eq(projectsTable.status, "shipped"),
            or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)),
            ne(projectsTable.userId, project[0].userId),
          ),
        )
        .limit(1);

      if (duplicates.length > 0) {
        return {
          error:
            "A shipped project with this Code URL already exists (from another user). This project has been kept in review.",
          duplicateCodeUrl: true,
        };
      }
    }

    // Create review record
    await db.insert(reviewsTable).values({
      projectId,
      reviewerId: user.id,
      action,
      feedbackForAuthor,
      internalJustification,
    });

    // Update project status
    let newStatus = "in_progress";
    const isAdmin = user.role === "admin";

    switch (action) {
      case "approved":
        // If reviewer (not admin) approves, send to second-pass review
        // If admin approves, ship directly
        newStatus = isAdmin ? "shipped" : "pending_admin_approval";
        break;
      case "denied":
        newStatus = "in_progress";
        break;
      case "permanently_rejected":
        newStatus = "permanently_rejected";
        break;
      default:
        newStatus = "in_progress";
    }

    const updateData: Record<string, unknown> = {
      status: newStatus,
      updatedAt: new Date(),
    };

    if (hoursOverride !== undefined) {
      updateData.hoursOverride = hoursOverride;
    }

    if (tierOverride !== undefined) {
      updateData.tierOverride = tierOverride;
    }

    let scrapsAwarded = 0;
    if (action === "approved") {
      const hours = hoursOverride ?? project[0].hours ?? 0;
      const tier = tierOverride ?? project[0].tier ?? 1;

      // Compute effective hours using activity-derived shipped dates
      const { effectiveHours } = await computeEffectiveHoursForProject({
        ...project[0],
        hoursOverride: hoursOverride ?? project[0].hoursOverride,
      });
      const newScrapsAwarded = calculateScrapsFromHours(effectiveHours, tier);

      // Only set scrapsAwarded if admin is approving
      // Reviewer approvals just go to pending_admin_approval without awarding scraps yet
      if (isAdmin) {
        const previouslyShipped = await hasProjectBeenShipped(projectId);
        // If this is an update to an already-shipped project, calculate ADDITIONAL scraps
        // (difference between new award and previous award)
        if (previouslyShipped && project[0].scrapsAwarded > 0) {
          scrapsAwarded = Math.max(
            0,
            newScrapsAwarded - project[0].scrapsAwarded,
          );
        } else {
          scrapsAwarded = newScrapsAwarded;
        }

        updateData.scrapsAwarded = newScrapsAwarded;
      }
    }

    await db
      .update(projectsTable)
      .set(updateData)
      .where(eq(projectsTable.id, projectId));

    if (action === "approved") {
      const previouslyShipped = await hasProjectBeenShipped(projectId);

      if (scrapsAwarded > 0) {
        await db.insert(projectActivityTable).values({
          userId: project[0].userId,
          projectId,
          action: previouslyShipped
            ? `earned ${scrapsAwarded} additional scraps (update)`
            : `earned ${scrapsAwarded} scraps`,
        });
      }

      // Only log shipping activity if admin approved (not pending second-pass)
      if (isAdmin) {
        await db.insert(projectActivityTable).values({
          userId: project[0].userId,
          projectId,
          action: previouslyShipped ? "project_updated" : "project_shipped",
        });
      }
    }

    // Update user internal notes if provided
    if (userInternalNotes !== undefined) {
      if (userInternalNotes.length <= 2500) {
        await db
          .update(usersTable)
          .set({ internalNotes: userInternalNotes, updatedAt: new Date() })
          .where(eq(usersTable.id, project[0].userId));
      }
    }

    // Send Slack DM notification to the project author
    // Skip notification when a non-admin reviewer approves (goes to pending_admin_approval)
    // The second-pass flow sends its own notification when an admin accepts/rejects
    const shouldNotify = isAdmin || action !== "approved";
    if (config.slackBotToken && shouldNotify) {
      try {
        // Get the project author's Slack ID
        const projectAuthor = await db
          .select({ slackId: usersTable.slackId })
          .from(usersTable)
          .where(eq(usersTable.id, project[0].userId))
          .limit(1);

        if (projectAuthor[0]?.slackId) {
          // Get admin Slack IDs for permanently rejected projects
          let adminSlackIds: string[] = [];
          if (action === "permanently_rejected") {
            const admins = await db
              .select({ slackId: usersTable.slackId })
              .from(usersTable)
              .where(eq(usersTable.role, "admin"));

            adminSlackIds = admins
              .map((a) => a.slackId)
              .filter((id): id is string => !!id);
          }

          // Get the reviewer's Slack ID
          const reviewerSlackId = user.slackId ?? null;

          await notifyProjectReview({
            userSlackId: projectAuthor[0].slackId,
            projectName: project[0].name,
            projectId,
            action,
            feedbackForAuthor,
            reviewerSlackId,
            adminSlackIds,
            scrapsAwarded,
            frontendUrl: config.frontendUrl,
            token: config.slackBotToken,
          });
        }
      } catch (slackErr) {
        // Don't fail the review if Slack notification fails
        console.error("Failed to send Slack DM notification:", slackErr);
      }
    }

    return { success: true };
  } catch (err) {
    console.error(err);
    return { error: "Failed to submit review" };
  }
});

// Second-pass review endpoints (admin only)
// Get projects pending admin approval (reviewer-approved projects)
admin.get("/second-pass", async ({ headers, query }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const page = parseInt(query.page as string) || 1;
    const limit = Math.min(parseInt(query.limit as string) || 20, 100);
    const offset = (page - 1) * limit;
    const sort = (query.sort as string) || "oldest";

    const submittedAtOrderExpr = sql<Date | null>`COALESCE((
            SELECT MAX(pa.created_at)
            FROM project_activity pa
            WHERE pa.project_id = projects.id
              AND pa.action = 'project_submitted'
        ), ${projectsTable.updatedAt})`;

    const [projects, countResult] = await Promise.all([
      db
        .select({
          id: projectsTable.id,
          userId: projectsTable.userId,
          name: projectsTable.name,
          description: projectsTable.description,
          image: projectsTable.image,
          githubUrl: projectsTable.githubUrl,
          playableUrl: projectsTable.playableUrl,
          hours: projectsTable.hours,
          hoursOverride: projectsTable.hoursOverride,
          hackatimeProject: projectsTable.hackatimeProject,
          tier: projectsTable.tier,
          tierOverride: projectsTable.tierOverride,
          status: projectsTable.status,
          deleted: projectsTable.deleted,
          scrapsAwarded: projectsTable.scrapsAwarded,
          scrapsPaidAt: projectsTable.scrapsPaidAt,
          views: projectsTable.views,
          updateDescription: projectsTable.updateDescription,
          aiDescription: projectsTable.aiDescription,
          feedbackSource: projectsTable.feedbackSource,
          feedbackGood: projectsTable.feedbackGood,
          feedbackImprove: projectsTable.feedbackImprove,
          createdAt: projectsTable.createdAt,
          updatedAt: projectsTable.updatedAt,
          submittedAt: sql<Date | null>`(
                    SELECT MAX(pa.created_at)
                    FROM project_activity pa
                    WHERE pa.project_id = projects.id
                      AND pa.action = 'project_submitted'
                )`,
        })
        .from(projectsTable)
        .where(eq(projectsTable.status, "pending_admin_approval"))
        .orderBy(
          sort === "newest"
            ? desc(submittedAtOrderExpr)
            : asc(submittedAtOrderExpr),
        )
        .limit(limit)
        .offset(offset),
      db
        .select({ count: sql<number>`count(*)` })
        .from(projectsTable)
        .where(eq(projectsTable.status, "pending_admin_approval")),
    ]);

    const total = Number(countResult[0]?.count || 0);

    // Compute effective hours for each project
    const projectsWithEffective = await Promise.all(
      projects.map(async (p) => {
        const result = await computeEffectiveHoursForProject(p);
        return {
          ...p,
          effectiveHours: result.effectiveHours,
          deductedHours: result.deductedHours,
        };
      }),
    );

    return {
      data: projectsWithEffective,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  } catch (err) {
    console.error(err);
    return { error: "Failed to fetch second-pass reviews" };
  }
});

// Get single project for second-pass review
admin.get("/second-pass/:id", async ({ params, headers }) => {
  const user = await requireAdmin(headers as Record<string, string>);
  if (!user) return { error: "Unauthorized" };

  try {
    const project = await db
      .select()
      .from(projectsTable)
      .where(eq(projectsTable.id, parseInt(params.id)))
      .limit(1);

    if (project.length <= 0) return { error: "Project not found!" };
    if (project[0].status !== "pending_admin_approval") {
      return { error: "Project is not pending admin approval" };
    }

    const projectUser = await db
      .select({
        id: usersTable.id,
        username: usersTable.username,
        email: usersTable.email,
        avatar: usersTable.avatar,
        internalNotes: usersTable.internalNotes,
      })
      .from(usersTable)
      .where(eq(usersTable.id, project[0].userId))
      .limit(1);

    const reviews = await db
      .select()
      .from(reviewsTable)
      .where(eq(reviewsTable.projectId, parseInt(params.id)));

    const reviewerIds = reviews.map((r) => r.reviewerId);
    let reviewers: {
      id: number;
      username: string | null;
      avatar: string | null;
    }[] = [];
    if (reviewerIds.length > 0) {
      reviewers = await db
        .select({
          id: usersTable.id,
          username: usersTable.username,
          avatar: usersTable.avatar,
        })
        .from(usersTable)
        .where(inArray(usersTable.id, reviewerIds));
    }

    // Look up Hackatime user info by email
    let hackatimeUserId: number | null = null;
    let hackatimeSuspected = false;
    let hackatimeBanned = false;
    if (projectUser[0]?.email) {
      try {
        const htUser = await getHackatimeUser(projectUser[0].email);
        if (htUser) {
          hackatimeUserId = htUser.user_id;
          hackatimeSuspected = htUser.suspected || false;
          hackatimeBanned = htUser.banned || false;
        }
      } catch (e) {
        console.error("[ADMIN] Failed to look up hackatime user:", e);
      }
    }

    // Calculate effective hours and overlapping projects
    const effectiveHoursData = await computeEffectiveHoursForProject(
      project[0],
    );

    return {
      project: project[0],
      hackatimeUserId,
      hackatimeSuspected,
      hackatimeBanned,
      user: projectUser[0]
        ? {
            id: projectUser[0].id,
            username: projectUser[0].username,
            email: projectUser[0].email,
            avatar: projectUser[0].avatar,
            internalNotes: projectUser[0].internalNotes,
          }
        : null,
      reviews: reviews.map((r) => {
        const reviewer = reviewers.find((rv) => rv.id === r.reviewerId);
        return {
          ...r,
          reviewerName: reviewer?.username,
          reviewerAvatar: reviewer?.avatar,
          reviewerId: r.reviewerId,
        };
      }),
      ...effectiveHoursData,
    };
  } catch (err) {
    console.error(err);
    return { error: "Something went wrong while trying to get project" };
  }
});

// Accept or reject a second-pass review
admin.post("/second-pass/:id", async ({ params, body, headers }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const { action, feedbackForAuthor, hoursOverride } = body as {
      action: "accept" | "reject";
      feedbackForAuthor?: string;
      hoursOverride?: number;
    };

    if (!["accept", "reject"].includes(action)) {
      return { error: 'Invalid action. Must be "accept" or "reject"' };
    }

    const projectId = parseInt(params.id);

    // Get project
    const project = await db
      .select()
      .from(projectsTable)
      .where(eq(projectsTable.id, projectId))
      .limit(1);

    if (!project[0]) return { error: "Project not found" };
    if (project[0].status !== "pending_admin_approval") {
      return { error: "Project is not pending admin approval" };
    }

    if (action === "accept") {
      // Accept the reviewer's approval and ship the project
      const tier = project[0].tierOverride ?? project[0].tier ?? 1;

      // Apply hours override if provided
      if (hoursOverride !== undefined) {
        await db
          .update(projectsTable)
          .set({ hoursOverride })
          .where(eq(projectsTable.id, projectId));
        project[0].hoursOverride = hoursOverride;
      }

      // Compute effective hours using activity-derived shipped dates
      const { effectiveHours } = await computeEffectiveHoursForProject(
        project[0],
      );
      const newScrapsAwarded = calculateScrapsFromHours(effectiveHours, tier);

      const previouslyShipped = await hasProjectBeenShipped(projectId);

      let scrapsAwarded = 0;
      const updateData: Record<string, unknown> = {
        status: "shipped",
        updatedAt: new Date(),
      };

      // Calculate scraps
      if (previouslyShipped && project[0].scrapsAwarded > 0) {
        scrapsAwarded = Math.max(
          0,
          newScrapsAwarded - project[0].scrapsAwarded,
        );
      } else {
        scrapsAwarded = newScrapsAwarded;
      }

      updateData.scrapsAwarded = newScrapsAwarded;

      // Update project
      await db
        .update(projectsTable)
        .set(updateData)
        .where(eq(projectsTable.id, projectId));

      // Log scraps earned
      if (scrapsAwarded > 0) {
        await db.insert(projectActivityTable).values({
          userId: project[0].userId,
          projectId,
          action: previouslyShipped
            ? `earned ${scrapsAwarded} additional scraps (update)`
            : `earned ${scrapsAwarded} scraps`,
        });
      }

      // Log project shipped
      await db.insert(projectActivityTable).values({
        userId: project[0].userId,
        projectId,
        action: previouslyShipped ? "project_updated" : "project_shipped",
      });

      // Send notification to project author
      if (config.slackBotToken) {
        try {
          const projectAuthor = await db
            .select({ slackId: usersTable.slackId })
            .from(usersTable)
            .where(eq(usersTable.id, project[0].userId))
            .limit(1);

          if (projectAuthor[0]?.slackId) {
            await notifyProjectReview({
              userSlackId: projectAuthor[0].slackId,
              projectName: project[0].name,
              projectId,
              action: "approved",
              feedbackForAuthor: "Your project has been approved and shipped!",
              reviewerSlackId: user.slackId ?? null,
              adminSlackIds: [],
              scrapsAwarded,
              frontendUrl: config.frontendUrl,
              token: config.slackBotToken,
            });
          }
        } catch (slackErr) {
          console.error("Failed to send Slack notification:", slackErr);
        }
      }

      return { success: true, scrapsAwarded };
    } else {
      // Reject: Delete the approval review and add a denial review
      // Find and delete the approval review
      await db
        .delete(reviewsTable)
        .where(
          and(
            eq(reviewsTable.projectId, projectId),
            eq(reviewsTable.action, "approved"),
          ),
        );

      // Add a denial review from the admin
      await db.insert(reviewsTable).values({
        projectId,
        reviewerId: user.id,
        action: "denied",
        feedbackForAuthor:
          feedbackForAuthor ||
          "The admin has rejected the initial approval. Please make improvements and resubmit.",
        internalJustification: "Second-pass rejection",
      });

      // Set project back to in_progress
      await db
        .update(projectsTable)
        .set({ status: "in_progress", updatedAt: new Date() })
        .where(eq(projectsTable.id, projectId));

      // Send notification to project author
      if (config.slackBotToken) {
        try {
          const projectAuthor = await db
            .select({ slackId: usersTable.slackId })
            .from(usersTable)
            .where(eq(usersTable.id, project[0].userId))
            .limit(1);

          if (projectAuthor[0]?.slackId) {
            await notifyProjectReview({
              userSlackId: projectAuthor[0].slackId,
              projectName: project[0].name,
              projectId,
              action: "denied",
              feedbackForAuthor:
                feedbackForAuthor ||
                "The admin has rejected the initial approval. Please make improvements and resubmit.",
              reviewerSlackId: user.slackId ?? null,
              adminSlackIds: [],
              scrapsAwarded: 0,
              frontendUrl: config.frontendUrl,
              token: config.slackBotToken,
            });
          }
        } catch (slackErr) {
          console.error("Failed to send Slack notification:", slackErr);
        }
      }

      return { success: true };
    }
  } catch (err) {
    console.error(err);
    return { error: "Failed to process second-pass review" };
  }
});

// Get pending scraps payout info (admin only)
admin.get("/scraps-payout", async ({ headers }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const pendingProjects = await db
      .select({
        id: projectsTable.id,
        name: projectsTable.name,
        image: projectsTable.image,
        scrapsAwarded: projectsTable.scrapsAwarded,
        hours: projectsTable.hours,
        hoursOverride: projectsTable.hoursOverride,
        userId: projectsTable.userId,
        status: projectsTable.status,
        createdAt: projectsTable.createdAt,
      })
      .from(projectsTable)
      .where(
        and(
          eq(projectsTable.status, "shipped"),
          isNull(projectsTable.scrapsPaidAt),
          sql`${projectsTable.scrapsAwarded} > 0`,
          or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)),
        ),
      );

    // Get user info for each pending project
    const userIds = [...new Set(pendingProjects.map((p) => p.userId))];
    let users: {
      id: number;
      username: string | null;
      avatar: string | null;
    }[] = [];
    if (userIds.length > 0) {
      users = await db
        .select({
          id: usersTable.id,
          username: usersTable.username,
          avatar: usersTable.avatar,
        })
        .from(usersTable)
        .where(inArray(usersTable.id, userIds));
    }

    const projectsWithUsers = pendingProjects.map((p) => {
      const owner = users.find((u) => u.id === p.userId);
      return {
        ...p,
        owner: owner
          ? { id: owner.id, username: owner.username, avatar: owner.avatar }
          : null,
      };
    });

    return {
      pendingProjects: pendingProjects.length,
      pendingScraps: pendingProjects.reduce(
        (sum, p) => sum + p.scrapsAwarded,
        0,
      ),
      projects: projectsWithUsers,
      nextPayoutDate: getNextPayoutDate().toISOString(),
    };
  } catch (err) {
    console.error(err);
    return { error: "Failed to fetch payout info" };
  }
});

// Manually trigger scraps payout (admin only)
admin.post("/scraps-payout", async ({ headers }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const { paidCount, totalScraps } = await payoutPendingScraps();
    return { success: true, paidCount, totalScraps };
  } catch (err) {
    console.error(err);
    return { error: "Failed to trigger payout" };
  }
});

// Reject a project's payout (admin only)
admin.post("/scraps-payout/reject", async ({ headers, body, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return status(401, { error: "Unauthorized" });

    const { projectId, reason } = body as { projectId: number; reason: string };

    if (!projectId || typeof projectId !== "number") {
      return status(400, { error: "Project ID is required" });
    }

    if (!reason?.trim()) {
      return status(400, { error: "A reason is required" });
    }

    // Find the project
    const project = await db
      .select({
        id: projectsTable.id,
        userId: projectsTable.userId,
        scrapsAwarded: projectsTable.scrapsAwarded,
        scrapsPaidAt: projectsTable.scrapsPaidAt,
        status: projectsTable.status,
        name: projectsTable.name,
      })
      .from(projectsTable)
      .where(eq(projectsTable.id, projectId))
      .limit(1);

    if (!project[0]) {
      return status(404, { error: "Project not found" });
    }

    if (project[0].scrapsPaidAt) {
      return status(400, {
        error: "Scraps have already been paid out for this project",
      });
    }

    if (project[0].scrapsAwarded <= 0) {
      return status(400, { error: "No scraps to reject for this project" });
    }

    const previousScraps = project[0].scrapsAwarded;

    // Set scrapsAwarded to 0 and status back to in_progress
    await db
      .update(projectsTable)
      .set({ scrapsAwarded: 0, status: "in_progress", updatedAt: new Date() })
      .where(eq(projectsTable.id, projectId));

    // Add a proper review record so it shows like a regular review card
    await db.insert(reviewsTable).values({
      projectId,
      reviewerId: user.id,
      action: "scraps_unawarded",
      feedbackForAuthor: `Payout rejected (${previousScraps} scraps): ${reason.trim()}`,
    });

    return { success: true, previousScraps };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to reject payout" });
  }
});

// Compute optimal shop item pricing from dollar cost (admin only)
admin.post("/shop/compute-pricing", async ({ headers, body, status }) => {
  const user = await requireAdmin(headers as Record<string, string>);
  if (!user) {
    return status(401, { error: "Unauthorized" });
  }

  const { dollarCost, baseProbability, stockCount } = body as {
    dollarCost: number;
    baseProbability?: number;
    stockCount?: number;
  };

  if (
    typeof dollarCost !== "number" ||
    !Number.isFinite(dollarCost) ||
    dollarCost <= 0
  ) {
    return status(400, { error: "dollarCost must be a positive number" });
  }

  if (
    baseProbability !== undefined &&
    (typeof baseProbability !== "number" ||
      baseProbability < 1 ||
      baseProbability > 100)
  ) {
    return status(400, { error: "baseProbability must be between 1 and 100" });
  }

  return computeItemPricing(dollarCost, baseProbability, stockCount ?? 1);
});

// Batch compute server-authoritative display roll costs (admin only)
// Accepts JSON body: { itemIds?: number[], items?: Array<{ id, price, baseProbability?, rollCostOverride?, perRollMultiplier?, rollCount?, userBoostPercent? }> }
// Returns: { results: [{ id, baseRollCost, displayRollCost }] }
admin.post("/shop/compute-roll-costs", async ({ headers, body, status }) => {
  const user = await requireAdmin(headers as Record<string, string>);
  if (!user) return status(401, { error: "Unauthorized" });

  const { itemIds, items } = body as {
    itemIds?: number[];
    items?: Array<any>;
  };

  try {
    let rows: any[] = [];

    // If list of DB IDs provided, load canonical fields from DB
    if (Array.isArray(itemIds) && itemIds.length > 0) {
      rows = await db
        .select({
          id: shopItemsTable.id,
          price: shopItemsTable.price,
          baseProbability: shopItemsTable.baseProbability,
          rollCostOverride: shopItemsTable.rollCostOverride,
          perRollMultiplier: shopItemsTable.perRollMultiplier,
        })
        .from(shopItemsTable)
        .where(inArray(shopItemsTable.id, itemIds));
    } else if (Array.isArray(items) && items.length > 0) {
      // Accept ad-hoc items payload from client for previewing unsaved items
      rows = items.map((it) => ({
        id: it.id,
        price: it.price,
        baseProbability: it.baseProbability ?? 50,
        rollCostOverride: it.rollCostOverride ?? null,
        perRollMultiplier: it.perRollMultiplier ?? 0.05,
        rollCount: it.rollCount ?? 0,
        userBoostPercent: it.userBoostPercent ?? 0,
      }));
    } else {
      return status(400, { error: "itemIds or items required" });
    }

    const results: Array<{
      id: number;
      baseRollCost: number;
      displayRollCost: number;
    }> = [];

    for (const r of rows) {
      // Effective probability includes any provided userBoostPercent
      const effectiveProbability = Math.min(
        (r.baseProbability ?? 50) + (r.userBoostPercent ?? 0),
        100,
      );
      const perRoll = r.perRollMultiplier ?? 0.05;
      const baseRollCost = calculateRollCost(
        r.price,
        effectiveProbability,
        r.rollCostOverride,
        r.baseProbability,
        perRoll,
      );
      const prev = r.rollCount ?? 0;
      const displayRollCost = Math.round(baseRollCost * (1 + perRoll * prev));

      results.push({ id: r.id, baseRollCost, displayRollCost });
    }

    return { results };
  } catch (err) {
    console.error("[ADMIN] compute-roll-costs error:", err);
    return status(500, { error: "Failed to compute roll costs" });
  }
});

// Shop admin endpoints (admin only)
admin.get("/shop/items", async ({ headers }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return { error: "Unauthorized" };

    const items = await db
      .select()
      .from(shopItemsTable)
      .orderBy(desc(shopItemsTable.createdAt));

    return items;
  } catch (err) {
    console.error(err);
    return { error: "Failed to fetch shop items" };
  }
});

admin.post("/shop/items", async ({ headers, body, status }) => {
  const user = await requireAdmin(headers as Record<string, string>);
  if (!user) {
    return status(401, { error: "Unauthorized" });
  }

  const {
    name,
    image,
    description,
    price,
    category,
    count,
    baseProbability,
    baseUpgradeCost,
    costMultiplier,
    boostAmount,
    rollCostOverride,
  } = body as {
    name: string;
    image: string;
    description: string;
    price: number;
    category: string;
    count: number;
    baseProbability?: number;
    baseUpgradeCost?: number;
    costMultiplier?: number;
    boostAmount?: number;
    rollCostOverride?: number | null;
  };

  if (
    !name?.trim() ||
    !image?.trim() ||
    !description?.trim() ||
    !category?.trim()
  ) {
    return status(400, { error: "All fields are required" });
  }

  if (typeof price !== "number" || price < 0) {
    return status(400, { error: "Invalid price" });
  }

  if (
    baseProbability !== undefined &&
    (typeof baseProbability !== "number" ||
      !Number.isInteger(baseProbability) ||
      baseProbability < 0 ||
      baseProbability > 100)
  ) {
    return status(400, {
      error: "Base probability must be an integer between 0 and 100",
    });
  }

  try {
    // Compute canonical pricing on the server (dollarCost = scrapsPrice / SCRAPS_PER_DOLLAR)
    const dollarCost =
      typeof price === "number" ? price / SCRAPS_PER_DOLLAR : 0;
    const pricing = computeItemPricing(dollarCost, baseProbability, count ?? 1);

    // Allow admin-supplied multipliers (optional); fallback to sensible defaults.
    const perRollMultiplierVal = (body as any)?.perRollMultiplier ?? 0.05;
    const upgradeBudgetMultiplierVal =
      (body as any)?.upgradeBudgetMultiplier ?? 3.0;

    await db.insert(shopItemsTable).values({
      name: name.trim(),
      image: image.trim(),
      description: description.trim(),
      price,
      category: category.trim(),
      count: count || 0,
      // Use server-calculated canonical values so DB is the source of truth
      baseProbability: pricing.baseProbability,
      baseUpgradeCost: pricing.baseUpgradeCost,
      costMultiplier: pricing.costMultiplier,
      boostAmount: pricing.boostAmount,
      rollCostOverride: rollCostOverride ?? null,
      perRollMultiplier: perRollMultiplierVal,
      upgradeBudgetMultiplier: upgradeBudgetMultiplierVal,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    return { success: true };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to create shop item" });
  }
});

admin.put("/shop/items/:id", async ({ params, headers, body, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const {
      name,
      image,
      description,
      price,
      category,
      count,
      baseProbability,
      baseUpgradeCost,
      costMultiplier,
      boostAmount,
      rollCostOverride,
    } = body as {
      name?: string;
      image?: string;
      description?: string;
      price?: number;
      category?: string;
      count?: number;
      baseProbability?: number;
      baseUpgradeCost?: number;
      costMultiplier?: number;
      boostAmount?: number;
      rollCostOverride?: number | null;
    };

    if (
      baseProbability !== undefined &&
      (typeof baseProbability !== "number" ||
        !Number.isInteger(baseProbability) ||
        baseProbability < 0 ||
        baseProbability > 100)
    ) {
      return status(400, {
        error: "Base probability must be an integer between 0 and 100",
      });
    }

    const updateData: Record<string, unknown> = { updatedAt: new Date() };

    if (name !== undefined) updateData.name = name.trim();
    if (image !== undefined) updateData.image = image.trim();
    if (description !== undefined) updateData.description = description.trim();
    if (price !== undefined) updateData.price = price;
    if (category !== undefined) updateData.category = category.trim();
    if (count !== undefined) updateData.count = count;
    if (baseProbability !== undefined)
      updateData.baseProbability = baseProbability;
    if (baseUpgradeCost !== undefined)
      updateData.baseUpgradeCost = baseUpgradeCost;
    if (costMultiplier !== undefined)
      updateData.costMultiplier = costMultiplier;
    if (boostAmount !== undefined) updateData.boostAmount = boostAmount;
    if (rollCostOverride !== undefined)
      updateData.rollCostOverride = rollCostOverride;

    const updated = await db
      .update(shopItemsTable)
      .set(updateData)
      .where(eq(shopItemsTable.id, parseInt(params.id)))
      .returning();

    if (!updated[0]) {
      return status(404, { error: "Not found" });
    }
    return { success: true };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to update shop item" });
  }
});

admin.delete("/shop/items/:id", async ({ params, headers, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const itemId = parseInt(params.id);

    // Delete all related records first (cascade manually)
    await db
      .delete(shopHeartsTable)
      .where(eq(shopHeartsTable.shopItemId, itemId));
    await db
      .delete(shopRollsTable)
      .where(eq(shopRollsTable.shopItemId, itemId));
    await db
      .delete(refineryOrdersTable)
      .where(eq(refineryOrdersTable.shopItemId, itemId));
    await db
      .delete(shopPenaltiesTable)
      .where(eq(shopPenaltiesTable.shopItemId, itemId));
    await db
      .delete(shopOrdersTable)
      .where(eq(shopOrdersTable.shopItemId, itemId));

    // Now delete the item itself
    await db.delete(shopItemsTable).where(eq(shopItemsTable.id, itemId));

    return { success: true };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to delete shop item" });
  }
});

// Reset refinery orders for users who haven't won/purchased any item
admin.post("/shop/reset-non-buyer-refinery", async ({ headers, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    // Find user+item combos that have refinery orders but no luck_win/purchase shop orders
    const refineryUsers = await db
      .select({
        userId: refineryOrdersTable.userId,
        shopItemId: refineryOrdersTable.shopItemId,
      })
      .from(refineryOrdersTable)
      .groupBy(refineryOrdersTable.userId, refineryOrdersTable.shopItemId);

    const buyers = await db
      .select({
        userId: shopOrdersTable.userId,
        shopItemId: shopOrdersTable.shopItemId,
      })
      .from(shopOrdersTable)
      .where(
        or(
          eq(shopOrdersTable.orderType, "purchase"),
          eq(shopOrdersTable.orderType, "luck_win"),
        ),
      )
      .groupBy(shopOrdersTable.userId, shopOrdersTable.shopItemId);

    const buyerSet = new Set(buyers.map((b) => `${b.userId}-${b.shopItemId}`));
    const toReset = refineryUsers.filter(
      (r) => !buyerSet.has(`${r.userId}-${r.shopItemId}`),
    );

    let deletedOrders = 0;
    let deletedHistory = 0;
    for (const { userId, shopItemId } of toReset) {
      const deleted = await db
        .delete(refineryOrdersTable)
        .where(
          and(
            eq(refineryOrdersTable.userId, userId),
            eq(refineryOrdersTable.shopItemId, shopItemId),
          ),
        )
        .returning({ id: refineryOrdersTable.id });
      deletedOrders += deleted.length;

      const historyDeleted = await db
        .delete(refinerySpendingHistoryTable)
        .where(
          and(
            eq(refinerySpendingHistoryTable.userId, userId),
            eq(refinerySpendingHistoryTable.shopItemId, shopItemId),
          ),
        )
        .returning({ id: refinerySpendingHistoryTable.id });
      deletedHistory += historyDeleted.length;
    }

    console.log(
      `[ADMIN] Reset non-buyer refinery: ${toReset.length} user-item combos, ${deletedOrders} orders, ${deletedHistory} history entries deleted`,
    );

    return {
      success: true,
      resetCount: toReset.length,
      deletedOrders,
      deletedHistory,
    };
  } catch (err) {
    console.error("[ADMIN] Failed to reset non-buyer refinery:", err);
    return status(500, { error: "Failed to reset refinery orders" });
  }
});

// News admin endpoints (admin only)
admin.get("/news", async ({ headers, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const items = await db
      .select()
      .from(newsTable)
      .orderBy(desc(newsTable.createdAt));

    return items;
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to fetch news" });
  }
});

admin.post("/news", async ({ headers, body, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const { title, content, active } = body as {
      title: string;
      content: string;
      active?: boolean;
    };

    if (!title?.trim() || !content?.trim()) {
      return status(400, { error: "Title and content are required" });
    }

    const inserted = await db
      .insert(newsTable)
      .values({
        title: title.trim(),
        content: content.trim(),
        active: active ?? true,
      })
      .returning({
        id: newsTable.id,
        title: newsTable.title,
        content: newsTable.content,
        active: newsTable.active,
        createdAt: newsTable.createdAt,
        updatedAt: newsTable.updatedAt,
      });

    return inserted[0];
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to create news" });
  }
});

admin.put("/news/:id", async ({ params, headers, body, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const { title, content, active } = body as {
      title?: string;
      content?: string;
      active?: boolean;
    };

    const updateData: Record<string, unknown> = { updatedAt: new Date() };

    if (title !== undefined) updateData.title = title.trim();
    if (content !== undefined) updateData.content = content.trim();
    if (active !== undefined) updateData.active = active;

    const updated = await db
      .update(newsTable)
      .set(updateData)
      .where(eq(newsTable.id, parseInt(params.id)))
      .returning({
        id: newsTable.id,
        title: newsTable.title,
        content: newsTable.content,
        active: newsTable.active,
        createdAt: newsTable.createdAt,
        updatedAt: newsTable.updatedAt,
      });

    if (!updated[0]) {
      return status(404, { error: "Not found" });
    }
    return updated[0];
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to update news" });
  }
});

admin.delete("/news/:id", async ({ params, headers, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    await db.delete(newsTable).where(eq(newsTable.id, parseInt(params.id)));

    return { success: true };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to delete news" });
  }
});

admin.get("/orders", async ({ headers, query, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const orderStatus = query.status as string | undefined;

    let ordersQuery = db
      .select({
        id: shopOrdersTable.id,
        quantity: shopOrdersTable.quantity,
        pricePerItem: shopOrdersTable.pricePerItem,
        totalPrice: shopOrdersTable.totalPrice,
        status: shopOrdersTable.status,
        orderType: shopOrdersTable.orderType,
        notes: shopOrdersTable.notes,
        isFulfilled: shopOrdersTable.isFulfilled,
        shippingAddress: shopOrdersTable.shippingAddress,
        phone: shopOrdersTable.phone,
        createdAt: shopOrdersTable.createdAt,
        itemId: shopItemsTable.id,
        itemName: shopItemsTable.name,
        itemImage: shopItemsTable.image,
        userId: usersTable.id,
        username: usersTable.username,
        slackId: usersTable.slackId,
      })
      .from(shopOrdersTable)
      .innerJoin(
        shopItemsTable,
        eq(shopOrdersTable.shopItemId, shopItemsTable.id),
      )
      .innerJoin(usersTable, eq(shopOrdersTable.userId, usersTable.id))
      .orderBy(desc(shopOrdersTable.createdAt));

    if (orderStatus) {
      ordersQuery = ordersQuery.where(
        eq(shopOrdersTable.status, orderStatus),
      ) as typeof ordersQuery;
    }

    return await ordersQuery;
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to fetch orders" });
  }
});

admin.patch("/orders/:id", async ({ params, body, headers, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const {
      status: orderStatus,
      notes,
      isFulfilled,
    } = body as { status?: string; notes?: string; isFulfilled?: boolean };

    const validStatuses = [
      "pending",
      "processing",
      "shipped",
      "delivered",
      "cancelled",
      "deleted",
    ];
    if (orderStatus && !validStatuses.includes(orderStatus)) {
      return status(400, { error: "Invalid status" });
    }

    const updateData: Record<string, unknown> = { updatedAt: new Date() };
    if (orderStatus) updateData.status = orderStatus;
    if (notes !== undefined) updateData.notes = notes;
    if (isFulfilled !== undefined) updateData.isFulfilled = isFulfilled;

    const updated = await db
      .update(shopOrdersTable)
      .set(updateData)
      .where(eq(shopOrdersTable.id, parseInt(params.id)))
      .returning({
        id: shopOrdersTable.id,
        quantity: shopOrdersTable.quantity,
        pricePerItem: shopOrdersTable.pricePerItem,
        totalPrice: shopOrdersTable.totalPrice,
        status: shopOrdersTable.status,
        orderType: shopOrdersTable.orderType,
        notes: shopOrdersTable.notes,
        isFulfilled: shopOrdersTable.isFulfilled,
        shippingAddress: shopOrdersTable.shippingAddress,
        createdAt: shopOrdersTable.createdAt,
      });

    if (!updated[0]) {
      return status(404, { error: "Not found" });
    }
    return updated[0];
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to update order" });
  }
});

// Sync hours for a single project from Hackatime
admin.post("/projects/:id/sync-hours", async ({ headers, params, status }) => {
  const user = await requireReviewer(headers as Record<string, string>);
  if (!user) {
    return status(401, { error: "Unauthorized" });
  }

  try {
    // Don't allow syncing shipped projects — their hours are frozen at approval time
    const [proj] = await db
      .select({ status: projectsTable.status })
      .from(projectsTable)
      .where(eq(projectsTable.id, parseInt(params.id)))
      .limit(1);

    if (!proj) {
      return status(404, { error: "Project not found" });
    }

    if (proj.status === "shipped") {
      return status(400, {
        error:
          "Cannot sync hours for shipped projects — hours are frozen at approval time",
      });
    }

    const result = await syncSingleProject(parseInt(params.id));
    if (result.error) {
      return {
        hours: result.hours,
        updated: result.updated,
        error: result.error,
      };
    }
    return { hours: result.hours, updated: result.updated };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to sync hours" });
  }
});

// Fix negative balances: give bonuses to all users with negative balance to bring them to 0
admin.post("/fix-negative-balances", async ({ headers, status }) => {
  const adminUser = await requireAdmin(headers as Record<string, string>);
  if (!adminUser) {
    return status(401, { error: "Unauthorized" });
  }

  try {
    // Get all user IDs
    const allUsers = await db.select({ id: usersTable.id }).from(usersTable);

    const fixed: {
      userId: number;
      username: string | null;
      deficit: number;
    }[] = [];

    for (const u of allUsers) {
      const { balance } = await getUserScrapsBalance(u.id);
      if (balance < 0) {
        const deficit = Math.abs(balance);
        await db.insert(userBonusesTable).values({
          userId: u.id,
          amount: deficit,
          reason: "negative_balance_fix",
          givenBy: adminUser.id,
        });

        const userInfo = await db
          .select({ username: usersTable.username })
          .from(usersTable)
          .where(eq(usersTable.id, u.id))
          .limit(1);

        fixed.push({
          userId: u.id,
          username: userInfo[0]?.username ?? null,
          deficit,
        });
      }
    }

    return { success: true, fixedCount: fixed.length, fixed };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to fix negative balances" });
  }
});

// CSV export of projects under review for YSWS
admin.get("/export/review-csv", async ({ headers, status }) => {
  try {
    const user = await requireReviewer(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const projects = await db
      .select({
        name: projectsTable.name,
        githubUrl: projectsTable.githubUrl,
        playableUrl: projectsTable.playableUrl,
        hackatimeProject: projectsTable.hackatimeProject,
        slackId: usersTable.slackId,
      })
      .from(projectsTable)
      .innerJoin(usersTable, eq(projectsTable.userId, usersTable.id))
      .where(
        and(
          or(
            eq(projectsTable.status, "waiting_for_review"),
            eq(projectsTable.status, "pending_admin_approval"),
          ),
          or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)),
        ),
      )
      .orderBy(desc(projectsTable.updatedAt));

    const escapeCSV = (val: string | null | undefined): string => {
      if (!val) return "";
      if (val.includes(",") || val.includes('"') || val.includes("\n")) {
        return '"' + val.replace(/"/g, '""') + '"';
      }
      return val;
    };

    const rows = ["name,code_link,demo_link,slack_id,hackatime_projects"];
    for (const p of projects) {
      rows.push(
        [
          escapeCSV(p.name),
          escapeCSV(p.githubUrl),
          escapeCSV(p.playableUrl),
          escapeCSV(p.slackId),
          escapeCSV(p.hackatimeProject),
        ].join(","),
      );
    }

    return new Response(rows.join("\n"), {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition":
          'attachment; filename="scraps-review-projects.csv"',
      },
    });
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to export review CSV" });
  }
});

admin.get("/export/review-json", async ({ headers, status }) => {
  try {
    const user = await requireReviewer(headers as Record<string, string>);
    if (!user) {
      return status(401, { error: "Unauthorized" });
    }

    const projects = await db
      .select({
        name: projectsTable.name,
        githubUrl: projectsTable.githubUrl,
        playableUrl: projectsTable.playableUrl,
        hackatimeProject: projectsTable.hackatimeProject,
        slackId: usersTable.slackId,
      })
      .from(projectsTable)
      .innerJoin(usersTable, eq(projectsTable.userId, usersTable.id))
      .where(
        and(
          or(
            eq(projectsTable.status, "waiting_for_review"),
            eq(projectsTable.status, "pending_admin_approval"),
          ),
          or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)),
        ),
      )
      .orderBy(desc(projectsTable.updatedAt));

    return projects.map((p) => {
      const hackatimeProjects = p.hackatimeProject
        ? p.hackatimeProject
            .split(",")
            .map((n: string) => n.trim())
            .filter((n: string) => n.length > 0)
        : [];

      return {
        name: p.name,
        codeLink: p.githubUrl || "",
        demoLink: p.playableUrl || "",
        submitter: { slackId: p.slackId || "" },
        hackatimeProjects,
      };
    });
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to export review JSON" });
  }
});

// Revert a shop order (admin only) - refunds scraps, restores inventory, reverses penalties, deletes order
// Admin: delete order (archive full payloads and remove timeline rows)
admin.delete("/orders/:id", async ({ params, headers, body, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return status(401, { error: "Unauthorized" });

    const orderId = parseInt(params.id);
    if (!Number.isInteger(orderId) || orderId <= 0) {
      return status(400, { error: "Invalid order id" });
    }

    const reason = (body && (body as any).reason) || null;
    if (!reason || typeof reason !== "string" || reason.trim().length < 3) {
      return status(400, {
        error: "Provide a short reason (min 3 chars) for deleting this order",
      });
    }

    const order = await db
      .select({
        id: shopOrdersTable.id,
        status: shopOrdersTable.status,
        orderType: shopOrdersTable.orderType,
        shopItemId: shopOrdersTable.shopItemId,
        quantity: shopOrdersTable.quantity,
        pricePerItem: shopOrdersTable.pricePerItem,
        totalPrice: shopOrdersTable.totalPrice,
        userId: shopOrdersTable.userId,
        shippingAddress: shopOrdersTable.shippingAddress,
        phone: shopOrdersTable.phone,
        notes: shopOrdersTable.notes,
        isFulfilled: shopOrdersTable.isFulfilled,
        createdAt: shopOrdersTable.createdAt,
        updatedAt: shopOrdersTable.updatedAt,
        itemName: shopItemsTable.name,
      })
      .from(shopOrdersTable)
      .innerJoin(
        shopItemsTable,
        eq(shopOrdersTable.shopItemId, shopItemsTable.id),
      )
      .where(eq(shopOrdersTable.id, orderId))
      .limit(1);

    if (!order[0]) return status(404, { error: "Order not found" });

    // Prevent double-archiving — attempt the select, and if the relation doesn't exist create it and retry.
    let alreadyRow = null;
    try {
      const already = await db.execute(
        sql`SELECT 1 FROM admin_deleted_orders WHERE original_order_id = ${orderId} AND restored = false LIMIT 1`,
      );
      alreadyRow =
        (already as any).rows?.[0] ??
        (Array.isArray(already) ? (already as any)[0] : null);
    } catch (err) {
      // If the table doesn't exist, create it on-demand (safe: CREATE TABLE IF NOT EXISTS)
      // and retry the select. If it's a different error, rethrow.
      const msg = (err as any)?.message ?? "";
      const code = (err as any)?.code ?? null;
      if (msg.includes("does not exist") || code === "42P01") {
        // Create the table to match the migration shape (minimal safe schema)
        await db.execute(sql`
          CREATE TABLE IF NOT EXISTS admin_deleted_orders (
            id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
            original_order_id integer NOT NULL,
            user_id integer NOT NULL,
            shop_item_id integer,
            quantity integer NOT NULL DEFAULT 1,
            price_per_item integer NOT NULL,
            total_price integer NOT NULL,
            status varchar,
            order_type varchar,
            shipping_address text,
            phone varchar,
            item_name varchar,
            created_at timestamptz,
            deleted_by integer,
            deleted_at timestamptz NOT NULL DEFAULT now(),
            reason text,
            deleted_payload jsonb,
            restored boolean NOT NULL DEFAULT false,
            restored_by integer,
            restored_at timestamptz
          );
          CREATE INDEX IF NOT EXISTS idx_admin_deleted_orders_deleted_at ON admin_deleted_orders (deleted_at DESC);
          CREATE INDEX IF NOT EXISTS idx_admin_deleted_orders_user_id ON admin_deleted_orders (user_id);
          CREATE INDEX IF NOT EXISTS idx_admin_deleted_orders_original_order_id ON admin_deleted_orders (original_order_id);
        `);
        // retry select once
        const already2 = await db.execute(
          sql`SELECT 1 FROM admin_deleted_orders WHERE original_order_id = ${orderId} AND restored = false LIMIT 1`,
        );
        alreadyRow =
          (already2 as any).rows?.[0] ??
          (Array.isArray(already2) ? (already2 as any)[0] : null);
      } else {
        throw err;
      }
    }
    if (alreadyRow) return status(409, { error: "Order already archived" });

    // collect related rows
    const [refineryOrders, refineryHistory, rolls, penalties] =
      await Promise.all([
        db
          .select()
          .from(refineryOrdersTable)
          .where(
            and(
              eq(refineryOrdersTable.userId, order[0].userId),
              eq(refineryOrdersTable.shopItemId, order[0].shopItemId),
            ),
          ),
        db
          .select()
          .from(refinerySpendingHistoryTable)
          .where(
            and(
              eq(refinerySpendingHistoryTable.userId, order[0].userId),
              eq(refinerySpendingHistoryTable.shopItemId, order[0].shopItemId),
            ),
          ),
        db
          .select()
          .from(shopRollsTable)
          .where(
            and(
              eq(shopRollsTable.userId, order[0].userId),
              eq(shopRollsTable.shopItemId, order[0].shopItemId),
            ),
          ),
        db
          .select()
          .from(shopPenaltiesTable)
          .where(
            and(
              eq(shopPenaltiesTable.userId, order[0].userId),
              eq(shopPenaltiesTable.shopItemId, order[0].shopItemId),
            ),
          ),
      ]);

    await db.transaction(async (tx) => {
      const deletedPayloadObj = {
        order: order[0] || {},
        refineryOrders: refineryOrders || [],
        refineryHistory: refineryHistory || [],
        shopRolls: rolls || [],
        shopPenalties: penalties || [],
      };
      const deletedPayload = JSON.stringify(deletedPayloadObj);

      await tx.execute(sql`INSERT INTO admin_deleted_orders (
        original_order_id, user_id, shop_item_id, quantity, price_per_item, total_price, status, order_type, shipping_address, phone, item_name, created_at,
        deleted_payload,
        deleted_by, deleted_at, reason
      ) VALUES (
        ${order[0].id}, ${order[0].userId}, ${order[0].shopItemId}, ${order[0].quantity}, ${order[0].pricePerItem}, ${order[0].totalPrice}, ${order[0].status}, ${order[0].orderType}, ${order[0].shippingAddress}, ${order[0].phone}, ${order[0].itemName}, ${order[0].createdAt},
        ${deletedPayload}::jsonb,
        ${user.id}, now(), ${reason}
      )`);

      await tx
        .delete(refinerySpendingHistoryTable)
        .where(
          and(
            eq(refinerySpendingHistoryTable.userId, order[0].userId),
            eq(refinerySpendingHistoryTable.shopItemId, order[0].shopItemId),
          ),
        );
      await tx
        .delete(refineryOrdersTable)
        .where(
          and(
            eq(refineryOrdersTable.userId, order[0].userId),
            eq(refineryOrdersTable.shopItemId, order[0].shopItemId),
          ),
        );
      await tx
        .delete(shopRollsTable)
        .where(
          and(
            eq(shopRollsTable.userId, order[0].userId),
            eq(shopRollsTable.shopItemId, order[0].shopItemId),
          ),
        );
      await tx
        .delete(shopPenaltiesTable)
        .where(
          and(
            eq(shopPenaltiesTable.userId, order[0].userId),
            eq(shopPenaltiesTable.shopItemId, order[0].shopItemId),
          ),
        );
      await tx.delete(shopOrdersTable).where(eq(shopOrdersTable.id, orderId));

      // Restore item stock for purchase/luck_win orders (count was decremented when the order was placed)
      if (
        order[0].orderType === "purchase" ||
        order[0].orderType === "luck_win"
      ) {
        await tx
          .update(shopItemsTable)
          .set({
            count: sql`${shopItemsTable.count} + ${order[0].quantity}`,
            updatedAt: new Date(),
          })
          .where(eq(shopItemsTable.id, order[0].shopItemId));
      }
    });

    console.log(
      `[ADMIN] Order #${orderId} archived/deleted by admin #${user.id}`,
    );
    return { success: true };
  } catch (err) {
    // Log full error details for diagnostics: stack, name, message, cause, and any DB-driver fields.
    // Wrap logging in a try/catch to avoid masking the original error if logging itself fails.
    try {
      console.error(
        "Admin delete order error (stack):",
        (err as any)?.stack ?? err,
      );
      console.error(
        "Admin delete order error (name):",
        (err as any)?.name ?? null,
      );
      console.error(
        "Admin delete order error (message):",
        (err as any)?.message ?? String(err),
      );
      console.error(
        "Admin delete order error (cause):",
        (err as any)?.cause ?? null,
      );
      // Some drivers attach query and params for failed queries (helpful for debugging)
      console.error(
        "Admin delete order error (query):",
        (err as any)?.query ?? null,
      );
      console.error(
        "Admin delete order error (params):",
        (err as any)?.params ?? null,
      );
      // Attempt to log the full error object including non-enumerable props
      try {
        console.error(
          "Admin delete order error (full):",
          JSON.stringify(err, Object.getOwnPropertyNames(err), 2),
        );
      } catch {
        // Fallback to a plain object log if JSON.stringify fails
        console.error("Admin delete order error (full fallback):", err);
      }
    } catch (logErr) {
      console.error("Failed to log admin delete error in detail:", logErr);
      console.error("Original error:", err);
    }

    return status(500, {
      error:
        "Failed to delete order: " + ((err as any)?.message || String(err)),
    });
  }
});

// Restore an archived order (full restore of order + related rows)
admin.post("/orders/:id/restore", async ({ params, headers, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return status(401, { error: "Unauthorized" });

    const originalOrderId = parseInt(params.id);
    if (!Number.isInteger(originalOrderId) || originalOrderId <= 0)
      return status(400, { error: "Invalid order id" });

    const archivedRes = await db.execute(
      sql`SELECT * FROM admin_deleted_orders WHERE original_order_id = ${originalOrderId} AND restored = false LIMIT 1`,
    );
    const archived =
      (archivedRes as any).rows?.[0] ??
      (Array.isArray(archivedRes) ? (archivedRes as any)[0] : null);
    if (!archived)
      return status(404, {
        error: "Archived order not found or already restored",
      });

    // parse payloads (single `deleted_payload` JSON column)
    const rawPayload = archived.deleted_payload;
    const deletedPayload =
      rawPayload == null
        ? {
            order: null,
            refineryOrders: [],
            refineryHistory: [],
            shopRolls: [],
            shopPenalties: [],
          }
        : typeof rawPayload === "string"
          ? JSON.parse(rawPayload)
          : rawPayload;
    const orderPayload = deletedPayload.order ?? null;
    const refineryOrdersPayload = deletedPayload.refineryOrders ?? [];
    const refineryHistoryPayload = deletedPayload.refineryHistory ?? [];
    const shopRollsPayload = deletedPayload.shopRolls ?? [];
    const shopPenaltiesPayload = deletedPayload.shopPenalties ?? [];

    await db.transaction(async (tx) => {
      if (!orderPayload) throw new Error("Archived order payload missing");

      // ensure no conflicting active order id
      const existing = await tx
        .select({ count: sql`count(*)` })
        .from(shopOrdersTable)
        .where(eq(shopOrdersTable.id, orderPayload.id));
      const existingCount = Number(existing[0]?.count ?? 0);
      if (existingCount > 0)
        throw new Error("Active order with that id already exists");

      // Use raw SQL with OVERRIDING SYSTEM VALUE to preserve the original order ID
      await tx.execute(sql`INSERT INTO shop_orders (id, user_id, shop_item_id, quantity, price_per_item, total_price, status, order_type, shipping_address, phone, notes, is_fulfilled, created_at, updated_at)
        OVERRIDING SYSTEM VALUE
        VALUES (${orderPayload.id}, ${orderPayload.userId}, ${orderPayload.shopItemId}, ${orderPayload.quantity}, ${orderPayload.pricePerItem}, ${orderPayload.totalPrice}, ${orderPayload.status}, ${orderPayload.orderType}, ${orderPayload.shippingAddress}, ${orderPayload.phone}, ${orderPayload.notes ?? null}, ${orderPayload.isFulfilled ?? false}, ${orderPayload.createdAt}, ${orderPayload.updatedAt ?? orderPayload.createdAt})`);

      // Related rows: omit id (auto-generated) — only the data matters, not the original IDs
      for (const r of refineryOrdersPayload) {
        await tx.insert(refineryOrdersTable).values({
          userId: r.userId,
          shopItemId: r.shopItemId,
          cost: r.cost,
          boostAmount: r.boostAmount,
          createdAt: r.createdAt,
        });
      }
      for (const h of refineryHistoryPayload) {
        await tx.insert(refinerySpendingHistoryTable).values({
          userId: h.userId,
          shopItemId: h.shopItemId,
          cost: h.cost,
          createdAt: h.createdAt,
        });
      }
      for (const rr of shopRollsPayload) {
        await tx.insert(shopRollsTable).values({
          userId: rr.userId,
          shopItemId: rr.shopItemId,
          rolled: rr.rolled,
          threshold: rr.threshold,
          won: rr.won,
          createdAt: rr.createdAt,
        });
      }
      for (const p of shopPenaltiesPayload) {
        await tx.insert(shopPenaltiesTable).values({
          userId: p.userId,
          shopItemId: p.shopItemId,
          probabilityMultiplier: p.probabilityMultiplier,
          createdAt: p.createdAt,
          updatedAt: p.updatedAt,
        });
      }

      // Decrement stock that was restored during delete (reverses the count+quantity from delete handler)
      if (
        orderPayload.orderType === "purchase" ||
        orderPayload.orderType === "luck_win"
      ) {
        await tx
          .update(shopItemsTable)
          .set({
            count: sql`GREATEST(${shopItemsTable.count} - ${orderPayload.quantity ?? 1}, 0)`,
            updatedAt: new Date(),
          })
          .where(eq(shopItemsTable.id, orderPayload.shopItemId));
      }

      await tx.execute(
        sql`UPDATE admin_deleted_orders SET restored = true, restored_by = ${user.id}, restored_at = now() WHERE id = ${archived.id}`,
      );
    });

    console.log(
      `[ADMIN] Archived order #${originalOrderId} fully restored by admin #${user.id}`,
    );
    return { success: true };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to restore archived order" });
  }
});

// Unship a shipped project (admin only) - sets it back to in_progress and zeros scraps
admin.post(
  "/projects/:id/unship",
  async ({ params, headers, body, status }) => {
    try {
      const user = await requireAdmin(headers as Record<string, string>);
      if (!user) return status(401, { error: "Unauthorized" });

      const projectId = parseInt(params.id);
      const { reason } = (body || {}) as { reason?: string };

      const project = await db
        .select({
          id: projectsTable.id,
          userId: projectsTable.userId,
          name: projectsTable.name,
          status: projectsTable.status,
          scrapsAwarded: projectsTable.scrapsAwarded,
          scrapsPaidAt: projectsTable.scrapsPaidAt,
        })
        .from(projectsTable)
        .where(eq(projectsTable.id, projectId))
        .limit(1);

      if (!project[0]) {
        return status(404, { error: "Project not found" });
      }

      if (project[0].status !== "shipped") {
        return status(400, { error: "Project is not shipped" });
      }

      const previousScraps = project[0].scrapsAwarded;

      // Set project back to in_progress and zero out scraps
      await db
        .update(projectsTable)
        .set({
          status: "in_progress",
          scrapsAwarded: 0,
          scrapsPaidAt: null,
          updatedAt: new Date(),
        })
        .where(eq(projectsTable.id, projectId));

      // Add a review record so it shows in the review history
      await db.insert(reviewsTable).values({
        projectId,
        reviewerId: user.id,
        action: "denied",
        feedbackForAuthor:
          reason?.trim() || "Project has been unshipped by an admin.",
        internalJustification: `Unshipped: removed ${previousScraps} scraps`,
      });

      return { success: true, previousScraps };
    } catch (err) {
      console.error(err);
      return status(500, { error: "Failed to unship project" });
    }
  },
);

// Get detailed financial timeline for a user (admin only)
admin.get("/users/:id/timeline", async ({ params, headers, status }) => {
  try {
    const user = await requireAdmin(headers as Record<string, string>);
    if (!user) return status(401, { error: "Unauthorized" });

    const targetUserId = parseInt(params.id);

    // Fetch all data sources in parallel
    const [paidProjects, bonusRows, shopOrders, refineryRows, refineryHistory] =
      await Promise.all([
        db
          .select({
            id: projectsTable.id,
            name: projectsTable.name,
            scrapsAwarded: projectsTable.scrapsAwarded,
            scrapsPaidAt: projectsTable.scrapsPaidAt,
            status: projectsTable.status,
            createdAt: projectsTable.createdAt,
          })
          .from(projectsTable)
          .where(
            and(
              eq(projectsTable.userId, targetUserId),
              sql`${projectsTable.scrapsAwarded} > 0`,
            ),
          ),
        db
          .select({
            id: userBonusesTable.id,
            amount: userBonusesTable.amount,
            reason: userBonusesTable.reason,
            givenBy: userBonusesTable.givenBy,
            createdAt: userBonusesTable.createdAt,
          })
          .from(userBonusesTable)
          .where(eq(userBonusesTable.userId, targetUserId)),
        db
          .select({
            id: shopOrdersTable.id,
            shopItemId: shopOrdersTable.shopItemId,
            totalPrice: shopOrdersTable.totalPrice,
            orderType: shopOrdersTable.orderType,
            status: shopOrdersTable.status,
            createdAt: shopOrdersTable.createdAt,
            itemName: shopItemsTable.name,
          })
          .from(shopOrdersTable)
          .innerJoin(
            shopItemsTable,
            eq(shopOrdersTable.shopItemId, shopItemsTable.id),
          )
          .where(eq(shopOrdersTable.userId, targetUserId)),
        db
          .select({
            id: refineryOrdersTable.id,
            shopItemId: refineryOrdersTable.shopItemId,
            cost: refineryOrdersTable.cost,
            boostAmount: refineryOrdersTable.boostAmount,
            createdAt: refineryOrdersTable.createdAt,
            itemName: shopItemsTable.name,
          })
          .from(refineryOrdersTable)
          .innerJoin(
            shopItemsTable,
            eq(refineryOrdersTable.shopItemId, shopItemsTable.id),
          )
          .where(eq(refineryOrdersTable.userId, targetUserId)),
        db
          .select({
            id: refinerySpendingHistoryTable.id,
            shopItemId: refinerySpendingHistoryTable.shopItemId,
            cost: refinerySpendingHistoryTable.cost,
            createdAt: refinerySpendingHistoryTable.createdAt,
            itemName: shopItemsTable.name,
          })
          .from(refinerySpendingHistoryTable)
          .innerJoin(
            shopItemsTable,
            eq(refinerySpendingHistoryTable.shopItemId, shopItemsTable.id),
          )
          .where(eq(refinerySpendingHistoryTable.userId, targetUserId)),
      ]);

    // Build a map of most recent purchase/win per item for lock detection
    const lastPurchaseByItem = new Map<number, Date>();
    for (const order of shopOrders) {
      if (order.orderType === "purchase" || order.orderType === "luck_win") {
        const existing = lastPurchaseByItem.get(order.shopItemId);
        const orderDate = new Date(order.createdAt);
        if (!existing || orderDate > existing) {
          lastPurchaseByItem.set(order.shopItemId, orderDate);
        }
      }
    }

    type TimelineEvent = {
      type: string;
      amount: number;
      description: string;
      date: string;
      locked?: boolean;
      itemName?: string;
      paid?: boolean;
      orderId?: number;
    };

    const timeline: TimelineEvent[] = [];

    // Earned scraps from projects
    for (const p of paidProjects) {
      timeline.push({
        type: "earned",
        amount: p.scrapsAwarded,
        description: `project "${p.name}"`,
        date: (p.scrapsPaidAt ?? p.createdAt ?? new Date()).toISOString(),
        paid: p.scrapsPaidAt !== null,
      });
    }

    // Bonuses
    for (const b of bonusRows) {
      timeline.push({
        type: "bonus",
        amount: b.amount,
        description: b.reason,
        date: b.createdAt.toISOString(),
      });
    }

    // Shop orders
    for (const o of shopOrders) {
      timeline.push({
        type: `shop_${o.orderType}`,
        amount: -o.totalPrice,
        description: o.itemName,
        date: o.createdAt.toISOString(),
        itemName: o.itemName,
        orderId: o.id,
      });
    }

    // Active refinery orders with lock status
    for (const r of refineryRows) {
      const lastPurchase = lastPurchaseByItem.get(r.shopItemId);
      const locked = !!lastPurchase && new Date(r.createdAt) <= lastPurchase;

      timeline.push({
        type: "refinery_upgrade",
        amount: -r.cost,
        description: `+${r.boostAmount}% boost for "${r.itemName}"`,
        date: r.createdAt.toISOString(),
        locked,
        itemName: r.itemName,
      });
    }

    // Consumed refinery entries (in spending history but no matching active order)
    // When a user wins, refinery orders are deleted but spending history stays
    // When undone, both order AND history are deleted (no trace remains)
    // So: history entries without a matching active order = consumed by a win
    const orderCountByItem = new Map<number, number>();
    for (const r of refineryRows) {
      orderCountByItem.set(
        r.shopItemId,
        (orderCountByItem.get(r.shopItemId) || 0) + 1,
      );
    }

    const historyByItem = new Map<number, typeof refineryHistory>();
    for (const h of refineryHistory) {
      const list = historyByItem.get(h.shopItemId) || [];
      list.push(h);
      historyByItem.set(h.shopItemId, list);
    }

    for (const [itemId, entries] of historyByItem) {
      const activeCount = orderCountByItem.get(itemId) || 0;
      // Sort oldest first - oldest entries beyond active count were consumed
      entries.sort(
        (a, b) =>
          new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
      );
      const consumedCount = Math.max(0, entries.length - activeCount);
      for (let i = 0; i < consumedCount; i++) {
        const h = entries[i];
        timeline.push({
          type: "refinery_consumed",
          amount: -h.cost,
          description: `upgrade consumed by win for "${h.itemName}"`,
          date: h.createdAt.toISOString(),
          itemName: h.itemName,
        });
      }
    }

    // Sort newest first
    timeline.sort(
      (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime(),
    );

    const balance = await getUserScrapsBalance(targetUserId);

    return { timeline, balance };
  } catch (err) {
    console.error(err);
    return status(500, { error: "Failed to fetch user timeline" });
  }
});

// Sync all submitted/pending projects to YSWS
admin.post("/sync-ysws", async ({ headers, set }) => {
  const user = await requireAdmin(headers as Record<string, string>);
  if (!user) return { error: "Unauthorized" };

  try {
    const projects = await db
      .select({
        id: projectsTable.id,
        name: projectsTable.name,
        githubUrl: projectsTable.githubUrl,
        playableUrl: projectsTable.playableUrl,
        hackatimeProject: projectsTable.hackatimeProject,
        userId: projectsTable.userId,
      })
      .from(projectsTable)
      .where(
        and(
          or(
            eq(projectsTable.status, "waiting_for_review"),
            eq(projectsTable.status, "pending_admin_approval"),
            eq(projectsTable.status, "shipped"),
          ),
          or(eq(projectsTable.deleted, 0), isNull(projectsTable.deleted)),
        ),
      );

    // Get emails for all project owners
    const userIds = [...new Set(projects.map((p) => p.userId))];
    const users =
      userIds.length > 0
        ? await db
            .select({ id: usersTable.id, email: usersTable.email })
            .from(usersTable)
            .where(inArray(usersTable.id, userIds))
        : [];
    const emailMap = new Map(users.map((u) => [u.id, u.email]));

    let synced = 0;
    let failed = 0;

    for (const project of projects) {
      const email = emailMap.get(project.userId);
      if (!email) {
        failed++;
        continue;
      }

      try {
        await submitProjectToYSWS({
          name: project.name,
          githubUrl: project.githubUrl,
          playableUrl: project.playableUrl,
          hackatimeProject: project.hackatimeProject,
          email,
        });
        synced++;
      } catch {
        failed++;
      }
    }

    console.log(
      `[ADMIN] YSWS sync complete: ${synced} synced, ${failed} failed out of ${projects.length} projects`,
    );
    return { synced, failed, total: projects.length };
  } catch (err) {
    console.error("[ADMIN] YSWS sync error:", err);
    return { error: "Failed to sync projects to YSWS" };
  }
});

// Recalculate shop item pricing from current price/stock values (admin only)
admin.post("/recalculate-shop-pricing", async ({ headers, status }) => {
  const user = await requireAdmin(headers as Record<string, string>);
  if (!user) {
    return status(401, { error: "Unauthorized" });
  }

  try {
    const updatedCount = await updateShopItemPricing();
    return { success: true, updatedCount };
  } catch (err) {
    console.error("[ADMIN] Shop pricing recalculation error:", err);
    return status(500, { error: "Failed to recalculate shop pricing" });
  }
});

admin.get("/config", async () => {
  // Public endpoint: returns canonical pricing constants for the frontend to consume.
  // These are intentionally read from the server-side constants so UI and server stay in sync.
  return {
    scrapsPerDollar: SCRAPS_PER_DOLLAR,
    dollarsPerHour: DOLLARS_PER_HOUR,
    tierMultipliers: TIER_MULTIPLIERS,
  };
});

export default admin;
