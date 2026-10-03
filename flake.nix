{
  description = "coreboot development SDK, plus Tom's CWWK CW-ADLN-NAS builds";

  # The upstream flake provides the coreboot development SDK (devShells).
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Build-only inputs for the ROM: mkCoreboot and the coreboot toolchain,
  # corebootFsp, corebootIntelMicrocode, the EDK2 coreboot payload and the
  # cbfstool/futility helpers. These are not in upstream nixpkgs yet, so pin
  # them here by explicit rev. The rev is pinned rather than locked so the
  # build stays reproducible without a committed flake.lock (upstream
  # gitignores /flake.lock), while `nixpkgs` floats exactly as upstream wants.
  inputs.nixpkgs-build.url = "github:tomfitzhenry/nixpkgs/d4f5af9ace16a3051884fd8b6043716e0cbca0cb";

  outputs =
    inputs:
    let
      self = inputs.self;
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs-build {
        inherit system;
        # The ROM embeds the non-free Intel FSP and microcode.
        config.allowUnfree = true;
      };

      # Assert the vboot RW_AB layout of an already-built ROM. Kept here
      # (rather than in nixpkgs) because it knows the board's CBFS contents.
      romStructureTest =
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

      # coreboot with vboot (verified boot) and the EDK2 UEFI payload for the
      # CWWK CW-ADLN-NAS, an Intel Alder Lake-N/Twin Lake (N355) NAS board.
      #
      # `src = self` is this repository, which carries the mainboard support,
      # the SuperIO COM1 console, the live-dumped GPIO table and the board's
      # vboot Kconfig block and 16 MiB RW_AB FMAP (`vboot-rwab.fmd`). The
      # public Intel FSP and the CPU microcode are injected from coreboot's
      # 3rdparty submodules via `files`.
      #
      # Runtime VBNV is stored in CMOS with a flash backup (the SoC selects
      # VBOOT_VBNV_CMOS_BACKUP_TO_FLASH), which is why the FMAP needs RW_NVRAM.
      rom = pkgs.mkCoreboot {
        src = self;
        defconfig = "cwwk_adln_nas_vboot";
        payload = pkgs.edk2.corebootPayload.payload;
        config = {
          VBOOT = "y";
          VBOOT_SLOTS_RW_AB = "y";
          # coreboot reserves the SMMSTORE region (the 0x80000 default matches
          # the FMAP). The stock EDK2 payload uses the EMU/volatile variable
          # backend, so UEFI variables are not persisted across reboots.
          SMMSTORE = "y";
          # Assemble the platform microcode from 3rdparty/intel-microcode.
          CPU_MICROCODE_CBFS_DEFAULT_BINS = "y";
          DEFAULT_CONSOLE_LOGLEVEL_8 = "y";
        };
        files = {
          "3rdparty/fsp" = pkgs.corebootFsp;
          "3rdparty/intel-microcode" = pkgs.corebootIntelMicrocode;
        };
        # futility (used to sign the RW slots) links against OpenSSL.
        extraNativeBuildInputs = [ pkgs.openssl ];
      };
    in
    # Upstream's devShells (coreboot toolchain + SDK tools)...
    (import ./util/nixshell/flake.nix inputs)
    # ...plus our build outputs.
    // {
      packages.${system} = {
        default = rom;
        coreboot = rom;
        # Exposed so the EDK2 coreboot payload can be built/cached via this
        # flake independently of the ROM.
        edk2-coreboot-payload = pkgs.edk2.corebootPayload;
      };

      checks.${system}.rom-structure = romStructureTest rom;
    };
}
