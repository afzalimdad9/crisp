/// Centralized, typed access to environment configuration.
export const env = {
  PORT: Number(process.env.PORT ?? 8787),
  DATABASE_URL: process.env.DATABASE_URL?.trim() || "",
  APPLE_BUNDLE_ID: process.env.APPLE_BUNDLE_ID?.trim() || "com.wisedt.WiseEdit",
  JWT_SECRET: process.env.JWT_SECRET?.trim() || "dev-secret-change-me",
  DEEPGRAM_API_KEY: process.env.DEEPGRAM_API_KEY?.trim() || "",
  FREE_MINUTES: Number(process.env.FREE_MINUTES ?? 10),
  DEV_AUTH: process.env.DEV_AUTH?.trim() === "1",
  get isProd() {
    return process.env.NODE_ENV === "production";
  },
};
