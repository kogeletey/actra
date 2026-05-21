export interface ActraTarget {
  os: "linux" | "darwin";
  arch: "amd64" | "arm64";
  linkMode: "dynamic" | "static";
}

export {
  assetName,
  cacheRoot,
  currentPackageVersion,
  releaseUrl,
  resolveTarget,
  run
} from "./actra.js";
