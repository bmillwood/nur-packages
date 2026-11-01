{ lib
, stdenv
, fetchFromGitHub
, nodejs_24
, pnpm_11
, pnpmConfigHook
, fetchPnpmDeps
, buildGoModule
}:

let
  version = "1.137.0"; # renovate: datasource=github-tags depName=bluesky-social/social-app
  src = fetchFromGitHub {
    owner = "bluesky-social";
    repo = "social-app";
    tag = version;
    hash = "sha256-AHv+PxTDJjAPbjdVLPZqzgInJj459avQFJzt0lI8RbY=";
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
      fetcherVersion = 4;
      hash = "sha256-a58iav6ZzrmVA+g5yBf9mWSORcVOzhBBZg9anNgxz1Y=";
    };

    # to avoid JavaScript heap exhaustion issues, matching
    # https://github.com/bluesky-social/social-app/blob/485405a086bbe700bbfb84c9a8669608617d0105/.github/workflows/pull-request-commit.yml#L25
    env.NODE_OPTIONS = "--max-old-space-size=4096";

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

      # postinstall is skipped by pnpmConfigHook (--ignore-scripts)
      pnpm lexicons:generate

      pnpm intl:build
      pnpm build-web
    '';

    installPhase = ''
      cp -r bskyweb $out/
    '';
  };
  server = buildGoModule {
    pname = "bskyweb";
    inherit version;
    src = static;
    vendorHash = "sha256-z/B9RF+yyEfhMCPW65M9wv+UWfnt9zbDm4T1mFxoxuQ=";
  };
in
server
