import { createHash, randomBytes, randomUUID } from "node:crypto";

import { and, eq, gt } from "drizzle-orm";
import type { NextRequest, NextResponse } from "next/server";

import { getDb } from "@/db";
import { sessions, users } from "@/db/schema";

export const SESSION_COOKIE = "robine_session";
const SESSION_DURATION_MS = 30 * 24 * 60 * 60 * 1000;

export function hashSessionToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function issueSession(userId: string) {
  const token = randomBytes(32).toString("base64url");
  const expiresAt = new Date(Date.now() + SESSION_DURATION_MS);
  return {
    token,
    expiresAt,
    row: {
      id: randomUUID(),
      userId,
      tokenHash: hashSessionToken(token),
      expiresAt,
    },
  };
}

export function setSessionCookie(response: NextResponse, token: string, expiresAt: Date) {
  response.cookies.set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    expires: expiresAt,
  });
}

export function clearSessionCookie(response: NextResponse) {
  response.cookies.set(SESSION_COOKIE, "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
}

export async function getUserForToken(token: string | undefined) {
  if (!token) return null;

  const [result] = await getDb()
    .select({
      id: users.id,
      email: users.email,
      displayName: users.displayName,
      createdAt: users.createdAt,
    })
    .from(sessions)
    .innerJoin(users, eq(sessions.userId, users.id))
    .where(and(eq(sessions.tokenHash, hashSessionToken(token)), gt(sessions.expiresAt, new Date())))
    .limit(1);

  return result ?? null;
}

export function getUserForRequest(request: NextRequest) {
  return getUserForToken(request.cookies.get(SESSION_COOKIE)?.value);
}
