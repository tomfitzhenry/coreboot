# Coreboot-side ROM definitions, built against stock upstream nixpkgs.
{
  pkgs,
  self,
  lib ? pkgs.lib,
}:
let
  coreboot = import ./coreboot.nix { inherit pkgs lib; };
  edk2 = import ./edk2.nix { inherit pkgs lib; };
  boards = import ./boards.nix {
    inherit
      pkgs
      self
      coreboot
      edk2
      lib
      ;
  };
in
{
  packages = {
    default = boards.cwwkAdlVboot;
    cwwk-adl-vboot = boards.cwwkAdlVboot;
    apu2-vboot = boards.apu2Vboot;
    edk2-coreboot-payload = edk2.edk2CorebootPayload;
    q35-rom = boards.q35BootUefi;
    q35-vboot-rom = boards.q35Vboot;
  };

  checks = import ./checks.nix {
    inherit pkgs lib;
    roms = boards;
    inherit (coreboot) defaultVersion;
  };
}
