{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    sbcl
    earthly
    tilt
    bun
    libev
    lmdb
    openssl
    curl
    websocat
  ];
  shellHook = ''
    export PATH="$HOME/.local/bin:$PATH"   # rodney
    export PATH="$HOME/.cargo/bin:$PATH"   # rho-cli
  '';
}
