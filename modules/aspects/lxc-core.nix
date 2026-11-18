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

        # WHY: unprivileged containers cannot create zram devices;
        # nixos-base enables zram by default, so the setup unit would fail.
        zramSwap.enable = false;

        # SECURITY: keys only. Root stays reachable by key because clan
        # deploys as root with the operator keys; unified allowed passwords.
        services.openssh.settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "prohibit-password";
          X11Forwarding = false;
        };

        custom.fishInteractiveShell.users = [ "root" ];
      };
  };
}
