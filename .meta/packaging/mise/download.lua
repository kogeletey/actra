#!/usr/bin/env lua

local function fail(msg)
  io.stderr:write(msg .. "\n")
  os.exit(1)
end

local function getenv(name, default)
  local v = os.getenv(name)
  if v == nil or v == "" then
    return default
  end
  return v
end

local function run(cmd)
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then
    fail("command failed: " .. cmd)
  end
end

local version = arg[1]
local os_name = arg[2] or "linux"
local arch = arg[3] or "amd64"
local link_mode = arg[4] or "dynamic"
local install_dir = arg[5] or "./bin"

if not version then
  fail("usage: download.lua <version> [os] [arch] [dynamic|static] [install_dir]")
end

if version:sub(1, 1) ~= "v" then
  version = "v" .. version
end

local repo = getenv("GITHUB_REPOSITORY", "kogeletey/actra")
local base = "https://github.com/" .. repo .. "/releases/download/" .. version
local name = "actra-" .. version:sub(2) .. "-" .. os_name .. "-" .. arch .. "-" .. link_mode
local archive = name .. ".tar.gz"
local checksum = "SHA256SUMS"

run(string.format("mkdir -p %q", install_dir))
run(string.format("curl -fsSLO %q", base .. "/" .. archive))
run(string.format("curl -fsSLO %q", base .. "/" .. checksum))

if os.execute("command -v sha256sum >/dev/null 2>&1") == true or os.execute("command -v sha256sum >/dev/null 2>&1") == 0 then
  run(string.format("grep ' %s$' %s | sha256sum -c -", archive, checksum))
else
  run(string.format("grep ' %s$' %s | shasum -a 256 -c -", archive, checksum))
end

run(string.format("tar -xzf %s", archive))
run(string.format("cp %s/actra %s/actra", name, install_dir))
run(string.format("chmod +x %s/actra", install_dir))

print("installed " .. install_dir .. "/actra")
