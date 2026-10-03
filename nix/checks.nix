# Structural and boot checks for the ROMs.
#
# The structure tests assert the vboot RW_AB layout and CBFS contents of an
# already-built ROM without hardware; the VM tests boot q35 ROMs in QEMU. The
# ROMs are built by the flake and closed over here, rather than being rebuilt
# from a nixpkgs `mkCoreboot`/`edk2.corebootPayload` (which no longer exists).
{
  pkgs,
  roms,
  defaultVersion,
  lib ? pkgs.lib,
}:

let
  # Assert the vboot RW_AB layout of the CWWK ROM. Kept here (rather than in
  # nixpkgs) because it knows the board's CBFS contents.
  cwwkRomStructureTest =
    rom:
    pkgs.runCommand "corebootVboot_cwwkAdl-rom-structure-test"
      {
        nativeBuildInputs = [
          pkgs.cbfstool
          pkgs.futility
        ];
      }
      ''
        set -euo pipefail
        rom=${rom}/coreboot.rom

        # The FMAP must describe vboot's RO + RW_A + RW_B layout, including
        # the RW_NVRAM region required by the flash-backed VBNV.
        cbfstool "$rom" layout > layout.txt
        for region in GBB COREBOOT VBLOCK_A VBLOCK_B FW_MAIN_A FW_MAIN_B \
          RW_FWID_A RW_FWID_B RW_NVRAM RECOVERY_MRC_CACHE RW_MRC_CACHE SMMSTORE; do
          grep -q "'$region'" layout.txt
        done

        # The early stages and the read-only blobs live in COREBOOT...
        cbfstool "$rom" print -r COREBOOT > coreboot.cbfs
        grep -q 'fallback/romstage' coreboot.cbfs
        grep -q 'fspm.bin' coreboot.cbfs
        grep -q 'cpu_microcode_blob.bin' coreboot.cbfs

        # ...while the RW slots carry ramstage, FSP-S and the payload.
        for slot in A B; do
          cbfstool "$rom" print -r "FW_MAIN_$slot" > "fw_main_$slot.cbfs"
          grep -q 'fallback/ramstage' "fw_main_$slot.cbfs"
          grep -q 'fallback/payload' "fw_main_$slot.cbfs"
          grep -q 'fsps.bin' "fw_main_$slot.cbfs"
        done

        # Each VBLOCK preamble must sign its FW_MAIN body.
        futility dump_fmap -x "$rom" VBLOCK_A FW_MAIN_A VBLOCK_B FW_MAIN_B \
          > /dev/null
        futility show -f FW_MAIN_A VBLOCK_A | grep -q 'Body verification succeeded'
        futility show -f FW_MAIN_B VBLOCK_B | grep -q 'Body verification succeeded'

        mkdir -p $out
        cp "$rom" $out/coreboot.rom
      '';

  # Structural check of the APU2 vboot ROM, runnable without hardware (there is
  # no APU2 QEMU model). It asserts that the vboot RW_AB FMAP and the signed
  # firmware slots are present, that the read-only files (AGESA, spd.bin,
  # romstage) are kept out of the RW slots, and that each VBLOCK signs its
  # FW_MAIN body.
  apu2RomStructureTest =
    rom:
    pkgs.stdenv.mkDerivation {
      pname = "corebootVboot_apu2-rom-structure-test";
      version = defaultVersion;
      dontUnpack = true;
      nativeBuildInputs = [
        pkgs.cbfstool
        pkgs.futility
      ];

      buildCommand = ''
        set -euo pipefail
        rom=${rom}/coreboot.rom

        # The FMAP must describe vboot's RO + RW_A + RW_B layout.
        cbfstool "$rom" layout > layout.txt
        for region in GBB COREBOOT VBLOCK_A VBLOCK_B FW_MAIN_A FW_MAIN_B \
          RW_FWID_A RW_FWID_B; do
          grep -q "'$region'" layout.txt
        done

        # AGESA, spd.bin and romstage are read-only: present in COREBOOT...
        cbfstool "$rom" print -r COREBOOT > coreboot.cbfs
        grep -q '^AGESA' coreboot.cbfs
        grep -q 'spd.bin' coreboot.cbfs
        grep -q 'fallback/romstage' coreboot.cbfs

        # ...and absent from both RW slots, which instead carry the payload.
        for slot in A B; do
          cbfstool "$rom" print -r "FW_MAIN_$slot" > "fw_main_$slot.cbfs"
          grep -q 'fallback/ramstage' "fw_main_$slot.cbfs"
          grep -q 'fallback/payload' "fw_main_$slot.cbfs"
          ! grep -q '^AGESA' "fw_main_$slot.cbfs"
          ! grep -q 'spd.bin' "fw_main_$slot.cbfs"
          ! grep -q 'fallback/romstage' "fw_main_$slot.cbfs"
        done

        # Each VBLOCK preamble must sign its FW_MAIN body.
        futility dump_fmap -x "$rom" VBLOCK_A FW_MAIN_A VBLOCK_B FW_MAIN_B \
          > /dev/null
        futility show -f FW_MAIN_A VBLOCK_A | grep -q 'Body verification succeeded'
        futility show -f FW_MAIN_B VBLOCK_B | grep -q 'Body verification succeeded'

        mkdir -p $out
        cp "$rom" $out/coreboot.rom
      '';

      meta = {
        description = "Structural check of the PC Engines APU2 vboot ROM";
        # The test embeds the ROM, which carries the unfree AGESA blob.
        license = [
          lib.licenses.gpl2
          lib.licenses.unfree
        ];
        maintainers = with lib.maintainers; [ tomfitzhenry ];
      };
    };
in
{
  cwwk-rom-structure = cwwkRomStructureTest roms.cwwkAdlVboot;
  apu2-rom-structure = apu2RomStructureTest roms.apu2Vboot;

  coreboot-boot-uefi = pkgs.testers.runNixOSTest (
    import ./tests/boot-uefi.nix {
      inherit pkgs;
      rom = roms.q35BootUefi;
    }
  );

  coreboot-vboot = pkgs.testers.runNixOSTest (
    import ./tests/vboot.nix {
      inherit pkgs;
      rom = roms.q35Vboot;
    }
  );
}
