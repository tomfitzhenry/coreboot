{
  description = "coreboot PC Engines APU2/APU3 firmware with CrabEFI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";

    # Submodule revisions from .gitmodules at the coreboot revision this flake
    # builds. Injecting them keeps the build hermetic (no `git submodule`).
    coreboot-blobs = {
      url = "github:coreboot/blobs/c236894e3c1de8501f007a9bf61255684c89cd30";
      flake = false;
    };
    coreboot-vboot = {
      url = "github:coreboot/vboot/f691f7675d46c8f4726146803543a095b68477c5";
      flake = false;
    };

    crabefi-src = {
      url = "github:ArthurHeymans/CrabEFI/974ec2cac1f75947254c4822a690e0ac47e5270a";
      flake = false;
    };
  };

  outputs = inputs: import ./util/nixshell/flake.nix inputs;
}
