/**
 * Negative-fixture gate for the transitional manifest validator.
 *
 * `scripts/validate-manifest.mjs` must reject every known-bad manifest in
 * `validator-negative/`; `validator-negative/base.toml` is the accepted
 * positive control (it is byte-identical to `bitty-plugin.toml`) and must
 * validate. The gate fails loudly when the fixture directory, the positive
 * control, or any negative fixture is missing, so an empty or partial tree
 * can never pass silently.
 *
 * Usage:
 *
 *   bun tests/check-negative-fixtures.mjs
 */

import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..");
const VALIDATOR = join(REPO_ROOT, "scripts", "validate-manifest.mjs");
const FIXTURE_DIR = join(REPO_ROOT, "validator-negative");
const POSITIVE_FIXTURE = "base.toml";
const TIMEOUT_MS = 60_000;

function validate(fixturePath) {
  return spawnSync("bun", [VALIDATOR, fixturePath], {
    timeout: TIMEOUT_MS,
    encoding: "utf8",
    cwd: REPO_ROOT,
  });
}

function main() {
  const problems = [];

  if (!existsSync(VALIDATOR)) {
    problems.push(`validator missing: ${VALIDATOR}`);
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
  const negatives = fixtures.filter((name) => name !== POSITIVE_FIXTURE);
  if (negatives.length === 0) {
    console.error("negative-fixtures: no negative fixtures to check");
    return 1;
  }

  const positive = validate(join(FIXTURE_DIR, POSITIVE_FIXTURE));
  if (positive.error !== undefined && positive.error !== null) {
    console.error(
      `negative-fixtures: validator could not run: ${positive.error.message}`,
    );
    return 2;
  }
  if (positive.status !== 0) {
    problems.push(
      `${POSITIVE_FIXTURE} must be ACCEPTED but the validator exited ${positive.status}`,
    );
  } else {
    console.log(`ok - ${POSITIVE_FIXTURE} accepted (positive control)`);
  }

  for (const name of negatives) {
    const result = validate(join(FIXTURE_DIR, name));
    if (result.error !== undefined && result.error !== null) {
      problems.push(
        `${name}: validator could not run: ${result.error.message}`,
      );
      continue;
    }
    if (result.status === 0) {
      problems.push(`${name} must be REJECTED but the validator accepted it`);
    } else {
      console.log(`ok - ${name} rejected (exit ${result.status})`);
    }
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
