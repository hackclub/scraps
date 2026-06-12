import {
  integer,
  real,
  pgTable,
  varchar,
  timestamp,
  unique,
  text,
  boolean,
  jsonb,
  index,
} from "drizzle-orm/pg-core";
import { usersTable } from "./users";

export const shopItemsTable = pgTable("shop_items", {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  name: varchar().notNull(),
  image: varchar().notNull(),
  description: varchar().notNull(),
  price: integer().notNull(),
  category: varchar().notNull(),
  count: integer().notNull().default(0),
  baseProbability: integer("base_probability").notNull().default(50),
  baseUpgradeCost: integer("base_upgrade_cost").notNull().default(10),
  costMultiplier: integer("cost_multiplier").notNull().default(115),
  boostAmount: integer("boost_amount").notNull().default(1),
  rollCostOverride: integer("roll_cost_override"),
  perRollMultiplier: real("per_roll_multiplier").notNull().default(0.05),
  upgradeBudgetMultiplier: real("upgrade_budget_multiplier")
    .notNull()
    .default(3.0),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export const shopHeartsTable = pgTable(
  "shop_hearts",
  {
    id: integer().primaryKey().generatedAlwaysAsIdentity(),
    userId: integer("user_id")
      .notNull()
      .references(() => usersTable.id),
    shopItemId: integer("shop_item_id")
      .notNull()
      .references(() => shopItemsTable.id),
    createdAt: timestamp("created_at").defaultNow().notNull(),
  },
  (table) => [unique().on(table.userId, table.shopItemId)],
);

export const shopOrdersTable = pgTable("shop_orders", {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  userId: integer("user_id")
    .notNull()
    .references(() => usersTable.id),
  shopItemId: integer("shop_item_id")
    .notNull()
    .references(() => shopItemsTable.id),
  quantity: integer().notNull().default(1),
  pricePerItem: integer("price_per_item").notNull(),
  totalPrice: integer("total_price").notNull(),
  status: varchar().notNull().default("pending"),
  orderType: varchar("order_type").notNull().default("purchase"),
  shippingAddress: text("shipping_address"),
  phone: varchar(),
  notes: text(),
  trackingNumber: varchar("tracking_number"),
  isFulfilled: boolean("is_fulfilled").notNull().default(false),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export const shopRollsTable = pgTable("shop_rolls", {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  userId: integer("user_id")
    .notNull()
    .references(() => usersTable.id),
  shopItemId: integer("shop_item_id")
    .notNull()
    .references(() => shopItemsTable.id),
  rolled: integer().notNull(),
  threshold: integer().notNull(),
  won: boolean().notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const refineryOrdersTable = pgTable("refinery_orders", {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  userId: integer("user_id")
    .notNull()
    .references(() => usersTable.id),
  shopItemId: integer("shop_item_id")
    .notNull()
    .references(() => shopItemsTable.id),
  cost: integer().notNull(),
  boostAmount: integer("boost_amount").notNull().default(1),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const shopPenaltiesTable = pgTable(
  "shop_penalties",
  {
    id: integer().primaryKey().generatedAlwaysAsIdentity(),
    userId: integer("user_id")
      .notNull()
      .references(() => usersTable.id),
    shopItemId: integer("shop_item_id")
      .notNull()
      .references(() => shopItemsTable.id),
    probabilityMultiplier: integer("probability_multiplier")
      .notNull()
      .default(100),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    updatedAt: timestamp("updated_at").defaultNow().notNull(),
  },
  (table) => [unique().on(table.userId, table.shopItemId)],
);

export const refinerySpendingHistoryTable = pgTable(
  "refinery_spending_history",
  {
    id: integer().primaryKey().generatedAlwaysAsIdentity(),
    userId: integer("user_id")
      .notNull()
      .references(() => usersTable.id),
    shopItemId: integer("shop_item_id")
      .notNull()
      .references(() => shopItemsTable.id),
    cost: integer().notNull(),
    createdAt: timestamp("created_at").defaultNow().notNull(),
  },
);

export const adminDeletedOrdersTable = pgTable(
  "admin_deleted_orders",
  {
    id: integer().primaryKey().generatedAlwaysAsIdentity(),
    originalOrderId: integer("original_order_id").notNull(),
    userId: integer("user_id").notNull(),
    shopItemId: integer("shop_item_id"),
    quantity: integer().notNull().default(1),
    pricePerItem: integer("price_per_item").notNull(),
    totalPrice: integer("total_price").notNull(),
    status: varchar(),
    orderType: varchar("order_type"),
    shippingAddress: text("shipping_address"),
    phone: varchar(),
    itemName: varchar("item_name"),
    createdAt: timestamp("created_at", { withTimezone: true }),
    deletedBy: integer("deleted_by"),
    deletedAt: timestamp("deleted_at", { withTimezone: true }).defaultNow().notNull(),
    reason: text(),
    deletedPayload: jsonb("deleted_payload"),
    restored: boolean().notNull().default(false),
    restoredBy: integer("restored_by"),
    restoredAt: timestamp("restored_at", { withTimezone: true }),
  },
  (table) => [
    index("idx_admin_deleted_orders_deleted_at").on(table.deletedAt),
    index("idx_admin_deleted_orders_user_id").on(table.userId),
    index("idx_admin_deleted_orders_original_order_id").on(table.originalOrderId),
  ],
);
