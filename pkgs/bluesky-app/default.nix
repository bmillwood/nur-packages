{ nixpkgs ? <nixpkgs>
, config ? {}
}:

let
  pkgs = import nixpkgs config;
  inherit (pkgs) lib;
  version = "1.112.0";
  src = pkgs.fetchFromGitHub {
    owner = "bluesky-social";
    repo = "social-app";
    rev = version;
    hash = "sha256-DW8UlQZzh7AVH5IvcHwt2KguyxGtuYbvPN/gqeY+OVQ=";
  };
  nodejs_pin = pkgs.nodejs_20;
  # stdenv with cc, which we use for better-sqlite
  static = pkgs.stdenv.mkDerivation {
    pname = "bsky-app-tweaked";
    inherit src version;
    yarnOfflineCache = pkgs.fetchYarnDeps {
      yarnLock = "${src}/yarn.lock";
      hash = "sha256-80TqOxX94kMyGVGu9cKMfZknGYuFj15An8XeydDvPRc=";
    };

    preConfigure = ''
      export npm_config_nodedir=${nodejs_pin}
      export PATH=/build/source/node_modules/.bin:$PATH

      expected=v$(cat .nvmrc)
      actual=$(${nodejs_pin}/bin/node --version | cut -d. -f1)
      if [ "$expected" != "$actual" ]
      then
        echo "node --version ($actual) doesn't match .nvmrc ($expected)" >&2
        exit 1
      fi
    '';

    buildPhase = ''
      yarn --offline postinstall
      yarn --offline build-web
    '';

    installPhase = ''
      cp -r bskyweb $out/
    '';

    nativeBuildInputs = [
      pkgs.yarnConfigHook

      nodejs_pin
      pkgs.python3
    ];
  };
  server = pkgs.buildGoModule {
    pname = "bskyweb";
    inherit version;
    src = static;
    vendorHash = "sha256-5iwhahIfwbjQ5qJm3RKH+ywnXX/Q5uWmENIrq9Kdq80=";
  };
in
server
