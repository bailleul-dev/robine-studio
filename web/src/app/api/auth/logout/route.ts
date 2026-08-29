import { eq } from "drizzle-orm";
import { NextRequest, NextResponse } from "next/server";

import { getDb } from "@/db";
import { sessions } from "@/db/schema";
import { assertSameOrigin, publicError } from "@/lib/auth/request";
import { clearSessionCookie, hashSessionToken, SESSION_COOKIE } from "@/lib/auth/session";

export async function POST(request: NextRequest) {
  try {
    assertSameOrigin(request);
    const token = request.cookies.get(SESSION_COOKIE)?.value;
    if (token) {
      await getDb().delete(sessions).where(eq(sessions.tokenHash, hashSessionToken(token)));
    }
    const response = NextResponse.json({ success: true });
    clearSessionCookie(response);
    return response;
  } catch (error) {
    const result = publicError(error);
    return NextResponse.json({ error: result.message }, { status: result.status });
  }
}
