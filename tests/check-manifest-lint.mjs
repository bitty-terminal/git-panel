/**
 * Authoritative SDK manifest report check.
 *
 * Runs the pinned `bitty-plugin-lint` (bitty-plugin-sdk, R-SDK-2; commit pin
 * in package.json and bun.lock) against `bitty-plugin.toml` in `--json` mode
 * and asserts the machine-readable report says the manifest is valid.
 * `just manifest` runs the same linter in human mode; this check covers the
 * `--json` contract and fails closed when the pinned dependency is missing
 * (run `just install` first).
 *
 * `BITTY_PLUGIN_LINT` overrides the CLI entry for a local SDK checkout.
 *
 * Usage:
 *
 *   bun tests/check-manifest-lint.mjs
 */

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..");
const MANIFEST = join(REPO_ROOT, "bitty-plugin.toml");
const PINNED_LINTER = join(
  REPO_ROOT,
  "node_modules",
  "bitty-plugin-sdk",
  "src",
  "cli.ts",
);
const TIMEOUT_MS = 60_000;

const override = process.env.BITTY_PLUGIN_LINT;
const linter =
  override !== undefined && override !== "" ? override : PINNED_LINTER;
if (!existsSync(linter)) {
  console.error(
    `manifest-lint: ${linter} is not installed; run 'just install'`,
  );
  process.exit(1);
}

const result = spawnSync("bun", [linter, "--json", MANIFEST], {
  timeout: TIMEOUT_MS,
  encoding: "utf8",
  cwd: REPO_ROOT,
});
if (result.error !== undefined && result.error !== null) {
  console.error(`manifest-lint: linter could not run: ${result.error.message}`);
  process.exit(2);
}

let report;
try {
  report = JSON.parse(result.stdout ?? "");
} catch {
  console.error("manifest-lint: linter did not emit a JSON report");
  process.stderr.write(result.stderr ?? "");
  process.exit(2);
}

const diagnostics = Array.isArray(report.diagnostics) ? report.diagnostics : [];
const errors = diagnostics.filter((entry) => entry.severity === "error");
if (result.status !== 0 || report.valid !== true || errors.length > 0) {
  for (const entry of diagnostics) {
    console.error(
      `  ${entry.severity}: ${entry.code} (${entry.path}): ${entry.message}`,
    );
  }
  console.error(
    `manifest-lint: FAIL (exit ${result.status}, valid=${report.valid}, errors=${errors.length})`,
  );
  process.exit(1);
}
console.log(
  `ok - ${MANIFEST} valid (warnings=${diagnostics.length}) via ${linter}`,
);
