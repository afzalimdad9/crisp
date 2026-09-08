import { randomUUID } from "node:crypto";
import pg from "pg";
import { env } from "./env.js";

export interface User {
  id: string;
  appleSub: string;
  email: string | null;
  createdAt: string;
}

/// Persistence for users, the credit ledger and jobs. Two implementations:
/// Postgres (when DATABASE_URL is set) and in-memory (local dev).
export interface Store {
  init(): Promise<void>;
  /// Returns the existing user for this Apple subject, or creates one (granting
  /// the free-minutes signup bonus). `isNew` tells the caller a grant happened.
  upsertUser(appleSub: string, email: string | null): Promise<{ user: User; isNew: boolean }>;
  getUser(id: string): Promise<User | null>;
  balanceMinutes(userId: string): Promise<number>;
  /// Append a ledger entry. `ref` is a unique idempotency key (no-op if it
  /// already exists) — used for signup grants and, later, Stripe webhooks.
  addLedger(userId: string, deltaMinutes: number, reason: string, ref?: string): Promise<void>;
  recordJob(userId: string, durationSec: number, minutesCharged: number, provider: string): Promise<void>;
}

// ── Postgres ──────────────────────────────────────────────────────────────────

class PgStore implements Store {
  private pool: pg.Pool;
  constructor(connectionString: string) {
    // Railway's private network (.railway.internal) and local Postgres don't use
    // SSL; the public proxy host does.
    const noSSL =
      connectionString.includes("localhost") ||
      connectionString.includes("127.0.0.1") ||
      connectionString.includes(".railway.internal");
    this.pool = new pg.Pool({
      connectionString,
      ssl: noSSL ? false : { rejectUnauthorized: false },
    });
  }

  async init() {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id text PRIMARY KEY,
        apple_sub text UNIQUE NOT NULL,
        email text,
        created_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE TABLE IF NOT EXISTS credit_ledger (
        id text PRIMARY KEY,
        user_id text NOT NULL REFERENCES users(id),
        delta_minutes numeric NOT NULL,
        reason text NOT NULL,
        ref text UNIQUE,
        created_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE TABLE IF NOT EXISTS jobs (
        id text PRIMARY KEY,
        user_id text NOT NULL REFERENCES users(id),
        status text NOT NULL,
        duration_sec numeric NOT NULL,
        minutes_charged numeric NOT NULL,
        provider text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now()
      );
    `);
  }

  async upsertUser(appleSub: string, email: string | null) {
    const existing = await this.pool.query<{ id: string; apple_sub: string; email: string | null; created_at: string }>(
      "SELECT id, apple_sub, email, created_at FROM users WHERE apple_sub = $1",
      [appleSub]
    );
    if (existing.rows[0]) {
      return { user: toUser(existing.rows[0]), isNew: false };
    }
    const id = randomUUID();
    const row = await this.pool.query(
      "INSERT INTO users (id, apple_sub, email) VALUES ($1, $2, $3) RETURNING id, apple_sub, email, created_at",
      [id, appleSub, email]
    );
    await this.addLedger(id, env.FREE_MINUTES, "signup_grant", `grant:${id}`);
    return { user: toUser(row.rows[0]), isNew: true };
  }

  async getUser(id: string) {
    const r = await this.pool.query("SELECT id, apple_sub, email, created_at FROM users WHERE id = $1", [id]);
    return r.rows[0] ? toUser(r.rows[0]) : null;
  }

  async balanceMinutes(userId: string) {
    const r = await this.pool.query<{ sum: string | null }>(
      "SELECT COALESCE(SUM(delta_minutes), 0) AS sum FROM credit_ledger WHERE user_id = $1",
      [userId]
    );
    return Number(r.rows[0]?.sum ?? 0);
  }

  async addLedger(userId: string, deltaMinutes: number, reason: string, ref?: string) {
    await this.pool.query(
      "INSERT INTO credit_ledger (id, user_id, delta_minutes, reason, ref) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (ref) DO NOTHING",
      [randomUUID(), userId, deltaMinutes, reason, ref ?? null]
    );
  }

  async recordJob(userId: string, durationSec: number, minutesCharged: number, provider: string) {
    await this.pool.query(
      "INSERT INTO jobs (id, user_id, status, duration_sec, minutes_charged, provider) VALUES ($1, $2, 'done', $3, $4, $5)",
      [randomUUID(), userId, durationSec, minutesCharged, provider]
    );
  }
}

function toUser(r: { id: string; apple_sub: string; email: string | null; created_at: string }): User {
  return { id: r.id, appleSub: r.apple_sub, email: r.email, createdAt: String(r.created_at) };
}

// ── In-memory (local dev) ─────────────────────────────────────────────────────

class MemoryStore implements Store {
  private users = new Map<string, User>();
  private ledger: { userId: string; delta: number; reason: string; ref?: string }[] = [];

  async init() {}

  async upsertUser(appleSub: string, email: string | null) {
    const found = [...this.users.values()].find((u) => u.appleSub === appleSub);
    if (found) return { user: found, isNew: false };
    const user: User = { id: randomUUID(), appleSub, email, createdAt: new Date().toISOString() };
    this.users.set(user.id, user);
    await this.addLedger(user.id, env.FREE_MINUTES, "signup_grant", `grant:${user.id}`);
    return { user, isNew: true };
  }

  async getUser(id: string) {
    return this.users.get(id) ?? null;
  }

  async balanceMinutes(userId: string) {
    return this.ledger.filter((l) => l.userId === userId).reduce((sum, l) => sum + l.delta, 0);
  }

  async addLedger(userId: string, deltaMinutes: number, reason: string, ref?: string) {
    if (ref && this.ledger.some((l) => l.ref === ref)) return;
    this.ledger.push({ userId, delta: deltaMinutes, reason, ref });
  }

  async recordJob() {}
}

export function makeStore(): Store {
  return env.DATABASE_URL ? new PgStore(env.DATABASE_URL) : new MemoryStore();
}
