{ inputs, ... }:
{
  den.aspects.desktop-niri-cosmic-fallback.nixos =
    {
      lib,
      pkgs,
      ...
    }:
    let
      # WHY: greetd can start the
      # session before connectors appear, which leaves a black screen.
      niriSessionCommand = pkgs.writeShellScript "niri-session-greetd" ''
        set -eu

        for _ in $(seq 1 50); do
          if ls /sys/class/drm/card*-*/status >/dev/null 2>&1 \
            && grep -q "^connected$" /sys/class/drm/card*-*/status 2>/dev/null; then
            break
          fi
          sleep 0.2
        done

        exec ${pkgs.niri}/bin/niri-session
      '';

      greeterCommand = pkgs.writeShellScript "niri-greetd-greeter" ''
        set -eu
        exec ${pkgs.tuigreet}/bin/tuigreet \
          --time \
          --remember \
          --cmd ${lib.escapeShellArg (toString niriSessionCommand)}
      '';

      # WHY: collect comparable samples for investigating the
      # COSMIC memory growth that prompted the switch.
      trialMetrics = pkgs.writeShellScript "niri-trial-metrics" ''
        set -u
        export PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.gawk
            pkgs.procps
          ]
        }

        dir="$HOME/.local/state/niri-trial"
        file="$dir/metrics.csv"
        mkdir -p "$dir"
        [ -e "$file" ] || echo "time,niri_pid,niri_rss_kb,niri_cpu_ticks,noctalia_rss_kb,vram_used_b" > "$file"

        pid=$(pgrep -o -x niri || true)
        rss=""
        ticks=""
        if [ -n "$pid" ]; then
          rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)
          ticks=$(awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null || true)
        fi
        noctalia=$(ps -C noctalia -o rss= 2>/dev/null | awk '{s += $1} END {print s + 0}')
        vram=$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1 || true)

        echo "$(date -Iseconds),$pid,$rss,$ticks,$noctalia,$vram" >> "$file"
      '';
    in
    {
      imports = [
        (import ../_nixos/workstation-niri.nix { inherit inputs; })
        (import ../_nixos/desktop-noctalia.nix { inherit inputs; })
      ];

      # INVARIANT: priority 60 overrides the Niri defaults and yields to COSMIC's mkForce.
      services.greetd.settings = {
        initial_session.command = lib.mkOverride 60 (toString niriSessionCommand);
        default_session.command = lib.mkOverride 60 (toString greeterCommand);
      };

      specialisation.cosmic.configuration = {
        imports = [ ../_nixos/desktop-cosmic.nix ];

        system.nixos.tags = [ "cosmic" ];

        programs.niri.enable = lib.mkForce false;

        # WHY: replace the inherited portal list to give COSMIC priority.
        xdg.portal.config.common.default = lib.mkForce [
          "cosmic"
          "gtk"
        ];
      };

      systemd.user.services.niri-trial-metrics = {
        description = "Record Niri trial resource usage";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = toString trialMetrics;
        };
      };

      systemd.user.timers.niri-trial-metrics = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
        };
      };

      home-manager.users.deepwatrcreatur = {
        # WHY: this host's terminal binds use Ghostty; nothing else installs it.
        home.packages = [ pkgs.ghostty ];
        programs.niri.settings = {
          outputs."HDMI-A-1".scale = 1.0;
          animations.slowdown = lib.mkForce 0.6;
          layout.shadow.enable = lib.mkForce false;

          binds = {
            "Mod+Return".action = lib.mkForce { spawn = [ "${pkgs.ghostty}/bin/ghostty" ]; };
            "Mod+E".action = lib.mkForce { spawn = [ "${pkgs.ghostty}/bin/ghostty" ]; };
            # Vicinae alongside Noctalia's launcher (Mod+Space); same key as on
            # the Plasma hosts.
            "Alt+Space".action.spawn = [
              "${pkgs.vicinae}/bin/vicinae"
              "toggle"
            ];
          };
        };

        # `vicinae toggle` needs the server running.
        programs.vicinae = {
          enable = true;
          systemd.enable = true;
        };

        programs.noctalia.settings = {
          shell.panel.transparency_mode = lib.mkForce "solid";
          # WHY: other templates write GTK, Qt and starship config outside Home Manager,
          # which would carry over when booting into the COSMIC specialisation.
          theme.templates.builtin_ids = lib.mkForce [ "niri" ];
        };
      };
    };
}
