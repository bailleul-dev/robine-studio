import { NextRequest, NextResponse } from "next/server";

import { getUserForRequest } from "@/lib/auth/session";

export async function GET(request: NextRequest) {
  const user = await getUserForRequest(request);
  if (!user) return NextResponse.json({ error: "Non authentifié." }, { status: 401 });
  return NextResponse.json({ user });
}
