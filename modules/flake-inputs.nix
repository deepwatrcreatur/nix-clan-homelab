{ inputs, ... }:
let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  children =
    node: input:
    let
      edges = lock.nodes.${node}.inputs or { };
    in
    # WHY: follows edges point to a node already reachable by a direct edge.
    map (name: {
      key = edges.${name};
      input = input.${name};
    }) (builtins.filter (name: builtins.isString edges.${name}) (builtins.attrNames edges));
  # WHY: the same source can appear in multiple lock nodes with different
  # dependencies. Walk the lock nodes before deduplicating source paths.
  lockedInputs = builtins.genericClosure {
    startSet = children lock.root inputs;
    operator = { key, input }: children key input.inputs;
  };
  sources = builtins.listToAttrs (
    map ({ input, ... }: {
      name = builtins.baseNameOf (builtins.unsafeDiscardStringContext input.outPath);
      value = input.outPath;
    }) lockedInputs
  );
in
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages.flake-inputs = pkgs.linkFarm "homelab-flake-inputs" sources;

      checks.flake-inputs =
        pkgs.runCommand "homelab-flake-inputs-check"
          {
            nixpkgsSource = inputs.nixpkgs.outPath;
            rawInput = inputs.unified.outPath;
            transitiveInput = inputs.deploy-rs.inputs.utils.outPath;
            retained = config.packages.flake-inputs;
          }
          ''
            for source in "$nixpkgsSource" "$rawInput" "$transitiveInput"; do
              test "$(readlink "$retained/''${source##*/}")" = "$source"
            done
            touch "$out"
          '';
    };
}
