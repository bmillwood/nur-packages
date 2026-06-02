{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "stardew-valley";
  version = "1.6.15.24357.8705766150";

  src = pkgs.requireFile {
    name = "stardew_valley_1_6_15_24357_8705766150_78675.sh";
    sha256 = "1vvhaldjrg2s04hd6d1ys4nd6z7k97bw7afn2wb9ya0rs6b79bls";
    url = "https://www.gog.com/en/game/stardew_valley";
  };

  nativeBuildInputs = [
    pkgs.autoPatchelfHook
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
    echo "the installer script has an embedded zipfile which unzip can extract" >&2
    echo "you should see a warning about extra bytes next, that's fine" >&2
    # accept exit code 1 but not any other nonzero code
    unzip -q $src || [ "$?" == "1" ]
  '';

  installPhase = ''
    cp -r data/noarch $out/
  '';

  ldLibraryPath = "/run/opengl-driver/lib:${pkgs.lib.makeLibraryPath [
    pkgs.icu
    pkgs.libGL
    pkgs.libxrandr
    pkgs.libpulseaudio
  ]}";

  postFixup = ''
    wrapProgram $out/game/"Stardew Valley" \
      --prefix LD_LIBRARY_PATH : "$ldLibraryPath"
  '';

  meta = {
    homepage = "https://www.stardewvalley.net/";
    license = pkgs.lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "Stardew Valley";
  };
}
