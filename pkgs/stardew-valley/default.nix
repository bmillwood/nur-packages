{ pkgs ? import <nixpkgs> {} }:

let
  installerName = "stardew_valley_1_6_15_24357_8705766150_78675.sh";
  pkgLibraryPath = pkgs.lib.makeLibraryPath [
      pkgs.icu
      pkgs.libGL
      pkgs.libGLX
      pkgs.libglvnd
      pkgs.libudev0-shim
      pkgs.libxcursor
      pkgs.libxi
      pkgs.libxrandr
      pkgs.libpulseaudio
    ];
  libraryPath = "/run/opengl-driver/lib:/run/opengl-driver-32/lib:${pkgLibraryPath}";
in
pkgs.stdenv.mkDerivation {
  pname = "stardew-valley";
  version = "1.6.15.24357.8705766150";

  # Downloaded from gog.com.
  src = pkgs.requireFile {
    name = installerName;
    sha256 = "1vvhaldjrg2s04hd6d1ys4nd6z7k97bw7afn2wb9ya0rs6b79bls";
    message = "${installerName} is not in the nix store";
  };

  nativeBuildInputs = [
    pkgs.autoPatchelfHook
    pkgs.bash
    pkgs.coreutils
    pkgs.makeWrapper
    pkgs.unzip
  ];

  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.gtk2
    pkgs.cairo
    pkgs.pango
    pkgs.lttng-ust_2_12
  ];

  unpackPhase = ''
    zipOffset=$(grep --max-count=1 --byte-offset --only-matching --text ''$'PK\x03\x04' $src | cut -d: -f1)
    dd bs="$zipOffset" skip=1 if=$src of=data.zip
    unzip data.zip
  '';

  installPhase = ''
    cp -r data/noarch $out/
  '';

  postFixup = ''
    wrapProgram $out/game/"Stardew Valley" \
      --prefix LD_LIBRARY_PATH : "${libraryPath}"
  '';
}
