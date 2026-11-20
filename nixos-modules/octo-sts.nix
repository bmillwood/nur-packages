{ config, lib, pkgs, ... }:

let
  cfg = config.services.octo-sts;
in
{
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

    appId = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Numeric ID of the GitHub App that mints the tokens.";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      example = "/run/secrets/octo-sts.pem";
      description = ''
        The GitHub App's private key. It's passed to the service as a systemd
        credential, so it can stay readable by root only.
      '';
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

    blockPrivateIPs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Refuse OIDC discovery and key fetches to private and shared
        (e.g. Tailscale) addresses. Only turn this off to trust an issuer
        that lives on one.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { OCTOSTS_POLICY_DIR = ".github/octo-sts"; };
      description = ''
        Further environment variables; see the octo-sts README for the rest.
        These override the ones this module sets.
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
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.octo-sts = {
      description = "octo-sts, a security token service for GitHub";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        PORT = toString cfg.port;
        STS_DOMAIN = cfg.domain;
        GITHUB_APP_IDS = toString cfg.appId;
        # %d is systemd's credentials directory, holding the LoadCredential
        # below.
        APP_SECRET_CERTIFICATE_FILE = "%d/app.pem";
        OCTOSTS_ALLOWED_ISSUERS = lib.concatStringsSep "," cfg.allowedIssuers;
        OCTOSTS_OIDC_BLOCK_PRIVATE_IPS = lib.boolToString cfg.blockPrivateIPs;
        # Metrics on means a Prometheus listener and an OpenTelemetry
        # tracer set up for Google Cloud.
        METRICS = "false";
      } // cfg.environment;
      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        LoadCredential = [ "app.pem:${cfg.privateKeyFile}" ];

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
    };

    services.nginx = lib.mkIf cfg.configureNginx {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts.${cfg.domain} = {
        enableACME = true;
        forceSSL = true;
        locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.configureNginx [ 80 443 ];
  };
}
