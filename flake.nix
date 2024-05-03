{
  description = "Development environment for nvim-atlas";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    flake-utils.url =
      "github:numtide/flake-utils/1ef2e671c3b0c19053962c07dbda38332dcebf26";
  };

  outputs = { self, nixpkgs, flake-utils, }:
    flake-utils.lib.eachDefaultSystem (system:
      let

        pkgs = nixpkgs.legacyPackages.${system};

        make-all = pkgs.writeShellScriptBin "make-all" ''
          if [ $# -eq 0 ]
          then
              set -- make test lint fmt
          fi

          if "$@"
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
            -- ${make-all}/bin/make-all "$@"
        '';

      in {
        formatter = pkgs.nixfmt;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gnumake
            lua-language-server
            luajitPackages.luacheck
            ripgrep
            stylua
            watch
            watchexec
          ];
        };
      });
}
