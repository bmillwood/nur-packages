{ config, lib, pkgs, ... }:

let
  cfg = config.services.claude-code-log;
in
{
  options.services.claude-code-log = {
    enable = lib.mkEnableOption "claude-code-log, which re-renders Claude Code transcripts as HTML as they change";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/claude-code-log { };
      defaultText = lib.literalMD "claude-code-log from this repository";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "User whose transcripts are rendered. The service runs as this user.";
    };

    projectsDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.users.users.${cfg.user}.home}/.claude/projects";
      defaultText = lib.literalExpression ''"''${config.users.users.''${cfg.user}.home}/.claude/projects"'';
      description = "Claude Code's projects directory, read but never written.";
    };

    outputDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/claude-code-log";
      description = ''
        Where the HTML goes. It's created owned by {option}`services.claude-code-log.user`
        and readable by everyone, so another service can serve it.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--combined" "yes" ];
      description = "Extra arguments to `claude-code-log watch`.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.settings.claude-code-log.${cfg.outputDir}.d = {
      inherit (cfg) user;
      mode = "0755";
    };

    systemd.services.claude-code-log = {
      description = "Render Claude Code transcripts as HTML";
      wantedBy = [ "multi-user.target" ];
      # By default the cache lives in the projects directory.
      environment.CLAUDE_CODE_LOG_CACHE_PATH = "%C/claude-code-log/cache.db";
      serviceConfig = {
        User = cfg.user;
        # Without --all-projects, watch only follows one project.
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe cfg.package)
          "watch"
          "--all-projects"
          "--projects-dir"
          cfg.projectsDir
          "--output"
          cfg.outputDir
        ] ++ cfg.extraArgs);
        Restart = "on-failure";

        CacheDirectory = "claude-code-log";
        ReadWritePaths = [ cfg.outputDir ];
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
