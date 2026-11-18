# Login shell is bash, but interactive sessions exec fish.
#
# WHY: Tools that run commands over SSH (e.g. VS Code Remote, rsync wrappers,
# automation agents) send POSIX shell snippets through the login shell. With fish
# as the login shell those snippets fail to parse. Keeping bash as the login shell
# fixes non-interactive commands while interactive sessions immediately exec fish.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.fishInteractiveShell;
in
{
  options.custom.fishInteractiveShell.users = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Users whose login shell is bash but whose interactive shells exec fish.";
  };

  config = lib.mkIf (cfg.users != [ ]) {
    programs.fish.enable = true;

    # Priority 90: beats plain definitions without clashing with mkForce users.
    users.users = lib.genAttrs cfg.users (_: {
      shell = lib.mkOverride 90 pkgs.bashInteractive;
    });

    # /etc/bashrc only runs this block for interactive shells. Skip it when
    # bash was started from fish (so `bash` inside fish still works) and when
    # bash is running a command string (`ssh host 'cmd'`).
    programs.bash.interactiveShellInit = ''
      case " ${lib.concatStringsSep " " cfg.users} " in
        *" $USER "*)
          if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING:-} ]]; then
            shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
            exec ${config.programs.fish.package}/bin/fish $LOGIN_OPTION
          fi
          ;;
      esac
    '';
  };
}
