export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export function assertSameOrigin(request: Request): void {
  const origin = request.headers.get("origin");
  const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
  if (!origin || !host) throw new HttpError(403, "Requête refusée.");

  let originHost: string;
  try {
    originHost = new URL(origin).host;
  } catch {
    throw new HttpError(403, "Requête refusée.");
  }
  if (originHost !== host) throw new HttpError(403, "Requête refusée.");
}

export async function readJson(request: Request): Promise<unknown> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    throw new HttpError(415, "Le corps doit être envoyé en JSON.");
  }
  try {
    return await request.json();
  } catch {
    throw new HttpError(400, "JSON invalide.");
  }
}

export function publicError(error: unknown) {
  if (error instanceof HttpError) {
    return { status: error.status, message: error.message };
  }
  console.error(error);
  return { status: 500, message: "Une erreur inattendue est survenue." };
}
