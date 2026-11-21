# Node-level `tailscale serve` handlers (https://<host>/, :8443, ...), all set
# from a single unit. Separate units running `tailscale serve` concurrently
# race on the serve config's ETag and one fails. nixpkgs'
# services.tailscale.serve doesn't cover this: `tailscale serve set-config`
# only configures Tailscale Services (svc:<name>), not the node itself.
{ config, lib, ... }:

let
  cfg = config.services.tailscale-serve-node;
  tailscale = lib.getExe config.services.tailscale.package;
in
{
  options.services.tailscale-serve-node.commands = lib.mkOption {
    type = lib.types.listOf (lib.types.listOf lib.types.str);
    default = [ ];
    example = [
      [ "/srv/static" ]
      [ "--https=8443" "http://localhost:8080" ]
    ];
    description = ''
      Argument lists for `tailscale serve --bg`, applied in order after
      `tailscale serve reset`, so this is the whole node serve config: handlers
      set some other way are removed whenever the unit runs.
    '';
  };

  config = lib.mkIf (cfg.commands != [ ]) {
    systemd.services.tailscale-serve-node = {
      description = "Tailscale Serve node configuration";
      requires = [ "tailscale-online.target" ];
      after = [ "tailscale-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ (builtins.toJSON cfg.commands) ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${tailscale} serve reset
      '' + lib.concatMapStrings (args: ''
        ${tailscale} serve --bg ${lib.escapeShellArgs args}
      '') cfg.commands;
    };
  };
}
