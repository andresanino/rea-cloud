// src/server.ts
import { spawn } from "child_process";

// src/command.ts
function getEmbedCommand(opts = {}) {
  if (opts.embedPackagePath) {
    return ["uv", "run", "--directory", opts.embedPackagePath, "hindsight-embed"];
  }
  const version = opts.embedVersion && opts.embedVersion.length > 0 ? opts.embedVersion : "latest";
  return ["uvx", `hindsight-embed@${version}`];
}

// src/logger.ts
var silentLogger = {
  debug: () => {
  },
  info: () => {
  },
  warn: () => {
  },
  error: () => {
  }
};
var consoleLogger = {
  debug: (msg) => console.debug(msg),
  info: (msg) => console.log(msg),
  warn: (msg) => console.warn(msg),
  error: (msg) => console.error(msg)
};

// src/server.ts
var DEFAULT_PORT = 8888;
var DEFAULT_HOST = "127.0.0.1";
var DEFAULT_PROFILE = "default";
var DEFAULT_READY_TIMEOUT_MS = 3e4;
var DEFAULT_READY_POLL_INTERVAL_MS = 1e3;
var HindsightServer = class {
  profile;
  port;
  host;
  baseUrl;
  embedVersion;
  embedPackagePath;
  userEnv;
  extraProfileCreateArgs;
  extraDaemonStartArgs;
  platformCpuWorkaround;
  readyTimeoutMs;
  readyPollIntervalMs;
  logger;
  constructor(opts = {}) {
    this.profile = opts.profile ?? DEFAULT_PROFILE;
    this.port = opts.port ?? DEFAULT_PORT;
    this.host = opts.host ?? DEFAULT_HOST;
    this.baseUrl = `http://${this.host}:${this.port}`;
    this.embedVersion = opts.embedVersion;
    this.embedPackagePath = opts.embedPackagePath;
    this.userEnv = opts.env ?? {};
    this.extraProfileCreateArgs = opts.extraProfileCreateArgs ?? [];
    this.extraDaemonStartArgs = opts.extraDaemonStartArgs ?? [];
    this.platformCpuWorkaround = opts.platformCpuWorkaround ?? process.platform === "darwin";
    this.readyTimeoutMs = opts.readyTimeoutMs ?? DEFAULT_READY_TIMEOUT_MS;
    this.readyPollIntervalMs = opts.readyPollIntervalMs ?? DEFAULT_READY_POLL_INTERVAL_MS;
    this.logger = opts.logger ?? silentLogger;
  }
  /** The base URL the daemon listens on (`http://host:port`). */
  getBaseUrl() {
    return this.baseUrl;
  }
  /** The profile name this server operates on. */
  getProfile() {
    return this.profile;
  }
  /**
   * Ensure the daemon is configured and running. Idempotent — the underlying
   * `profile create --merge` and `daemon start` commands tolerate re-runs.
   */
  async start() {
    this.logger.info(`[hindsight] starting daemon for profile "${this.profile}"`);
    const env = this.buildEnv();
    await this.configureProfile(env);
    await this.startDaemon(env);
    await this.waitForReady();
    this.logger.info(`[hindsight] daemon ready at ${this.baseUrl}`);
  }
  /** Stop the daemon. Never throws — logs and resolves even on failure. */
  async stop() {
    this.logger.info(`[hindsight] stopping daemon for profile "${this.profile}"`);
    const [cmd, ...baseArgs] = getEmbedCommand({
      embedVersion: this.embedVersion,
      embedPackagePath: this.embedPackagePath
    });
    const args = [...baseArgs, "daemon", "--profile", this.profile, "stop"];
    const child = spawn(cmd, args, { stdio: "pipe", env: this.buildEnv(), windowsHide: true });
    this.pipeOutput(child, "daemon.stop");
    await new Promise((resolve) => {
      const timeout = setTimeout(() => {
        this.logger.warn(`[hindsight] daemon stop timed out after 5s`);
        resolve();
      }, 5e3);
      child.on("exit", () => {
        clearTimeout(timeout);
        this.logger.info(`[hindsight] daemon stopped`);
        resolve();
      });
      child.on("error", (err) => {
        clearTimeout(timeout);
        this.logger.warn(`[hindsight] error stopping daemon: ${err.message}`);
        resolve();
      });
    });
  }
  /** Probe `/health` once with a short timeout. */
  async checkHealth() {
    try {
      const res = await fetch(`${this.baseUrl}/health`, {
        signal: AbortSignal.timeout(2e3)
      });
      return res.ok;
    } catch {
      return false;
    }
  }
  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------
  /**
   * Merge the process env, the caller-supplied `env`, and (on macOS) the
   * embeddings CPU workaround. Caller-supplied values always win over the
   * workaround; undefined values are dropped.
   */
  buildEnv() {
    const merged = { ...process.env };
    if (this.platformCpuWorkaround && process.platform === "darwin") {
      merged["HINDSIGHT_API_EMBEDDINGS_LOCAL_FORCE_CPU"] = "1";
      merged["HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU"] = "1";
    }
    for (const [key, value] of Object.entries(this.userEnv)) {
      if (value !== void 0) {
        merged[key] = value;
      }
    }
    return merged;
  }
  /**
   * Run `profile create <name> --merge --port <port> [--env K=V ...]`.
   * Every entry in the merged env that was passed via {@link userEnv} (or
   * auto-applied by the CPU workaround) is forwarded as `--env`.
   */
  async configureProfile(env) {
    this.logger.info(`[hindsight] configuring profile "${this.profile}"`);
    const [cmd, ...baseArgs] = getEmbedCommand({
      embedVersion: this.embedVersion,
      embedPackagePath: this.embedPackagePath
    });
    const createArgs = [
      ...baseArgs,
      "profile",
      "create",
      this.profile,
      "--merge",
      "--port",
      String(this.port)
    ];
    const envForProfile = this.collectProfileEnv(env);
    for (const [key, value] of Object.entries(envForProfile)) {
      createArgs.push("--env", `${key}=${value}`);
    }
    createArgs.push(...this.extraProfileCreateArgs);
    await this.runCommand(cmd, createArgs, env, "profile.create");
  }
  /** Collect only the env vars that should be written into the profile file. */
  collectProfileEnv(env) {
    const out = {};
    for (const [key, value] of Object.entries(this.userEnv)) {
      if (value !== void 0) {
        out[key] = value;
      }
    }
    if (this.platformCpuWorkaround && process.platform === "darwin") {
      const cpuKeys = [
        "HINDSIGHT_API_EMBEDDINGS_LOCAL_FORCE_CPU",
        "HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU"
      ];
      for (const key of cpuKeys) {
        if (!(key in out) && env[key] !== void 0) {
          out[key] = env[key];
        }
      }
    }
    return out;
  }
  async startDaemon(env) {
    const [cmd, ...baseArgs] = getEmbedCommand({
      embedVersion: this.embedVersion,
      embedPackagePath: this.embedPackagePath
    });
    const args = [
      ...baseArgs,
      "daemon",
      "--profile",
      this.profile,
      "start",
      ...this.extraDaemonStartArgs
    ];
    await this.runCommand(cmd, args, env, "daemon.start");
  }
  /**
   * Spawn `cmd` with `args`, pipe its output through the logger, and resolve
   * once it exits with code 0. Rejects on non-zero exit or spawn error.
   */
  async runCommand(cmd, args, env, label) {
    const child = spawn(cmd, args, { stdio: "pipe", env, windowsHide: true });
    let output = "";
    child.stdout?.on("data", (data) => {
      const text = data.toString();
      output += text;
      for (const line of text.trimEnd().split("\n")) {
        if (line) this.logger.info(`[hindsight:${label}] ${line}`);
      }
    });
    child.stderr?.on("data", (data) => {
      const text = data.toString();
      output += text;
      for (const line of text.trimEnd().split("\n")) {
        if (line) this.logger.warn(`[hindsight:${label}] ${line}`);
      }
    });
    await new Promise((resolve, reject) => {
      child.on("exit", (code) => {
        if (code === 0) {
          resolve();
        } else {
          reject(new Error(`${label} failed with code ${code}: ${output.trim()}`));
        }
      });
      child.on("error", (err) => {
        reject(new Error(`${label} failed to spawn: ${err.message}`, { cause: err }));
      });
    });
  }
  /** Stream a spawned child's stdout/stderr through the logger without blocking. */
  pipeOutput(child, label) {
    child.stdout?.on("data", (data) => {
      for (const line of data.toString().trimEnd().split("\n")) {
        if (line) this.logger.info(`[hindsight:${label}] ${line}`);
      }
    });
    child.stderr?.on("data", (data) => {
      for (const line of data.toString().trimEnd().split("\n")) {
        if (line) this.logger.warn(`[hindsight:${label}] ${line}`);
      }
    });
  }
  /** Poll `/health` until it succeeds or `readyTimeoutMs` elapses. */
  async waitForReady() {
    const deadline = Date.now() + this.readyTimeoutMs;
    let attempt = 0;
    while (Date.now() < deadline) {
      attempt++;
      try {
        const res = await fetch(`${this.baseUrl}/health`, {
          signal: AbortSignal.timeout(this.readyPollIntervalMs)
        });
        if (res.ok) {
          this.logger.debug(`[hindsight] health check passed (attempt ${attempt})`);
          return;
        }
      } catch {
      }
      await new Promise((resolve) => setTimeout(resolve, this.readyPollIntervalMs));
    }
    throw new Error(
      `Hindsight daemon did not become ready within ${this.readyTimeoutMs}ms at ${this.baseUrl}`
    );
  }
};
export {
  HindsightServer,
  consoleLogger,
  getEmbedCommand,
  silentLogger
};
//# sourceMappingURL=index.js.map