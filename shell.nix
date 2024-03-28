{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {

  nativeBuildInputs = with pkgs; [
    lua-language-server
    luajitPackages.luacheck
    ripgrep
    stylua
  ];

}
