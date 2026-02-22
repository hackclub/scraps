import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import { config } from "../config";

/**
 * Create a managed PG pool with conservative defaults and an error handler.
 * This prevents unhandled pool/client errors from terminating the process
 * and provides sensible timeouts for development and production.
 */
const pool = new Pool({
  max: 10,
  connectionString: config.databaseUrl,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 30000,
});

pool.on("error", (err) => {
  console.error("[DB_POOL] Unexpected idle client error", err);
  // Do not rethrow here. Let the app decide how to handle transient DB issues.
});

// Gracefully close pool on process shutdown
process.on("beforeExit", async () => {
  try {
    await pool.end();
  } catch (err) {
    console.warn("[DB_POOL] Error shutting down pool", err);
  }
});

export const db = drizzle(pool);
export { pool as pgPool };
