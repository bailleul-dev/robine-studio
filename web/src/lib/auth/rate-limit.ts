import { createHash } from "node:crypto";

import { getSql } from "@/db";

export async function consumeRateLimit(
  action: string,
  identifier: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  const key = createHash("sha256").update(`${action}:${identifier}`).digest("hex");
  const sql = getSql();
  const [result] = await sql<{ attempts: number }[]>`
    INSERT INTO auth_rate_limits (key, attempts, window_started_at)
    VALUES (${key}, 1, NOW())
    ON CONFLICT (key) DO UPDATE SET
      attempts = CASE
        WHEN auth_rate_limits.window_started_at < NOW() - (${windowSeconds} * INTERVAL '1 second') THEN 1
        ELSE auth_rate_limits.attempts + 1
      END,
      window_started_at = CASE
        WHEN auth_rate_limits.window_started_at < NOW() - (${windowSeconds} * INTERVAL '1 second') THEN NOW()
        ELSE auth_rate_limits.window_started_at
      END
    RETURNING attempts
  `;
  return Boolean(result && result.attempts <= limit);
}

export function requestIdentifier(request: Request, email: string): string {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const address = forwarded || request.headers.get("x-real-ip") || "unknown";
  return `${address}:${email}`;
}
