import { describe, expect, it } from "vitest";

import { hashPassword, verifyPassword } from "./password";

describe("password hashing", () => {
  it("accepts the original password and rejects another one", async () => {
    const hash = await hashPassword("une phrase de passe solide");
    expect(hash).not.toContain("une phrase de passe solide");
    await expect(verifyPassword("une phrase de passe solide", hash)).resolves.toBe(true);
    await expect(verifyPassword("mauvaise phrase", hash)).resolves.toBe(false);
  });

  it("rejects malformed hashes", async () => {
    await expect(verifyPassword("anything", "broken" )).resolves.toBe(false);
  });
});
