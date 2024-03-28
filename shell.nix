{ pkgs ? import <nixpkgs> { } }:
let

  make-all = pkgs.writeShellScriptBin "make-all" ''
    if make fmt all
    then
        c=42
    else
        c=41
    fi

    printf '\e[%dm\e[K\e[m\n' $c
    test $c -ne 41
  '';

  watch = pkgs.writeShellScriptBin "watch" ''
    exec ${pkgs.watchexec}/bin/watchexec --restart --quiet -n \
      -- ${make-all}/bin/make-all
  '';

in
pkgs.mkShell {

  nativeBuildInputs = with pkgs; [
    gnumake
    lua-language-server
    luajitPackages.luacheck
    ripgrep
    stylua
    watch
    watchexec
  ];

}
