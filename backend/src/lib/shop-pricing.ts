import { db } from "../db";
import { shopItemsTable } from "../schemas/shop";
import { eq } from "drizzle-orm";
import {
  calculateShopItemPricing,
  calculateRollCost,
  computeRollThreshold,
  SCRAPS_PER_DOLLAR,
} from "./scraps";

export function computeItemPricing(
  dollarCost: number,
  baseProbability?: number,
  stockCount: number = 1,
): {
  price: number;
  baseProbability: number;
  baseUpgradeCost: number;
  costMultiplier: number;
  boostAmount: number;
  rollCost: number;
  expectedRollsAtBase: number;
  expectedSpendAtBase: number;
  dollarCost: number;
  scrapsPerDollar: number;
} {
  const pricing = calculateShopItemPricing(dollarCost, stockCount);
  const price = pricing.price;
  const prob =
    baseProbability !== undefined &&
    baseProbability >= 1 &&
    baseProbability <= 100
      ? Math.round(baseProbability)
      : pricing.baseProbability;

  const rollCost = calculateRollCost(price, prob, undefined, prob);

  const threshold = computeRollThreshold(prob);
  const expectedRollsAtBase =
    threshold > 0 ? Math.round((100 / threshold) * 10) / 10 : Infinity;
  const expectedSpendAtBase = Math.round(rollCost * expectedRollsAtBase);

  return {
    price,
    baseProbability: prob,
    baseUpgradeCost: pricing.baseUpgradeCost,
    costMultiplier: pricing.costMultiplier,
    boostAmount: pricing.boostAmount,
    rollCost,
    expectedRollsAtBase,
    expectedSpendAtBase,
    dollarCost,
    scrapsPerDollar: SCRAPS_PER_DOLLAR,
  };
}

export async function updateShopItemPricing(): Promise<number> {
  try {
    const items = await db
      .select({
        id: shopItemsTable.id,
        name: shopItemsTable.name,
        price: shopItemsTable.price,
        count: shopItemsTable.count,
      })
      .from(shopItemsTable);

    let updated = 0;
    for (const item of items) {
      const monetaryValue = item.price / SCRAPS_PER_DOLLAR;
      const pricing = calculateShopItemPricing(monetaryValue, item.count);

      await db
        .update(shopItemsTable)
        .set({
          baseProbability: pricing.baseProbability,
          baseUpgradeCost: pricing.baseUpgradeCost,
          costMultiplier: pricing.costMultiplier,
          boostAmount: pricing.boostAmount,
          updatedAt: new Date(),
        })
        .where(eq(shopItemsTable.id, item.id));

      updated++;
    }

    console.log(`[SHOP-PRICING] Updated pricing for ${updated} shop items`);
    return updated;
  } catch (err) {
    console.error("[SHOP-PRICING] Failed to update shop item pricing:", err);
    return 0;
  }
}
