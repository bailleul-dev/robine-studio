import { describe, expect, it } from "vitest";

import { loginSchema, registerSchema } from "./validation";

describe("auth validation", () => {
  it("normalizes email addresses", () => {
    const result = registerSchema.parse({
      email: "  ARTISTE@Example.COM ",
      password: "une phrase de passe",
      displayName: " Artiste ",
    });
    expect(result.email).toBe("artiste@example.com");
    expect(result.displayName).toBe("Artiste");
  });

  it("rejects short registration passwords", () => {
    expect(registerSchema.safeParse({ email: "a@b.fr", password: "court", displayName: "AB" }).success).toBe(false);
  });

  it("keeps login errors generic by accepting any non-empty password shape", () => {
    expect(loginSchema.safeParse({ email: "a@b.fr", password: "x" }).success).toBe(true);
  });
});
