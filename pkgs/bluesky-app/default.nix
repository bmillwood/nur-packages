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
  # main at time of writing, because no tag has support for node > 20 yet (and
  # node 20 is EOL)
  version = "bf83f165eef5c0ba36aca9f02d11e261bf29223d";
  src = fetchFromGitHub {
    owner = "bluesky-social";
    repo = "social-app";
    rev = version;
    hash = "sha256-zAbnISQYfjs3icbloRRY6JcsHgvFdengdBu/GblsSLc=";
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
      hash = "sha256-bCZDuV0QMrcJnVzvwGTh6x9Wx8OXKo8tUme3qTk7t5U=";
    };

    preConfigure = ''
      expected=v$(cut -d. -f1 .nvmrc)
      actual=$(${nodejs_pin}/bin/node --version | cut -d. -f1)
      if [ "$expected" != "$actual" ]
      then
        echo "node --version ($actual) doesn't match .nvmrc ($expected) from ${src} (${src.rev})" >&2
        exit 1
      fi
    '';

    buildPhase = ''
      # insist on our own node binary
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
    vendorHash = "sha256-5iwhahIfwbjQ5qJm3RKH+ywnXX/Q5uWmENIrq9Kdq80=";
  };
in
server
