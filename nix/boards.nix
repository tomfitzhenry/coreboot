# Board packages built from this repository (or from mainline, for the APU2).
{
  pkgs,
  self,
  coreboot,
  edk2,
  lib ? pkgs.lib,
}:

let
  inherit (coreboot)
    mkCoreboot
    defaultSrc
    corebootBlobs
    corebootFsp
    corebootIntelMicrocode
    ;

  payload = edk2.edk2CorebootPayload.payload;

  # coreboot with vboot (verified boot) and the EDK2 UEFI payload for the CWWK
  # CW-ADLN-NAS, an Intel Alder Lake-N/Twin Lake (N355) NAS board.
  #
  # `src = self` is this repository, which carries the mainboard support, the
  # SuperIO COM1 console, the live-dumped GPIO table and the board's vboot
  # Kconfig block and 16 MiB RW_AB FMAP (`vboot-rwab.fmd`). The public Intel
  # FSP and the CPU microcode are injected from coreboot's 3rdparty submodules
  # via `files`.
  #
  # Runtime VBNV is stored in CMOS with a flash backup (the SoC selects
  # VBOOT_VBNV_CMOS_BACKUP_TO_FLASH), which is why the FMAP needs RW_NVRAM.
  cwwkAdlVboot = mkCoreboot {
    src = self;
    defconfig = "cwwk_adln_nas_vboot";
    inherit payload;
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
      "3rdparty/fsp" = corebootFsp;
      "3rdparty/intel-microcode" = corebootIntelMicrocode;
    };
    # futility (used to sign the RW slots) links against OpenSSL.
    extraNativeBuildInputs = [ pkgs.openssl ];
  };

  # coreboot with vboot and the EDK2 UEFI payload for the PC Engines APU2,
  # flashed as a full 8 MiB RW_AB image.
  #
  # Mainline coreboot does not support vboot on this board; the patch ports the
  # pcengines fork's support (FMAP, mainboard Kconfig and AMDFW_OUTSIDE_CBFS)
  # onto current mainline. The APU2's AGESA blob is redistributable but under a
  # restrictive AMD license, so the ROM is unfree and excluded from caches.
  #
  # https://github.com/pcengines/coreboot/blob/8d3e714804b1b2bb5bc89e3ffd9cb3c34f8eb0c6/src/mainboard/pcengines/apu2/Kconfig
  apu2Vboot = mkCoreboot {
    src = defaultSrc;
    defconfig = "pcengines_apu2_vboot";
    inherit payload;
    config = {
      VBOOT = "y";
      VBOOT_SLOTS_RW_AB = "y";
      # The APU2 defconfig builds secondary payloads (iPXE, Memtest86+) by
      # fetching their sources from the network at build time; disable them.
      PXE = "n";
      MEMTEST_SECONDARY_PAYLOAD = "n";
    };
    files = {
      "3rdparty/blobs" = corebootBlobs;
    };
    patches = [ ./patches/apu2-vboot.patch ];
    # amdfwtool, which assembles the AGESA stage, links against OpenSSL.
    extraNativeBuildInputs = [ pkgs.openssl ];
  };

  # QEMU q35 emulation board with the EDK2 payload, used by the boot-uefi VM
  # test. It has no vboot, just a console log level the test can match. Built
  # from mainline, which is what the q35 tests were validated against; this
  # tree may be based on an older coreboot.
  q35BootUefi = mkCoreboot {
    src = defaultSrc;
    defconfig = "emulation_qemu_x86_q35_smm_tseg";
    inherit payload;
    config = {
      DEFAULT_CONSOLE_LOGLEVEL_5 = "y";
    };
  };

  # QEMU q35 emulation board with vboot (RW_AB) and the EDK2 payload, used by
  # the vboot A/B fallback VM test. `VBOOT_MOCK_SECDATA` stands in for the
  # TPM the emulation board lacks.
  q35Vboot = mkCoreboot {
    src = defaultSrc;
    defconfig = "emulation_qemu_x86_q35_smm_tseg";
    inherit payload;
    config = {
      VBOOT = "y";
      VBOOT_SLOTS_RW_AB = "y";
      VBOOT_MOCK_SECDATA = "y";
      # Spew level so vboot's firmware selection messages are on the serial
      # console.
      DEFAULT_CONSOLE_LOGLEVEL_8 = "y";
    };
  };
in
{
  inherit
    cwwkAdlVboot
    apu2Vboot
    q35BootUefi
    q35Vboot
    ;
}
