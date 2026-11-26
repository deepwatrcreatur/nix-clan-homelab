# Kernel and SSH hardening for routers, plus a smaller closure.
# UPSTREAM: the kernel part is nix-router-optimized's router-security-hardened
# (decision 0003); only settings it does not cover live here. docs/router-hardening.md
{
  config,
  den,
  inputs,
  ...
}:
let
  # WHY: shared with the VM test below.
  hardening = {
    imports = [ inputs.nix-router-optimized.nixosModules.router-security-hardened ];

    services.router-security-hardened = {
      enable = true;
      kernelHardening = {
        enable = true;
        # WHY: VRRP members and a standby routing via its peer receive traffic
        # asymmetrically; strict filtering drops it. router-role sets 2 too.
        rpFilter = "loose";
      };
    };

    # PAM already denies it (sshd's unixAuth follows PasswordAuthentication);
    # stop advertising the method too, as lxc-core does.
    services.openssh.settings.KbdInteractiveAuthentication = false;

    # WHY: saves evaluating and shipping the option manual; man pages stay.
    documentation.nixos.enable = false;
  };
in
{
  den.aspects.router-hardening.nixos = hardening;
  den.aspects.router-role.includes = [ den.aspects.router-hardening ];

  perSystem =
    { pkgs, ... }:
    let
      router = config.flake.nixosConfigurations.elitedesk.config;
    in
    {
      checks.router-hardening-options =
        assert router.services.router-security-hardened.kernelHardening.enable;
        assert router.boot.kernel.sysctl."kernel.kptr_restrict" == 2;
        assert router.boot.kernel.sysctl."net.core.bpf_jit_harden" == 2;
        assert !router.services.openssh.settings.KbdInteractiveAuthentication;
        # The hardening must not disturb forwarding or the loose filter.
        assert router.boot.kernel.sysctl."net.ipv4.conf.all.forwarding" == true;
        assert router.boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" == 2;
        # Ping stays answered; the dashboard and alerting probe the routers.
        assert router.boot.kernel.sysctl."net.ipv4.icmp_echo_ignore_all" == 0;
        pkgs.runCommand "router-hardening-options" { } "touch $out";

      checks.router-hardening = pkgs.testers.runNixOSTest {
        name = "router-hardening";
        nodes.machine = {
          imports = [ hardening ];
          services.openssh.enable = true;
          services.openssh.settings.PasswordAuthentication = false;
        };
        testScript = ''
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("systemd-sysctl.service")
          for key, value in {
              "kernel.kptr_restrict": "2",
              "kernel.dmesg_restrict": "1",
              "kernel.unprivileged_bpf_disabled": "1",
              "net.core.bpf_jit_harden": "2",
              "fs.suid_dumpable": "0",
              "net.ipv4.conf.all.rp_filter": "2",
          }.items():
              got = machine.succeed(f"sysctl -n {key}").strip()
              assert got == value, f"{key}: {got}"
          # A missing module or install command would also make modprobe fail.
          machine.succeed("modinfo tipc")
          status, output = machine.execute("modprobe tipc 2>&1")
          assert status != 0 and "/bin/false' for module tipc: retcode 1" in output, output
          machine.fail("lsmod | grep -qw tipc")
          methods = machine.succeed("sshd -T | grep -i kbdinteractive")
          assert "no" in methods.split(), methods
        '';
      };
    };
}
