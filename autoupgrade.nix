{ config, lib, pkgs, ... }:
let
  cfg = config.services.autoupgrade;
  inherit (lib) mkOption types;
in
{
  options = {
    services.autoupgrade = {
      enable = lib.mkEnableOption "autoupgrade";
      sendmail = mkOption {
        type = types.package;
      };
      recipient = mkOption {
        type = types.str;
      };
      gitAuthor = mkOption {
        type = types.str;
      };
      schedule = mkOption {
        type = types.str;
      };
    };
  };

  config = {
    systemd.services.autoupgrade = {
      serviceConfig = {
        Type = "oneshot";
      };
      # this script is frequently changed by upgrade, so restartIfChanged leads to
      # it invoking itself
      restartIfChanged = false;
      path = [
        pkgs.git
        pkgs.nixos-rebuild
        pkgs.openssh # for git commit signing
        cfg.sendmail
        pkgs.which
      ];
      environment = {
        NIX_PATH = builtins.concatStringsSep ":" config.nix.nixPath;
        HOME = "/root"; # attempting to fix git not reading /root/.gitconfig
      };
      script = ''
        set -ux -o pipefail
        cd /etc/nixos
        mkdir -p /root/upgrades
        log=/root/upgrades/$(date --iso-8601=seconds)
        set +e # still send the e-mail if it fails
        {
          git diff-index --exit-code HEAD \
            && git submodule update --remote \
            && ! git diff-index --exit-code HEAD \
            && time nixos-rebuild --install-bootloader --no-build-output switch \
            && git commit -am autoupgrade --author="${cfg.gitAuthor}"
        } &> "$log"
        status=$?
        set -e

        sendfile() {
          {
            echo "To: $1"
            echo "Subject: autoupgrade exited $status: $log"
            echo "MIME-Version: 1.0"
            echo "Content-Type: text/plain; charset=UTF-8"
            # base64-encode because long lines are invalid in SMTP and msmtp
            # appears to not enforce this on the client side, which (I think)
            # led to the DKIM signature being computed and *then* the lines
            # being rewrapped to be short enough, so the signature didn't match
            echo "Content-Transfer-Encoding: base64"
            echo
            base64 "$log"
          } | sendmail -t "$1"
        }
        sendfile "${cfg.recipient}" "$log"
      '';
    };
    systemd.timers.autoupgrade = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Unit = "autoupgrade.service";
      };
    };
  };
}
