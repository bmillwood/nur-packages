{ config, lib, pkgs, ... }:

let
  cfg = config.services.octo-sts;

  appConfigFile = (pkgs.formats.yaml { }).generate "octo-sts-apps.yaml" {
    orgs = lib.mapAttrsToList
      (org: apps: {
        name = org;
        apps = map
          (app: {
            app_name = app.name;
            app_id = app.appId;
            # octo-sts expands ${VAR} in the file's strings.
            private_key_file = "\${CREDENTIALS_DIRECTORY}/${app.name}.pem";
          })
          apps;
      })
      (lib.groupBy (app: app.org)
        (lib.mapAttrsToList (name: app: app // { inherit name; }) cfg.apps));
  };

  # The webhook only takes its secret from the environment (or a cloud secret
  # manager), and Environment= would put it in the store.
  webhookStart = pkgs.writeShellScript "octo-sts-webhook-start" ''
    export APP_SECRET_CERTIFICATE_FILE="$CREDENTIALS_DIRECTORY/app.pem"
    GITHUB_WEBHOOK_SECRET=$(< "$CREDENTIALS_DIRECTORY/webhook-secret")
    export GITHUB_WEBHOOK_SECRET
    exec ${lib.getExe' cfg.package "octo-sts-webhook"}
  '';

  serviceHardening = {
    Restart = "on-failure";
    DynamicUser = true;
    CapabilityBoundingSet = "";
    # AF_UNIX for name resolution via nss/systemd-resolved.
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    PrivateUsers = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" "~@privileged" ];
    UMask = "0077";
  };
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "services" "octo-sts" "appId" ]
      "Use services.octo-sts.apps.<name>.appId instead.")
    (lib.mkRemovedOptionModule [ "services" "octo-sts" "privateKeyFile" ]
      "Use services.octo-sts.apps.<name>.privateKeyFile instead.")
  ];

  options.services.octo-sts = {
    enable = lib.mkEnableOption ''
      octo-sts, which exchanges OIDC tokens (e.g. from GitHub Actions) for
      GitHub App installation tokens scoped by trust policies kept in the
      target repositories
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/octo-sts { };
      defaultText = lib.literalMD "octo-sts from this repository";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "sts.example.org";
      description = ''
        Public hostname of this instance. It is also the audience octo-sts
        expects in incoming tokens unless a trust policy says otherwise, and
        what callers pass as `domain` to `octo-sts/action`.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = ''
        Port for plain HTTP (and gRPC). octo-sts listens on every interface
        with no TLS, so leave this closed in the firewall and expose it
        through a reverse proxy, e.g. with
        {option}`services.octo-sts.configureNginx`.
      '';
    };

    apps = lib.mkOption {
      description = ''
        The GitHub Apps that mint tokens, by name. A trust policy picks one
        with `app: <name>`. Tokens act as that App's bot user, so separate
        Apps give separate identities to the automations using them.
      '';
      example = lib.literalExpression ''
        {
          renovate = { appId = 123; privateKeyFile = "/run/secrets/renovate.pem"; };
          claude = { appId = 456; privateKeyFile = "/run/secrets/claude.pem"; };
        }
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          appId = lib.mkOption {
            type = lib.types.ints.positive;
            description = "The App's numeric ID (not its client ID).";
          };

          privateKeyFile = lib.mkOption {
            type = lib.types.path;
            example = "/run/secrets/octo-sts.pem";
            description = ''
              The App's private key. It's passed to the service as a systemd
              credential, so it can stay readable by root only.
            '';
          };

          org = lib.mkOption {
            type = lib.types.str;
            default = "*";
            description = ''
              The GitHub owner whose repositories this App serves, or `*` for
              any owner that no other App names.
            '';
          };
        };
      });
    };

    allowedIssuers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://token.actions.githubusercontent.com" ];
      description = ''
        OIDC issuers octo-sts will contact to verify tokens. An empty list
        means any issuer a trust policy names, which lets whoever can write a
        policy point it at a provider they control, and lets any caller make
        this server fetch from a URL of their choosing.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { OCTOSTS_POLICY_DIR = ".github/octo-sts"; };
      description = ''
        Further environment variables; see the
        [octo-sts README](https://github.com/octo-sts/app#readme) for the
        rest. These override the ones this module sets. The webhook gets them
        too, since it must agree with the exchange service on settings like
        `ORG_POLICY_REPO` and `OCTOSTS_POLICY_DIR`.
      '';
    };

    configureNginx = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve {option}`services.octo-sts.domain` over HTTPS through nginx,
        with a certificate from ACME (which needs
        {option}`security.acme.acceptTerms` and
        {option}`security.acme.defaults.email`), and open ports 80 and 443.
        The webhook, if enabled, is served at `/webhook`.
      '';
    };

    webhook = {
      enable = lib.mkEnableOption ''
        the octo-sts webhook, which validates the trust policies a push or
        pull request changes, and reports the result as a check run named
        "Trust Policy Validation".

        It needs a GitHub App with read access to contents and pull requests
        and write access to checks, subscribed to the `pull_request`, `push`,
        `check_suite` and `check_run` events, and installed on the
        repositories holding policies
      '';

      port = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = ''
          Port for the webhook's plain HTTP, with the same caveats as
          {option}`services.octo-sts.port`.
        '';
      };

      appId = lib.mkOption {
        type = lib.types.ints.positive;
        description = ''
          The numeric ID of the App the webhook receives events for and posts
          check runs as. It can be one of {option}`services.octo-sts.apps`,
          but a separate App keeps `checks: write` and the webhook
          subscription away from the identities that mint tokens.
        '';
      };

      privateKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "The webhook App's private key, passed as a systemd credential.";
      };

      secretFile = lib.mkOption {
        type = lib.types.path;
        description = ''
          File holding the App's webhook secret, which GitHub signs
          deliveries with. Passed as a systemd credential.
        '';
      };

      organizations = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          GitHub owners whose events to validate. Empty means every owner the
          App is installed for.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.services.octo-sts = {
        description = "octo-sts, a security token service for GitHub";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        environment = {
          PORT = toString cfg.port;
          STS_DOMAIN = cfg.domain;
          APP_CONFIG_FILE = appConfigFile;
          # Otherwise a policy that doesn't name an App gets whichever one
          # octo-sts picks, i.e. an unpredictable identity.
          OCTOSTS_REQUIRE_APP_PIN = lib.boolToString (lib.length (lib.attrNames cfg.apps) > 1);
          OCTOSTS_ALLOWED_ISSUERS = lib.concatStringsSep "," cfg.allowedIssuers;
          # Upstream leaves this off so issuers on private networks work.
          # Without one, it only lets callers make this server probe the
          # local network.
          OCTOSTS_OIDC_BLOCK_PRIVATE_IPS = "true";
          # Metrics on means a Prometheus listener and an OpenTelemetry
          # tracer set up for Google Cloud.
          METRICS = "false";
        } // cfg.environment;
        serviceConfig = serviceHardening // {
          ExecStart = lib.getExe cfg.package;
          LoadCredential = lib.mapAttrsToList
            (name: app: "${name}.pem:${app.privateKeyFile}")
            cfg.apps;
        };
      };

      services.nginx = lib.mkIf cfg.configureNginx {
        enable = true;
        virtualHosts.${cfg.domain} = {
          enableACME = true;
          # Port 80 then answers ACME's HTTP-01 challenges and redirects
          # everything else, so tokens never cross plain HTTP.
          forceSSL = true;
          locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.configureNginx [ 80 443 ];
    }

    (lib.mkIf cfg.webhook.enable {
      systemd.services.octo-sts-webhook = {
        description = "octo-sts webhook, validating trust policies in GitHub check runs";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        environment = {
          PORT = toString cfg.webhook.port;
          GITHUB_APP_IDS = toString cfg.webhook.appId;
          GITHUB_WEBHOOK_ORGANIZATION_FILTER = lib.concatStringsSep "," cfg.webhook.organizations;
          METRICS = "false";
        } // cfg.environment;
        serviceConfig = serviceHardening // {
          ExecStart = webhookStart;
          LoadCredential = [
            "app.pem:${cfg.webhook.privateKeyFile}"
            "webhook-secret:${cfg.webhook.secretFile}"
          ];
        };
      };

      services.nginx.virtualHosts.${cfg.domain}.locations."= /webhook" = lib.mkIf cfg.configureNginx {
        proxyPass = "http://127.0.0.1:${toString cfg.webhook.port}/";
      };
    })
  ]);
}
