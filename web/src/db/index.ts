import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";

import * as schema from "./schema";

type Database = ReturnType<typeof drizzle<typeof schema>>;

let client: ReturnType<typeof postgres> | undefined;
let db: Database | undefined;

function databaseUrl() {
  const value = process.env.DATABASE_URL;
  if (!value) {
    throw new Error("DATABASE_URL is not configured");
  }
  return value;
}

export function getDb(): Database {
  if (!client) {
    client = postgres(databaseUrl(), {
      max: process.env.NODE_ENV === "production" ? 10 : 3,
      idle_timeout: 20,
      prepare: false,
    });
    db = drizzle(client, { schema });
  }
  return db!;
}

export function getSql() {
  if (!client) getDb();
  return client!;
}
