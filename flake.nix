{
  description = "actra - Shell-native OpenAPI, ForgeFed, and AI agent CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        shardLines = pkgs.lib.splitString "\n" (builtins.readFile ./shard.yml);
        parsedVersions = map (line: let
          match = builtins.match "^[[:space:]]*version:[[:space:]]*([^[:space:]]+).*" line;
        in
          if match == null then null else builtins.head match
        ) shardLines;
        version = pkgs.lib.findFirst (value: value != null) "0.0.0" parsedVersions;

        actra = pkgs.stdenv.mkDerivation {
          pname = "actra";
          inherit version;
          src = ./.;

          nativeBuildInputs = with pkgs; [
            crystal
            shards
            pkg-config
          ];

          buildInputs = with pkgs; [
            openssl
            sqlite
          ];

          doCheck = false;

          buildPhase = ''
            export HOME=$TMPDIR
            shards install
            crystal build src/actra.cr --release -o actra
          '';

          installPhase = ''
            mkdir -p "$out/bin"
            cp actra "$out/bin/actra"
          '';

          meta = with pkgs.lib; {
            description = "Shell-native OpenAPI, ForgeFed, and AI agent CLI";
            homepage = "https://github.com/kogeletey/actra";
            license = licenses.bsd0;
            mainProgram = "actra";
          };
        };
      in
      {
        packages = {
          default = actra;
          actra = actra;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = actra;
          name = "actra";
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            crystal
            shards
            pkg-config
            openssl
            sqlite
          ];
        };
      }
    );
}
