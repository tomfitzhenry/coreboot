# EDK2 UEFI firmware built as a coreboot payload (UefiPayloadPkg).
#
# This replaces the `corebootPayload` attribute that was added to the nixpkgs
# edk2 package. It uses only stock `pkgs.edk2.mkDerivation`, but overrides the
# build command: stock hardcodes the host architecture (X64) before appending
# `$buildFlags`, whereas UefiPayloadPkg.dsc picks the PayloadEntry architecture
# from the *first* `-a` argument (`!if "IA32" in "$(ARCH)"`). coreboot enters
# payloads in 32-bit protected mode, so the entry must be IA32 while the DXE
# core stays X64. Passing `-a IA32` first and `-a X64` second yields `ARCH:
# IA32 X64` with a 32-bit entry point that switches to long mode.
{
  pkgs,
  lib ? pkgs.lib,
}:

let
  mkEdk2CorebootPayload =
    overrides:
    pkgs.edk2.mkDerivation "UefiPayloadPkg/UefiPayloadPkg.dsc" (
      finalAttrs:
      {
        pname = "edk2-coreboot-payload";
        version = pkgs.edk2.version;

        nativeBuildInputs = [
          pkgs.util-linux
          pkgs.nasm
          pkgs.acpica-tools
        ];

        hardeningDisable = [
          "format"
          "stackprotector"
          "pic"
          "fortify"
        ];

        buildFlags = [ "-D BOOTLOADER=COREBOOT" ];
        buildConfig = "RELEASE";

        # Put IA32 before X64 so UefiPayloadPkg.dsc builds the 32-bit
        # PayloadEntry (and the X64 DXE core it hands over to).
        buildPhase = ''
          runHook preBuild
          build -a IA32 -a X64 -b ${finalAttrs.buildConfig} -t GCC \
            -p UefiPayloadPkg/UefiPayloadPkg.dsc -n $NIX_BUILD_CORES $buildFlags
          runHook postBuild
        '';

        passthru = {
          # The built payload, for embedding in a coreboot ROM.
          payload = "${finalAttrs.finalPackage}/FV/UEFIPAYLOAD.fd";
        };

        meta = {
          description = "EDK2 UEFI firmware as a coreboot payload (UefiPayloadPkg)";
          homepage = "https://github.com/tianocore/edk2";
          license = lib.licenses.bsd2;
          maintainers = with lib.maintainers; [ tomfitzhenry ];
          platforms = lib.platforms.x86_64;
        };
      }
      // overrides
    );
in
{
  inherit mkEdk2CorebootPayload;
  edk2CorebootPayload = mkEdk2CorebootPayload { };
}
