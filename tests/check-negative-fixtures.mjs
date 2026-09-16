/**
 * Negative-fixture gate for the authoritative SDK manifest linter.
 *
 * The pinned `bitty-plugin-lint` (bitty-plugin-sdk, package.json + bun.lock)
 * must reject every known-bad manifest in `validator-negative/`;
 * `validator-negative/base.toml` is the accepted positive control and must be
 * byte-identical to `bitty-plugin.toml`. The gate fails loudly when the
 * linter, the fixture directory, the positive control, a required negative
 * fixture, or its expected diagnostic is missing, so an empty or partial tree
 * can never pass silently.
 *
 * Every rejection must be a manifest verdict (exit 1) carrying at least one
 * `error:` diagnostic; a usage/IO failure (exit 2) is a gate failure, not a
 * rejection. A negative fixture listed in {@link REQUIRED_NEGATIVES} must emit
 * its expected diagnostic code, so a fixture cannot pass by being rejected for
 * the wrong reason.
 *
 * Usage:
 *
 *   bun tests/check-negative-fixtures.mjs
 *
 * `BITTY_PLUGIN_LINT` overrides the linter entry point (local SDK checkout).
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..");
const MANIFEST = join(REPO_ROOT, "bitty-plugin.toml");
const FIXTURE_DIR = join(REPO_ROOT, "validator-negative");
const POSITIVE_FIXTURE = "base.toml";
const PINNED_LINTER = join(
  REPO_ROOT,
  "node_modules",
  "bitty-plugin-sdk",
  "src",
  "cli.ts",
);
const TIMEOUT_MS = 60_000;
const EXIT_INVALID = 1;

/**
 * Required negative fixtures and the diagnostic code each must trigger.
 * Removing a fixture or changing its defect without updating this roster
 * fails the gate.
 */
const REQUIRED_NEGATIVES = new Map([
  ["bad-param.toml", "capabilities.invalid"],
  ["bare-spawn.toml", "capabilities.param-required"],
  ["fs-traversal.toml", "capabilities.filesystem.invalid"],
  ["param-forbidden.toml", "capabilities.param-forbidden"],
  ["tools-no-required.toml", "manifest.type"],
  ["tools-no-version.toml", "manifest.type"],
  ["tools-rg.toml", "tools.tool.unknown"],
]);

function resolveLinter() {
  const override = process.env.BITTY_PLUGIN_LINT;
  if (override !== undefined && override !== "") {
    return override;
  }
  return PINNED_LINTER;
}

function lint(linter, fixturePath) {
  return spawnSync("bun", [linter, fixturePath], {
    timeout: TIMEOUT_MS,
    encoding: "utf8",
    cwd: REPO_ROOT,
  });
}

/** Diagnostic codes carried on `error:` lines of a human-mode report. */
function errorCodes(stdout) {
  const codes = new Set();
  for (const line of stdout.split("\n")) {
    const match = /: error: ([a-z][\w.-]*)/.exec(line);
    if (match !== null) {
      codes.add(match[1]);
    }
  }
  return codes;
}

function main() {
  const problems = [];
  const linter = resolveLinter();

  if (!existsSync(linter)) {
    problems.push(`linter missing: ${linter} (run 'just install')`);
  }
  if (!existsSync(FIXTURE_DIR)) {
    problems.push(`fixture directory missing: ${FIXTURE_DIR}`);
  }
  if (problems.length > 0) {
    for (const problem of problems) {
      console.error(`negative-fixtures: ${problem}`);
    }
    return 1;
  }

  const fixtures = readdirSync(FIXTURE_DIR)
    .filter((name) => name.endsWith(".toml"))
    .sort();
  if (fixtures.length === 0) {
    console.error(`negative-fixtures: no *.toml fixtures in ${FIXTURE_DIR}`);
    return 1;
  }
  if (!fixtures.includes(POSITIVE_FIXTURE)) {
    console.error(
      `negative-fixtures: positive control ${POSITIVE_FIXTURE} is missing`,
    );
    return 1;
  }
  if (
    !readFileSync(join(FIXTURE_DIR, POSITIVE_FIXTURE)).equals(
      readFileSync(MANIFEST),
    )
  ) {
    console.error(
      `negative-fixtures: positive control ${POSITIVE_FIXTURE} is not byte-identical to bitty-plugin.toml`,
    );
    return 1;
  }
  for (const name of REQUIRED_NEGATIVES.keys()) {
    if (!fixtures.includes(name)) {
      problems.push(`required negative ${name} is missing`);
    }
  }
  const negatives = fixtures.filter((name) => name !== POSITIVE_FIXTURE);
  if (negatives.length === 0) {
    console.error("negative-fixtures: no negative fixtures to check");
    return 1;
  }

  const positive = lint(linter, join(FIXTURE_DIR, POSITIVE_FIXTURE));
  if (positive.error !== undefined && positive.error !== null) {
    console.error(
      `negative-fixtures: linter could not run: ${positive.error.message}`,
    );
    return 2;
  }
  if (positive.status !== 0) {
    problems.push(
      `${POSITIVE_FIXTURE} must be ACCEPTED but the linter exited ${positive.status}`,
    );
  } else {
    console.log(`ok - ${POSITIVE_FIXTURE} accepted (positive control)`);
  }

  for (const name of negatives) {
    const result = lint(linter, join(FIXTURE_DIR, name));
    if (result.error !== undefined && result.error !== null) {
      problems.push(`${name}: linter could not run: ${result.error.message}`);
      continue;
    }
    if (result.status !== EXIT_INVALID) {
      problems.push(
        `${name} must be REJECTED with exit ${EXIT_INVALID} but the linter exited ${result.status}`,
      );
      continue;
    }
    const codes = errorCodes(result.stdout ?? "");
    if (codes.size === 0) {
      problems.push(`${name} was rejected without an error diagnostic`);
      continue;
    }
    const expected = REQUIRED_NEGATIVES.get(name);
    if (expected !== undefined && !codes.has(expected)) {
      problems.push(
        `${name} must emit '${expected}' but emitted: ${[...codes].sort().join(", ")}`,
      );
      continue;
    }
    console.log(
      `ok - ${name} rejected (exit ${result.status}; ${[...codes].sort().join(", ")})`,
    );
  }

  if (problems.length > 0) {
    console.error("negative-fixture gate failed:");
    for (const problem of problems) {
      console.error(`  - ${problem}`);
    }
    return 1;
  }
  console.log(
    `negative-fixture gate passed (${negatives.length} rejected, 1 accepted)`,
  );
  return 0;
}

process.exit(main());
