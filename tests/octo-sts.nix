# Checks the module's service starts under its systemd sandboxing and can read
# its key through LoadCredential, which evaluation alone can't tell you.
# Exchanging a real token would need GitHub, so the last check only reaches as
# far as token validation.
{ testers, runCommand, openssl }:

let
  # A throwaway key, world-readable in the store, which is fine for a test.
  privateKey = runCommand "octo-sts-test-key.pem" { nativeBuildInputs = [ openssl ]; } ''
    openssl genrsa -out $out 2048
  '';
in
testers.runNixOSTest {
  name = "octo-sts";

  nodes.machine = {
    imports = [ ../nixos-modules/octo-sts.nix ];
    services.octo-sts = {
      enable = true;
      domain = "sts.example.invalid";
      appId = 1;
      privateKeyFile = privateKey;
    };
  };

  testScript = ''
    machine.wait_for_unit("octo-sts.service")
    machine.wait_for_open_port(8080)
    machine.succeed("curl -sf http://localhost:8080/")
    machine.succeed(
      "curl -s -H 'Authorization: Bearer x.y.z' "
      "'http://localhost:8080/sts/exchange?scope=a/b&identity=c' "
      "| grep -q 'invalid bearer token'"
    )
  '';
}
