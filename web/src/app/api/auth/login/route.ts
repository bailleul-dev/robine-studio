import { eq } from "drizzle-orm";
import { NextResponse } from "next/server";

import { getDb } from "@/db";
import { sessions, users } from "@/db/schema";
import { verifyPassword } from "@/lib/auth/password";
import { consumeRateLimit, requestIdentifier } from "@/lib/auth/rate-limit";
import { assertSameOrigin, HttpError, publicError, readJson } from "@/lib/auth/request";
import { issueSession, setSessionCookie } from "@/lib/auth/session";
import { firstValidationError, loginSchema } from "@/lib/auth/validation";

export async function POST(request: Request) {
  try {
    assertSameOrigin(request);
    const parsed = loginSchema.safeParse(await readJson(request));
    if (!parsed.success) throw new HttpError(400, firstValidationError(parsed.error));

    const { email, password } = parsed.data;
    const allowed = await consumeRateLimit("login", requestIdentifier(request, email), 10, 15 * 60);
    if (!allowed) throw new HttpError(429, "Trop de tentatives. Réessayez dans quelques minutes.");

    const [user] = await getDb().select().from(users).where(eq(users.email, email)).limit(1);
    if (!user || !(await verifyPassword(password, user.passwordHash))) {
      throw new HttpError(401, "E-mail ou mot de passe incorrect.");
    }

    const session = issueSession(user.id);
    await getDb().insert(sessions).values(session.row);

    const response = NextResponse.json({
      user: { id: user.id, email: user.email, displayName: user.displayName },
    });
    setSessionCookie(response, session.token, session.expiresAt);
    return response;
  } catch (error) {
    const result = publicError(error);
    return NextResponse.json({ error: result.message }, { status: result.status });
  }
}
