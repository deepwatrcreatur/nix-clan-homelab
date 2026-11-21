{ fetchurl, lib, stdenvNoCC }:
let
  version = "0.1.45";
in
stdenvNoCC.mkDerivation {
  pname = "beads-rust";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${version}/br-v${version}-linux_musl_amd64.tar.gz";
    hash = "sha256-2IipnHHrCCx/oa/k9ASmpw4rbQK43GXb4B+m+I1QCSo=";
  };

  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    tar -xzf "$src" br
    install -Dm755 br "$out/bin/beads-rust"
    runHook postInstall
  '';

  meta = {
    description = "Beads issue tracker";
    license = lib.licenses.mit;
    mainProgram = "beads-rust";
    platforms = [ "x86_64-linux" ];
  };
}
