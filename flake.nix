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
      beam29 = pkgs.beam29Packages;
    in {
      default = pkgs.mkShell {
        packages = with pkgs;
          [
            # Language toolchains
            beam29.elixir_1_20
            beam29.erlang

            # Dev tools
            nixd
            git
            nix-output-monitor
            cocogitto

            # Prose linting
            vale
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.inotify-tools];

        shellHook = ''
          # Local tool state (gitignored)
          export MIX_HOME=$PWD/.nix-shell/mix
          export HEX_HOME=$PWD/.nix-shell/hex
          export ERL_LIBS=$HEX_HOME/lib/erlang/lib

          export PATH=$MIX_HOME/bin:$PATH
          export PATH=$MIX_HOME/escripts:$PATH
          export PATH=$HEX_HOME/bin:$PATH

          # IEx history
          export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_path '\"$PWD/.nix-shell/.erlang-history\"'"

          mix local.hex --if-missing --force
          mix local.rebar --if-missing --force

          if [ -f mix.exs ]; then
            mix deps.get > /dev/null
          fi
        '';
      };
    });
  };
}
