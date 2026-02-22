import { db } from "../db";
import { shopItemsTable } from "../schemas/shop";
import { eq } from "drizzle-orm";
import {
  calculateShopItemPricing,
  calculateRollCost,
  computeRollThreshold,
  SCRAPS_PER_DOLLAR,
} from "./scraps";

/**
 * Compute optimal shop item pricing from real-world cost.
 *
 * @param dollarCost  - what the item costs us in USD
 * @param baseProbability - desired base win chance 1-100 (optional, auto-computed if omitted)
 * @param stockCount  - how many we have in stock (used for auto-probability)
 * @returns full pricing breakdown including scraps price, roll cost, upgrade curve
 */
export function computeItemPricing(
  dollarCost: number,
  baseProbability?: number,
  stockCount: number = 1,
): {
  /** scraps price (item face value) */
  price: number;
  /** base win probability 1-100 */
  baseProbability: number;
  /** cost of first refinery upgrade */
  baseUpgradeCost: number;
  /** multiplier per upgrade level (percentage, e.g. 110 = 1.1x) */
  costMultiplier: number;
  /** probability boost per upgrade */
  boostAmount: number;
  /** cost per roll attempt at base probability */
  rollCost: number;
  /** estimated rolls to win at base probability */
  expectedRollsAtBase: number;
  /** expected total roll spend at base probability */
  expectedSpendAtBase: number;
  /** dollar cost input */
  dollarCost: number;
  /** scraps per dollar used */
  scrapsPerDollar: number;
} {
  // Delegate core pricing calculation to the canonical helper so admin previews
  // and bulk recalculations stay consistent with live logic.
  const pricing = calculateShopItemPricing(dollarCost, stockCount);

  const price = pricing.price;
  // If caller provided an explicit baseProbability, prefer it for displayed values,
  // otherwise use the computed baseProbability from the canonical helper.
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
