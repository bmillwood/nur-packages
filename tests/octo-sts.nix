# Checks the module's service starts under its systemd sandboxing and can read
# its keys through LoadCredential and the generated config file, which
# evaluation alone can't tell you.
# Exchanging a real token would need GitHub, so the last check only reaches as
# far as token validation. Likewise, the webhook is only sent a ping, which
# shows it got the secret from its credential.
{ testers, runCommand, openssl, writeText }:

let
  # Throwaway keys, world-readable in the store, which is fine for a test.
  privateKey = name: runCommand "octo-sts-test-${name}.pem" { nativeBuildInputs = [ openssl ]; } ''
    openssl genrsa -out $out 2048
  '';
  # With the trailing newline an editor would leave, which GitHub's copy of
  # the secret doesn't have.
  webhookSecret = "hunter2";
  webhookSecretFile = writeText "octo-sts-test-webhook-secret" "${webhookSecret}\n";
in
testers.runNixOSTest {
  name = "octo-sts";

  nodes.machine = {
    imports = [ ../nixos-modules/octo-sts.nix ];
    services.octo-sts = {
      enable = true;
      domain = "sts.example.invalid";
      apps = {
        alpha = { appId = 1; privateKeyFile = privateKey "alpha"; };
        beta = { appId = 2; privateKeyFile = privateKey "beta"; org = "example"; };
      };
      webhook = {
        enable = true;
        appId = 3;
        privateKeyFile = privateKey "webhook";
        secretFile = webhookSecretFile;
      };
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

    import hmac, hashlib, shlex

    machine.wait_for_unit("octo-sts-webhook.service")
    machine.wait_for_open_port(8081)
    machine.succeed("curl -sf http://localhost:8081/healthcheck")

    def ping_status(secret):
        body = '{"zen": "Keep it logically awesome.", "hook_id": 1}'
        signature = hmac.new(secret.encode(), body.encode(), hashlib.sha256).hexdigest()
        return machine.succeed(
            "curl -s -o /dev/null -w '%{http_code}' "
            "-H 'Content-Type: application/json' -H 'X-GitHub-Event: ping' "
            f"-H 'X-Hub-Signature-256: sha256={signature}' "
            f"--data {shlex.quote(body)} http://localhost:8081/"
        )

    # Accepted and ignored, as the webhook does with any event it doesn't handle.
    assert ping_status("${webhookSecret}") == "202"
    assert ping_status("wrong") == "400"
  '';
}
