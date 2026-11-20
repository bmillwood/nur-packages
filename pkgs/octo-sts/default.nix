{ lib
, buildGoModule
, fetchFromGitHub
, callPackage
}:

buildGoModule rec {
  pname = "octo-sts";
  version = "0.14.4"; # renovate: datasource=github-tags depName=octo-sts/app

  src = fetchFromGitHub {
    owner = "octo-sts";
    repo = "app";
    tag = "v${version}";
    hash = "sha256-B3hd/mP8fxOSyltrh4ySn16rEkiUjJ2ZpTDxETMjrjY=";
  };

  vendorHash = "sha256-eHGQwnshnC8YGcGtpLMwyTBlM/t/YD82mE/Bmp2oB/g=";

  # Only the token exchange service. The webhook (policy validation as PR
  # check runs), probers and policy-cleanup job are optional parts of
  # Chainguard's own deployment.
  subPackages = [ "cmd/app" ];

  postInstall = ''
    mv $out/bin/app $out/bin/octo-sts
  '';

  passthru.tests.nixos = callPackage ../../tests/octo-sts.nix { };

  meta = {
    description = "Security token service exchanging OIDC tokens for scoped GitHub App installation tokens";
    homepage = "https://github.com/octo-sts/app";
    license = lib.licenses.asl20;
    mainProgram = "octo-sts";
  };
}
