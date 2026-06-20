{ lib
, stdenv
, fetchFromGitHub
, nodejs_24
, pnpm_11
, pnpmConfigHook
, fetchPnpmDeps
, bash
, buildGoModule
}:

let
  version = "1.124.0"; # renovate: datasource=github-tags depName=bluesky-social/social-app
  src = fetchFromGitHub {
    owner = "bluesky-social";
    repo = "social-app";
    rev = version;
    hash = "sha256-SU1w9QzuewSu/EqgdzEN4BKd3ViPlr4/k2kTU2WSOEM=";
  };
  nodejs_pin = nodejs_24;
  # pinning per https://nixos.org/manual/nixpkgs/unstable/#javascript-pnpm
  pnpm = pnpm_11;
  static = stdenv.mkDerivation {
    pname = "bsky-app-static";
    inherit version src;

    nativeBuildInputs = [
      nodejs_pin
      pnpm
      pnpmConfigHook
    ];

    pnpmDeps = fetchPnpmDeps {
      pname = "bsky-app-static";
      inherit version src;
      inherit pnpm;
      fetcherVersion = 3;
      hash = "sha256-Q9o2pa5V8DIhXzA22k1xBUiDRSfpBpVnbqfYeefMRzo=";
    };

    # pnpm downloads a node binary that matches the version specified in the
    # package.json. I tried using that instead of system node, but I can't
    # autoPatchElf it inside fetchPnpmDeps (that's a fixed-output derivation so
    # can't depend on other store paths), but I also want it to have a real
    # store path by the time I patchShebangs in this derivation to point at it.
    # it turned out to be easier just to use system node, but let's at least
    # check the major version is correct
    preConfigure = ''
      expected=v$(cut -d. -f1 .nvmrc)
      actual=$(${nodejs_pin}/bin/node --version | cut -d. -f1)
      if [ "$expected" != "$actual" ]
      then
        echo "node --version ($actual) doesn't match .nvmrc ($expected) from ${src} (${src.rev})" >&2
        exit 1
      fi
    '';

    # see above: rm the downloaded binary because pnpm will put
    # node_modules/.bin on our PATH when running scripts, and it doesn't work
    # (having not been autoPatchElf'd)
    buildPhase = ''
      rm -f node_modules/.bin/node

      make build-web SHELL=${bash}/bin/bash
    '';

    installPhase = ''
      cp -r bskyweb $out/
    '';
  };
  server = buildGoModule {
    pname = "bskyweb";
    inherit version;
    src = static;
    vendorHash = "sha256-b2r8ZDKQzPzEiMOk2JE0EiU2taH371tb268df+HVIKw=";
  };
in
server
