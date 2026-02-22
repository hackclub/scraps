import { eq, sql } from "drizzle-orm";
import type { PgTransaction } from "drizzle-orm/pg-core";
import { db } from "../db";
import { projectsTable } from "../schemas/projects";
import { shopOrdersTable, refinerySpendingHistoryTable } from "../schemas/shop";
import { userBonusesTable } from "../schemas/users";

export const PHI = (1 + Math.sqrt(5)) / 2;
export const MULTIPLIER = 10;
export const SCRAPS_PER_HOUR = PHI * MULTIPLIER;
export const DOLLARS_PER_HOUR = 4;
export const SCRAPS_PER_DOLLAR = SCRAPS_PER_HOUR / DOLLARS_PER_HOUR;

export const TIER_MULTIPLIERS: Record<number, number> = {
  1: 0.8,
  2: 1.0,
  3: 1.25,
  4: 1.5,
};

export interface ShopItemPricing {
  price: number;
  baseProbability: number;
  baseUpgradeCost: number;
  costMultiplier: number;
  boostAmount: number;
}

export function calculateShopItemPricing(
  monetaryValue: number,
  stockCount: number,
  upgradeBudgetMultiplier?: number,
  perRollMultiplier?: number,
): ShopItemPricing {
  const price = Math.round(monetaryValue * SCRAPS_PER_DOLLAR);

  // Rarity based on price and stock
  // Higher price = rarer, fewer stock = rarer
  // Base probability ranges from 1% (very rare) to 80% (common)
  const priceRarityFactor = Math.max(0, 1 - monetaryValue / 100); // $100+ = max rarity
  const stockRarityFactor = Math.min(1, stockCount / 20); // 20+ stock = common
  const baseProbability = Math.max(
    1,
    Math.min(
      80,
      Math.round((priceRarityFactor * 0.4 + stockRarityFactor * 0.6) * 80),
    ),
  );

  // Per-roll multiplier applied to base roll cost (admin-configurable per item)
  const perRollMult = perRollMultiplier ?? 1;

  // Roll cost at base probability (apply per-roll multiplier)
  const rollCost = Math.max(
    1,
    Math.round(price * (baseProbability / 100) * perRollMult),
  );

  // Use a start+decay upgrade cost model:
  // Use provided upgradeBudgetMultiplier if present; otherwise fall back to UPGRADE_MAX_BUDGET_MULTIPLIER
  const maxBudgetMultiplier =
    upgradeBudgetMultiplier ?? UPGRADE_MAX_BUDGET_MULTIPLIER;
  const maxBudget = Math.max(0, Math.floor(price * maxBudgetMultiplier));

  // Number of upgrades needed to go from baseProbability to 100%
  const probabilityGap = 100 - baseProbability;
  const targetUpgrades = Math.max(
    5,
    Math.min(20, Math.ceil(monetaryValue / 5)),
  );
  const boostAmount = Math.max(1, Math.round(probabilityGap / targetUpgrades));
  const actualUpgrades = Math.ceil(probabilityGap / boostAmount);

  // Base upgrade cost is a fixed fraction of price (start percent)
  let baseUpgradeCost = Math.max(1, Math.floor(price * UPGRADE_START_PERCENT));
  const costMultiplier = Math.round(UPGRADE_DECAY * 100); // store decay as percentage (e.g. 1.05 -> 105)

  // If cumulative upgrades would exceed maxBudget, scale down baseUpgradeCost until it fits
  // Compute cumulative with decay series until actualUpgrades levels or budget exceeded
  function computeCumulative(base: number): number {
    let cum = 0;
    let next = base;
    for (let i = 0; i < actualUpgrades; i++) {
      cum += Math.floor(next);
      next = next / UPGRADE_DECAY;
      if (cum > maxBudget) break;
    }
    return cum;
  }

  if (maxBudget > 0) {
    // If current cumulative exceeds budget, reduce baseUpgradeCost iteratively (small loop)
    let cum = computeCumulative(baseUpgradeCost);
    let attempts = 0;
    while (cum > maxBudget && baseUpgradeCost > 1 && attempts < 200) {
      baseUpgradeCost = Math.max(1, baseUpgradeCost - 1);
      cum = computeCumulative(baseUpgradeCost);
      attempts++;
    }
  }

  return {
    price,
    baseProbability,
    baseUpgradeCost,
    costMultiplier,
    boostAmount,
  };
}

export function calculateRollCost(
  basePrice: number,
  effectiveProbability: number,
  rollCostOverride?: number | null,
  baseProbability?: number,
  perRollMultiplier?: number,
): number {
  if (rollCostOverride != null && rollCostOverride > 0) {
    return rollCostOverride;
  }
  // Use provided baseProbability if caller wants the roll cost fixed to base;
  // otherwise use effectiveProbability. Also apply an optional per-roll multiplier.
  const probToUse = baseProbability ?? effectiveProbability;
  const multiplier = perRollMultiplier ?? 1;
  return Math.max(1, Math.round(basePrice * (probToUse / 100) * multiplier));
}

const UPGRADE_START_PERCENT = 0.25;
const UPGRADE_DECAY = 1.05;
const UPGRADE_MAX_BUDGET_MULTIPLIER = 3;

export function getUpgradeCost(
  price: number,
  upgradeCount: number,
  actualSpent?: number,
): number | null {
  const maxBudget = price * UPGRADE_MAX_BUDGET_MULTIPLIER;
  const cumulative = actualSpent ?? 0;
  if (cumulative >= maxBudget) return null;
  const nextCost = Math.max(
    1,
    Math.floor(
      (price * UPGRADE_START_PERCENT) / Math.pow(UPGRADE_DECAY, upgradeCount),
    ),
  );
  if (cumulative + nextCost > maxBudget) {
    const remaining = Math.floor(maxBudget - cumulative);
    return remaining > 0 ? remaining : null;
  }
  return nextCost;
}

export function computeRollThreshold(probability: number): number {
  // 15% house edge: displayed 50% → actual 42%, displayed 100% → actual 85%
  return Math.max(1, Math.floor((probability * 17) / 20));
}

export function calculateScrapsFromHours(
  hours: number,
  tier: number = 1,
): number {
  const tierMultiplier = TIER_MULTIPLIERS[tier] ?? 1.0;
  return Math.floor(hours * PHI * MULTIPLIER * tierMultiplier);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type DbOrTx = typeof db | PgTransaction<any, any, any>;

export async function getUserScrapsBalance(
  userId: number,
  txOrDb: DbOrTx = db,
): Promise<{
  earned: number;
  pending: number;
  spent: number;
  balance: number;
}> {
  // Earned scraps: sum of scrapsAwarded for projects that have been paid out
  const earnedResult = await txOrDb
    .select({
      total: sql<number>`COALESCE(SUM(${projectsTable.scrapsAwarded}), 0)`,
    })
    .from(projectsTable)
    .where(
      sql`${projectsTable.userId} = ${userId} AND ${projectsTable.scrapsPaidAt} IS NOT NULL`,
    );

  // Pending scraps: scrapsAwarded for shipped projects not yet paid out
  const pendingResult = await txOrDb
    .select({
      total: sql<number>`COALESCE(SUM(${projectsTable.scrapsAwarded}), 0)`,
    })
    .from(projectsTable)
    .where(
      sql`${projectsTable.userId} = ${userId} AND ${projectsTable.status} = 'shipped' AND (${projectsTable.deleted} = 0 OR ${projectsTable.deleted} IS NULL) AND ${projectsTable.scrapsPaidAt} IS NULL AND ${projectsTable.scrapsAwarded} > 0`,
    );

  const bonusResult = await txOrDb
    .select({
      total: sql<number>`COALESCE(SUM(${userBonusesTable.amount}), 0)`,
    })
    .from(userBonusesTable)
    .where(eq(userBonusesTable.userId, userId));

  const spentResult = await txOrDb
    .select({
      total: sql<number>`COALESCE(SUM(${shopOrdersTable.totalPrice}), 0)`,
    })
    .from(shopOrdersTable)
    .where(eq(shopOrdersTable.userId, userId));

  // Calculate scraps spent on refinery upgrades (permanent history, only deleted on undo)
  const upgradeSpentResult = await txOrDb
    .select({
      total: sql<number>`COALESCE(SUM(${refinerySpendingHistoryTable.cost}), 0)`,
    })
    .from(refinerySpendingHistoryTable)
    .where(eq(refinerySpendingHistoryTable.userId, userId));

  const projectEarned = Number(earnedResult[0]?.total) || 0;
  const pending = Number(pendingResult[0]?.total) || 0;
  const bonusEarned = Number(bonusResult[0]?.total) || 0;
  const earned = projectEarned + bonusEarned;
  const shopSpent = Number(spentResult[0]?.total) || 0;
  const upgradeSpent = Number(upgradeSpentResult[0]?.total) || 0;
  const spent = shopSpent + upgradeSpent;
  const balance = earned - spent;

  return { earned, pending, spent, balance };
}

export async function canAfford(
  userId: number,
  cost: number,
  txOrDb: DbOrTx = db,
): Promise<boolean> {
  if (cost < 0) return false;
  if (!Number.isFinite(cost)) return false;

  const { balance } = await getUserScrapsBalance(userId, txOrDb);

  if (!Number.isFinite(balance)) return false;

  return balance >= cost;
}
