/**
 * Pluggable logger interface.
 *
 * This package does not own any logging infrastructure — consumers inject
 * whatever they want (console, pino, openclaw's logger, a no-op). The default
 * is silent so embedding this package never adds noise to an unrelated app.
 */
interface Logger {
    debug(msg: string): void;
    info(msg: string): void;
    warn(msg: string): void;
    error(msg: string): void;
}
/** Logger that drops every call. Used when no logger is passed. */
declare const silentLogger: Logger;
/** Logger that writes to the standard console. Handy for CLIs and tests. */
declare const consoleLogger: Logger;

/**
 * Options for {@link HindsightServer}.
 *
 * The server is intentionally thin and pass-through: anything configurable
 * on the daemon side (env vars or CLI flags) can be set here without needing
 * a new dedicated option. Use {@link env} for `HINDSIGHT_*` / `OPENAI_API_KEY` /
 * custom provider settings, and the two `extra*` arrays to append raw CLI
 * args to `profile create` or `daemon start`.
 *
 * For talking to the daemon after `start()`, use `@vectorize-io/hindsight-client`
 * against `server.getBaseUrl()`. This package does not ship its own HTTP
 * client.
 */
interface HindsightServerOptions {
    /** Profile name used for `--profile <name>` on every sub-command. Default: `"default"`. */
    profile?: string;
    /** TCP port the daemon listens on. Default: `8888`. */
    port?: number;
    /** Hostname the daemon binds to (for health checks). Default: `127.0.0.1`. */
    host?: string;
    /** Version of the underlying `hindsight-embed` PyPI package to run via `uvx`. Default: `"latest"`. */
    embedVersion?: string;
    /** Local path to a `hindsight-embed` checkout — takes precedence over `embedVersion`. */
    embedPackagePath?: string;
    /**
     * Environment variables passed to the daemon process AND written into the
     * profile via repeated `--env KEY=VALUE` flags. This is the preferred way
     * to surface any `HINDSIGHT_API_*` / `HINDSIGHT_EMBED_*` setting — adding a
     * new daemon env var never requires a wrapper update.
     *
     * Values of `undefined` are dropped (so you can spread conditionally).
     */
    env?: Record<string, string | undefined>;
    /** Extra args appended verbatim to `hindsight-embed profile create <name> --merge ...`. */
    extraProfileCreateArgs?: string[];
    /** Extra args appended verbatim to `hindsight-embed daemon --profile <name> start ...`. */
    extraDaemonStartArgs?: string[];
    /**
     * On macOS, automatically set
     * `HINDSIGHT_API_EMBEDDINGS_LOCAL_FORCE_CPU=1` and
     * `HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU=1` to avoid Metal/MPS crashes in
     * daemon mode. Default: `true` on `darwin`, ignored elsewhere. Any value set
     * explicitly in {@link env} wins over the auto-applied value.
     */
    platformCpuWorkaround?: boolean;
    /** Max time (ms) to wait for `/health` to return 200. Default: `30_000`. */
    readyTimeoutMs?: number;
    /** Polling interval (ms) while waiting for `/health`. Default: `1_000`. */
    readyPollIntervalMs?: number;
    /** Optional pluggable logger. Default: silent. */
    logger?: Logger;
}

/**
 * Manages the lifecycle of a local Hindsight daemon from a Node.js process.
 *
 * On {@link start}, this class:
 *   1. Resolves the `hindsight-embed` command (via `uvx` or a local `uv run`).
 *   2. Runs `profile create <name> --merge --port <port> [--env K=V ...]`
 *      with every entry in {@link HindsightServerOptions.env} forwarded as
 *      an `--env` flag.
 *   3. Runs `daemon --profile <name> start` and waits for the start command
 *      to exit.
 *   4. Polls `http://host:port/health` until it returns `200` or the
 *      `readyTimeoutMs` budget is exhausted.
 *
 * On {@link stop}, it runs `daemon --profile <name> stop` and returns once
 * the command exits (or after a short grace period).
 *
 * This is the Node.js equivalent of the Python `hindsight-all` package's
 * `HindsightServer`: a thin programmatic lifecycle wrapper around the
 * Hindsight daemon. It does NOT ship an HTTP client — once `start()`
 * resolves, use `@vectorize-io/hindsight-client` against `getBaseUrl()` for
 * retain / recall / reflect.
 *
 * The class is deliberately transparent about the daemon: new CLI flags or
 * environment variables never require a code change here — callers can pass
 * them via `env`, `extraProfileCreateArgs`, or `extraDaemonStartArgs`.
 */
declare class HindsightServer {
    private readonly profile;
    private readonly port;
    private readonly host;
    private readonly baseUrl;
    private readonly embedVersion;
    private readonly embedPackagePath;
    private readonly userEnv;
    private readonly extraProfileCreateArgs;
    private readonly extraDaemonStartArgs;
    private readonly platformCpuWorkaround;
    private readonly readyTimeoutMs;
    private readonly readyPollIntervalMs;
    private readonly logger;
    constructor(opts?: HindsightServerOptions);
    /** The base URL the daemon listens on (`http://host:port`). */
    getBaseUrl(): string;
    /** The profile name this server operates on. */
    getProfile(): string;
    /**
     * Ensure the daemon is configured and running. Idempotent — the underlying
     * `profile create --merge` and `daemon start` commands tolerate re-runs.
     */
    start(): Promise<void>;
    /** Stop the daemon. Never throws — logs and resolves even on failure. */
    stop(): Promise<void>;
    /** Probe `/health` once with a short timeout. */
    checkHealth(): Promise<boolean>;
    /**
     * Merge the process env, the caller-supplied `env`, and (on macOS) the
     * embeddings CPU workaround. Caller-supplied values always win over the
     * workaround; undefined values are dropped.
     */
    private buildEnv;
    /**
     * Run `profile create <name> --merge --port <port> [--env K=V ...]`.
     * Every entry in the merged env that was passed via {@link userEnv} (or
     * auto-applied by the CPU workaround) is forwarded as `--env`.
     */
    private configureProfile;
    /** Collect only the env vars that should be written into the profile file. */
    private collectProfileEnv;
    private startDaemon;
    /**
     * Spawn `cmd` with `args`, pipe its output through the logger, and resolve
     * once it exits with code 0. Rejects on non-zero exit or spawn error.
     */
    private runCommand;
    /** Stream a spawned child's stdout/stderr through the logger without blocking. */
    private pipeOutput;
    /** Poll `/health` until it succeeds or `readyTimeoutMs` elapses. */
    private waitForReady;
}

/**
 * Resolve the command that invokes the `hindsight-embed` Python CLI.
 *
 * - If `embedPackagePath` is set, runs the package from a local checkout via
 *   `uv run --directory <path> hindsight-embed`. Used for in-repo development.
 * - Otherwise runs it via `uvx hindsight-embed@<version>` so no global install
 *   is required.
 *
 * Returns the argv as `[command, ...baseArgs]` suitable for `spawn()` /
 * `execFile()` (never shell-interpolated).
 */
interface EmbedCommandOptions {
    /** Version spec passed to uvx (e.g. "latest", "0.5.0"). Default: "latest". */
    embedVersion?: string;
    /** Local checkout path. When set, overrides `embedVersion` and uses `uv run`. */
    embedPackagePath?: string;
}
declare function getEmbedCommand(opts?: EmbedCommandOptions): string[];

export { type EmbedCommandOptions, HindsightServer, type HindsightServerOptions, type Logger, consoleLogger, getEmbedCommand, silentLogger };
