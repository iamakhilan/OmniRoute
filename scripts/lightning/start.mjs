#!/usr/bin/env node
/**
 * Lightning AI Studio launcher for OmniRoute.
 *
 * Lightning Studios persist the home directory across stop/restart, so keep
 * OmniRoute's SQLite state there. Credentials themselves should be supplied as
 * Lightning Secrets (not committed to this repository).
 */
import { spawn } from "node:child_process";
import path from "node:path";

const persistentStudioDir = "/teamspace/studios/this_studio";
const dataDir = process.env.DATA_DIR?.trim() || path.join(persistentStudioDir, ".omniroute");

const env = {
  ...process.env,
  NODE_ENV: process.env.NODE_ENV || "production",
  DATA_DIR: dataDir,
  PORT: process.env.PORT || "20128",
  APP_BIND_HOST: process.env.APP_BIND_HOST || "0.0.0.0",
  OMNIROUTE_SERVER_HOST: process.env.OMNIROUTE_SERVER_HOST || "0.0.0.0",
  REQUIRE_API_KEY: process.env.REQUIRE_API_KEY || "true",
};

const requiredSecrets = [
  "JWT_SECRET",
  "API_KEY_SECRET",
  "STORAGE_ENCRYPTION_KEY",
  "OMNIROUTE_API_KEY",
];

const missing = requiredSecrets.filter((key) => !String(env[key] || "").trim());
if (missing.length > 0) {
  console.error(
    "[Lightning] Missing required secrets: " +
      missing.join(", ") +
      ". Add them as Lightning User/Teamspace Secrets before starting OmniRoute."
  );
  process.exit(1);
}

if (env.NEXT_PUBLIC_BASE_URL) {
  console.log(`[Lightning] Public base URL: ${env.NEXT_PUBLIC_BASE_URL}`);
}

console.log(`[Lightning] Persistent data directory: ${dataDir}`);
console.log(`[Lightning] Listening on 0.0.0.0:${env.PORT}`);
console.log("[Lightning] SQLite/provider credentials will survive Studio restarts.");

const child = spawn("npm", ["run", "start"], {
  cwd: process.cwd(),
  env,
  stdio: "inherit",
  shell: process.platform === "win32",
});

const forwardSignal = (signal) => {
  if (!child.killed) child.kill(signal);
};

process.on("SIGINT", () => forwardSignal("SIGINT"));
process.on("SIGTERM", () => forwardSignal("SIGTERM"));

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
