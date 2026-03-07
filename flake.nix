{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = {
    nixpkgs,
    systems,
    ...
  }: let
    forEachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    devShells = forEachSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      default = pkgs.mkShell {
        packages = with pkgs;
          [
            # Language toolchains
            elixir
            erlang
            gcc

            # Build tools
            cmake
            xz
            gnumake
            pkg-config

            # Dev tools
            nixd
            git
            nix-output-monitor
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.inotify-tools];

        shellHook = ''
          # Local tool state (gitignored)
          export MIX_HOME=$PWD/.nix-shell/mix
          export HEX_HOME=$PWD/.nix-shell/hex
          export ERL_LIBS=$HEX_HOME/lib/erlang/lib

          export LD_LIBRARY_PATH=${pkgs.glibc}/lib:${pkgs.stdenv.cc.cc.lib}:''${LD_LIBRARY_PATH:-}
          export LD=${pkgs.glibc}/lib/ld-linux-x86-64.so.2

          export PATH=$MIX_HOME/bin:$PATH
          export PATH=$MIX_HOME/escripts:$PATH
          export PATH=$HEX_HOME/bin:$PATH

          # IEx history
          export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_path '\"$PWD/.nix-shell/.erlang-history\"'"

          # First-time setup
          if [ ! -d "$MIX_HOME" ]; then
            mix local.hex --force
            mix local.rebar --force
          fi

          if [ -f mix.exs ]; then
            mix deps.get > /dev/null
          fi
        '';
      };
    });
  };
}
