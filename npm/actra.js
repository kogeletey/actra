#!/usr/bin/env node
import { createHash } from "node:crypto";
import { copyFileSync, createWriteStream, existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { chmod, mkdtemp } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import https from "node:https";

const REPOSITORY = "kogeletey/actra";
const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export function currentPackageVersion() {
  const packageJsonPath = path.join(PACKAGE_ROOT, "package.json");
  const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8"));
  return packageJson.version;
}

export function resolveTarget() {
  const os = process.platform;
  const cpu = process.arch;

  if (os === "linux" && cpu === "x64") {
    return { os: "linux", arch: "amd64", linkMode: "static" };
  }
  if (os === "linux" && cpu === "arm64") {
    return { os: "linux", arch: "arm64", linkMode: "static" };
  }
  if (os === "darwin" && cpu === "arm64") {
    return { os: "darwin", arch: "arm64", linkMode: "dynamic" };
  }

  throw new Error(`unsupported platform for Actra npm package: ${os}/${cpu}`);
}

export function cacheRoot() {
  if (process.env.ACTRA_INSTALL_DIR) {
    return process.env.ACTRA_INSTALL_DIR;
  }
  if (process.env.XDG_CACHE_HOME) {
    return path.join(process.env.XDG_CACHE_HOME, "actra", "npm");
  }
  return path.join(homedir(), ".cache", "actra", "npm");
}

export function assetName(version = currentPackageVersion(), target = resolveTarget()) {
  return `actra-${version}-${target.os}-${target.arch}-${target.linkMode}.tar.gz`;
}

export function releaseUrl(file, version = currentPackageVersion()) {
  return `https://github.com/${REPOSITORY}/releases/download/v${version}/${file}`;
}

async function download(url, destination) {
  await new Promise((resolve, reject) => {
    https.get(url, (response) => {
      if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        download(response.headers.location, destination).then(resolve, reject);
        return;
      }
      if (response.statusCode !== 200) {
        reject(new Error(`download failed: ${url} returned HTTP ${response.statusCode}`));
        response.resume();
        return;
      }
      const file = createWriteStream(destination);
      pipeline(response, file).then(resolve, reject);
    }).on("error", reject);
  });
}

function expectedSha256(sumsText, file) {
  for (const line of sumsText.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    const [hash, name] = trimmed.split(/\s+/, 2);
    if (name === file || name === `dist/${file}`) {
      return hash;
    }
  }
  throw new Error(`missing ${file} entry in SHA256SUMS`);
}

function sha256(file) {
  const hash = createHash("sha256");
  hash.update(readFileSync(file));
  return hash.digest("hex");
}

function extractTarball(archive, destination) {
  const result = spawnSync("tar", ["-xzf", archive, "-C", destination], {
    stdio: "inherit"
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`tar exited with status ${result.status}`);
  }
}

async function installBinary() {
  const version = currentPackageVersion();
  const target = resolveTarget();
  const archiveName = assetName(version, target);
  const installDir = path.join(cacheRoot(), version, `${target.os}-${target.arch}-${target.linkMode}`);
  const binaryPath = path.join(installDir, "actra");

  if (existsSync(binaryPath)) {
    return binaryPath;
  }

  mkdirSync(installDir, { recursive: true });
  const workDir = await mkdtemp(path.join(tmpdir(), "actra-npm-"));
  const archivePath = path.join(workDir, archiveName);
  const sumsPath = path.join(workDir, "SHA256SUMS");

  try {
    await download(releaseUrl(archiveName, version), archivePath);
    await download(releaseUrl("SHA256SUMS", version), sumsPath);

    const wanted = expectedSha256(readFileSync(sumsPath, "utf8"), archiveName);
    const actual = sha256(archivePath);
    if (actual !== wanted) {
      throw new Error(`checksum mismatch for ${archiveName}: expected ${wanted}, got ${actual}`);
    }

    extractTarball(archivePath, workDir);
    const extractedBinary = path.join(workDir, archiveName.replace(/\.tar\.gz$/, ""), "actra");
    await chmod(extractedBinary, 0o755);
    copyFileSync(extractedBinary, binaryPath);
    await chmod(binaryPath, 0o755);
    return binaryPath;
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
}

export async function run(args = process.argv.slice(2)) {
  const binaryPath = await installBinary();
  const child = spawn(binaryPath, args, { stdio: "inherit" });
  child.on("exit", (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 1);
  });
  child.on("error", (error) => {
    console.error(error.message);
    process.exit(1);
  });
}

function isDirectRun() {
  return process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isDirectRun()) {
  run().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
