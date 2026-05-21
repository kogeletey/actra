export interface ActraTarget {
  os: "linux" | "darwin";
  arch: "amd64" | "arm64";
  linkMode: "dynamic" | "static";
}

export function currentPackageVersion(): string;
export function resolveTarget(): ActraTarget;
export function cacheRoot(): string;
export function assetName(version?: string, target?: ActraTarget): string;
export function releaseUrl(file: string, version?: string): string;
export function run(args?: string[]): Promise<void>;
