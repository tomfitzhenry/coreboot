{
  description = "coreboot development SDK, plus Tom's CWWK CW-ADLN-NAS and APU2 builds";

  # The upstream flake provides the coreboot development SDK (devShells). The
  # ROM definitions live in ./nix and use only stock nixpkgs, so there is no
  # nixpkgs fork input.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    inputs:
    let
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs {
        inherit system;
        # The ROMs embed the non-free Intel FSP and microcode and the AMD AGESA
        # blob.
        config.allowUnfree = true;
      };

      ours = import ./nix {
        inherit pkgs;
        self = inputs.self;
      };
    in
    # Upstream's devShells (coreboot toolchain + SDK tools)...
    (import ./util/nixshell/flake.nix inputs)
    # ...plus our build outputs and checks.
    // {
      packages.${system} = ours.packages;
      checks.${system} = ours.checks;
    };
}
