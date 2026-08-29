import { describe, expect, it } from "vitest";

import { assertSameOrigin, HttpError } from "./request";

describe("origin protection", () => {
  it("accepts a request from the same host", () => {
    const request = new Request("https://amp.robine.fr/api/auth/login", {
      headers: { origin: "https://amp.robine.fr", host: "amp.robine.fr" },
    });
    expect(() => assertSameOrigin(request)).not.toThrow();
  });

  it("rejects cross-site and origin-less requests", () => {
    const crossSite = new Request("https://amp.robine.fr/api/auth/login", {
      headers: { origin: "https://evil.example", host: "amp.robine.fr" },
    });
    expect(() => assertSameOrigin(crossSite)).toThrow(HttpError);
    expect(() => assertSameOrigin(new Request("https://amp.robine.fr"))).toThrow(HttpError);
  });
});
