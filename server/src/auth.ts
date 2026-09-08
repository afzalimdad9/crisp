import { createRemoteJWKSet, jwtVerify, SignJWT } from "jose";
import type { MiddlewareHandler } from "hono";
import { env } from "./env.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const appleJWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const sessionKey = new TextEncoder().encode(env.JWT_SECRET);

/// Verifies a "Sign in with Apple" identity token against Apple's public keys,
/// checking issuer and audience (= our bundle id). Returns the stable user id
/// (`sub`) and email if present.
export async function verifyAppleIdentityToken(idToken: string): Promise<{ sub: string; email: string | null }> {
  const { payload } = await jwtVerify(idToken, appleJWKS, {
    issuer: APPLE_ISSUER,
    audience: env.APPLE_BUNDLE_ID,
  });
  if (!payload.sub) throw new Error("Apple token missing subject");
  const email = typeof payload.email === "string" ? payload.email : null;
  return { sub: payload.sub, email };
}

/// Issues our own 30-day session token for a user id.
export async function issueSessionToken(userId: string): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime("30d")
    .sign(sessionKey);
}

async function verifySessionToken(token: string): Promise<string> {
  const { payload } = await jwtVerify(token, sessionKey);
  if (!payload.sub) throw new Error("session token missing subject");
  return payload.sub;
}

/// Hono middleware: requires a valid `Authorization: Bearer <token>` and stashes
/// the user id at `c.get("userId")`.
export const requireAuth: MiddlewareHandler<{ Variables: { userId: string } }> = async (c, next) => {
  const header = c.req.header("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return c.json({ error: "missing bearer token" }, 401);
  try {
    c.set("userId", await verifySessionToken(token));
  } catch {
    return c.json({ error: "invalid or expired token" }, 401);
  }
  await next();
};
