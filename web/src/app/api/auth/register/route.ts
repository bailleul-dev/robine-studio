import { randomUUID } from "node:crypto";

import { eq } from "drizzle-orm";
import { NextResponse } from "next/server";

import { getDb } from "@/db";
import { sessions, users } from "@/db/schema";
import { hashPassword } from "@/lib/auth/password";
import { consumeRateLimit, requestIdentifier } from "@/lib/auth/rate-limit";
import { assertSameOrigin, HttpError, publicError, readJson } from "@/lib/auth/request";
import { issueSession, setSessionCookie } from "@/lib/auth/session";
import { firstValidationError, registerSchema } from "@/lib/auth/validation";

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const parsed = registerSchema.safeParse(await readJson(request));
    if (!parsed.success) throw new HttpError(400, firstValidationError(parsed.error));

    const { email, password, displayName } = parsed.data;
    const allowed = await consumeRateLimit("register", requestIdentifier(request, email), 5, 60 * 60);
    if (!allowed) throw new HttpError(429, "Trop de tentatives. Réessayez plus tard.");

    const database = getDb();
    const [existing] = await database.select({ id: users.id }).from(users).where(eq(users.email, email)).limit(1);
    if (existing) throw new HttpError(409, "Un compte utilise déjà cette adresse e-mail.");

    const userId = randomUUID();
    const session = issueSession(userId);
    const passwordHash = await hashPassword(password);

    await database.transaction(async (transaction) => {
      await transaction.insert(users).values({ id: userId, email, displayName, passwordHash });
      await transaction.insert(sessions).values(session.row);
    });

    const response = NextResponse.json({ user: { id: userId, email, displayName } }, { status: 201 });
    setSessionCookie(response, session.token, session.expiresAt);
    return response;
  } catch (error) {
    const result = publicError(error);
    return NextResponse.json({ error: result.message }, { status: result.status });
  }
}
