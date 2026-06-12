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

  const maxBudgetMultiplier =
    upgradeBudgetMultiplier ?? UPGRADE_MAX_BUDGET_MULTIPLIER;
  const maxBudget = Math.max(0, Math.floor(price * maxBudgetMultiplier));

  const probabilityGap = 100 - baseProbability;
  const targetUpgrades = Math.max(
    5,
    Math.min(20, Math.ceil(monetaryValue / 5)),
  );
  const boostAmount = Math.max(1, Math.round(probabilityGap / targetUpgrades));
  const actualUpgrades = Math.ceil(probabilityGap / boostAmount);

  let baseUpgradeCost = Math.max(1, Math.floor(price * UPGRADE_START_PERCENT));
  const costMultiplier = Math.round(UPGRADE_DECAY * 100);

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
): number {
  if (rollCostOverride != null && rollCostOverride > 0) {
    return rollCostOverride;
  }
  const probToUse = baseProbability ?? effectiveProbability;
  return Math.max(1, Math.round(basePrice * (probToUse / 100)));
}

const UPGRADE_START_PERCENT = 0.25;
const UPGRADE_DECAY = 1.05;
const UPGRADE_MAX_BUDGET_MULTIPLIER = 3;

export function getUpgradeCost(
  price: number,
  upgradeCount: number,
  actualSpent?: number,
  baseUpgradeCost?: number,
): number | null {
  const maxBudget = price * UPGRADE_MAX_BUDGET_MULTIPLIER;
  const cumulative = actualSpent ?? 0;
  if (cumulative >= maxBudget) return null;
  const base = baseUpgradeCost ?? Math.max(1, Math.floor(price * UPGRADE_START_PERCENT));
  const nextCost = Math.max(
    1,
    Math.floor(base / Math.pow(UPGRADE_DECAY, upgradeCount)),
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
  // Earned scraps: sum of paid amounts for projects that have been paid out
  // Use scrapsPaidAmount if set, otherwise fall back to scrapsAwarded for legacy projects
  // that were paid before scrapsPaidAmount was introduced
  const earnedResult = await txOrDb
    .select({
      total: sql<number>`COALESCE(SUM(CASE WHEN ${projectsTable.scrapsPaidAmount} > 0 THEN ${projectsTable.scrapsPaidAmount} ELSE ${projectsTable.scrapsAwarded} END), 0)`,
    })
    .from(projectsTable)
    .where(
      sql`${projectsTable.userId} = ${userId} AND (${projectsTable.scrapsPaidAt} IS NOT NULL OR ${projectsTable.scrapsPaidAmount} > 0) AND ${projectsTable.scrapsAwarded} > 0`,
    );

  // Pending scraps: scrapsAwarded for shipped unpaid projects
  const pendingResult = await txOrDb
    .select({
      total: sql<number>`COALESCE(SUM(${projectsTable.scrapsAwarded} - CASE WHEN ${projectsTable.scrapsPaidAmount} > 0 THEN ${projectsTable.scrapsPaidAmount} ELSE 0 END), 0)`,
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
    .where(
      sql`${shopOrdersTable.userId} = ${userId} AND ${shopOrdersTable.status} NOT IN ('cancelled', 'deleted')`,
    );

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
