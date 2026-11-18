# LXC container core aspect.
# Ported from unified den/aspects/lxc-core.nix.
{ den, ... }:
{
  den.aspects.lxc-core = {
    includes = [ den.aspects.nixos-base ];

    nixos =
      { modulesPath, lib, ... }:
      {
        imports = [
          "${modulesPath}/virtualisation/lxc-container.nix"
        ];

        # WHY: container build sandboxing fails inside unprivileged LXC
        nix.settings.sandbox = lib.mkDefault false;

        # WHY: debugfs is not accessible in unprivileged LXC containers; disabling prevents failed systemd mount unit
        systemd.mounts = [
          {
            what = "debugfs";
            where = "/sys/kernel/debug";
            enable = false;
          }
        ];

        security.wrappers.sudo.setuid = true;

        # OpenSSH settings for LXC
        services.openssh.settings = {
          PasswordAuthentication = lib.mkDefault true;
          PermitRootLogin = lib.mkDefault "yes";
          X11Forwarding = false;
        };

        # Root interactive shell uses fish via bash wrapper
        custom.fishInteractiveShell.users = [ "root" ];
      };
  };
}
