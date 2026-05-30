#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";

const version = process.argv[2] ?? process.env.VERSION;

if (!version) {
  console.error("usage: scripts/sync-js-package-version.mjs <version>");
  process.exit(1);
}

const semverPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

if (!semverPattern.test(version)) {
  console.error(`invalid SemVer version: ${version}`);
  process.exit(1);
}

for (const file of ["package.json", "jsr.json"]) {
  const data = JSON.parse(readFileSync(file, "utf8"));
  data.version = version;
  writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}
