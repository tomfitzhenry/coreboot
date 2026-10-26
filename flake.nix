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
    coreboot-fsp = {
      url = "github:coreboot/fsp/98426bfd958eb7397c474ff5d440dc9a1d146215";
      flake = false;
    };
    coreboot-intel-microcode = {
      url = "github:coreboot/intel-microcode/bdc92abe5c499c3fd7988b76a128d05c9120a520";
      flake = false;
    };

    crabefi-src = {
      url = "github:ArthurHeymans/CrabEFI/974ec2cac1f75947254c4822a690e0ac47e5270a";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      rust-overlay,
      crane,
      coreboot-blobs,
      coreboot-vboot,
      coreboot-fsp,
      coreboot-intel-microcode,
      crabefi-src,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [ "x86_64-linux" ];
      forAllSystems = lib.genAttrs systems;

      # Keep the pre-existing `nix develop` SDK available.
      legacy = import ./util/nixshell/flake.nix inputs;

      mkSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          crabefi = import ./pkgs/crabefi {
            inherit pkgs crane crabefi-src;
          };

          mkCoreboot =
            {
              name,
              defconfig,
              vboot ? false,
              useBlobs ? false,
              useFsp ? false,
              extraConfig ? "",
            }:
            let
              config = "configs/config.${defconfig}";
            in
            pkgs.stdenvNoCC.mkDerivation {
              pname = "coreboot-${name}${lib.optionalString vboot "-vboot"}";
              version = self.shortRev or self.dirtyShortRev or "unknown";
              src = self;

              nativeBuildInputs = [
                # stdenvNoCC has no host compiler; Kconfig and the host
                # utilities still need one.
                pkgs.buildPackages.stdenv.cc
                pkgs.coreboot-toolchain.i386
                pkgs.pkg-config
                pkgs.python3
                pkgs.futility
              ];

              # amdfwtool needs libcrypto for the Avalon PSP blobs.
              buildInputs = [ pkgs.openssl ];

              strictDeps = true;
              enableParallelBuilding = true;
              dontStrip = true;
              dontPatchELF = true;

              postPatch = ''
                # Submodules are replaced by pinned flake inputs.
                rm -rf 3rdparty/blobs 3rdparty/vboot
                mkdir -p 3rdparty/blobs 3rdparty/vboot
                cp -rT ${coreboot-blobs} 3rdparty/blobs
                cp -rT ${coreboot-vboot} 3rdparty/vboot

                patchShebangs util/xcompile/xcompile
                patchShebangs util/genbuild_h/genbuild_h.sh
              '' + lib.optionalString vboot ''
                # coreboot generates a test-only GBB HWID with this script
                # when CONFIG_GBB_HWID is empty.
                patchShebangs util/chromeos/gen_test_hwid.sh
              '' + lib.optionalString useFsp ''
                # The Intel FSP and microcode submodules are not available in
                # the Nix build sandbox; inject the pinned flake inputs.
                rm -rf 3rdparty/fsp 3rdparty/intel-microcode
                mkdir -p 3rdparty/fsp 3rdparty/intel-microcode
                cp -rT ${coreboot-fsp} 3rdparty/fsp
                cp -rT ${coreboot-intel-microcode} 3rdparty/intel-microcode
              '';

              configurePhase = ''
                runHook preConfigure
                cp ${config} .config
                cat >> .config <<'EOF'
# CONFIG_PAYLOAD_NONE is not set
# CONFIG_PAYLOAD_SEABIOS is not set
# CONFIG_PXE is not set
# CONFIG_BUILD_IPXE is not set
# CONFIG_MEMTEST_SECONDARY_PAYLOAD is not set
CONFIG_PAYLOAD_ELF=y
CONFIG_PAYLOAD_FILE="${crabefi.package}/lib/crabefi/crabefi.elf"
CONFIG_COMPRESSED_PAYLOAD_LZMA=y
EOF
              '' + lib.optionalString useBlobs ''
                cat >> .config <<'EOF'
CONFIG_USE_BLOBS=y
EOF
              '' + lib.optionalString vboot ''
                # Development images: use vboot's test/devkeys and mock
                # secdata (no TPM), so this is not production-ready
                # measured boot or anti-rollback.
                cat >> .config <<'EOF'
CONFIG_VBOOT=y
CONFIG_VBOOT_SLOTS_RW_AB=y
EOF
              '' + lib.optionalString (extraConfig != "") ''
                cat >> .config <<'EOF'
${extraConfig}
EOF
              '' + ''
                make olddefconfig
                runHook postConfigure
              '';

              makeFlags = [
                "BUILD_TIMELESS=1"
                "CONFIG_ANY_TOOLCHAIN=y"
                "UPDATED_SUBMODULES=1"
                "KERNELVERSION=${self.shortRev or self.dirtyShortRev or "unknown"}"
                "FUTILITY=${pkgs.futility}/bin/futility"
              ];

              installPhase = ''
                runHook preInstall
                install -Dm644 build/coreboot.rom $out/coreboot.rom
                install -Dm644 .config $out/config
                install -Dm644 ${config} $out/defconfig
              '' + ''
                runHook postInstall
              '';
            };

          apu2-vboot = mkCoreboot {
            name = "pcengines-apu2";
            defconfig = "pcengines_apu2";
            vboot = true;
            useBlobs = true;
          };
          apu3-vboot = mkCoreboot {
            name = "pcengines-apu3";
            defconfig = "pcengines_apu3";
            vboot = true;
            useBlobs = true;
          };
          q35-vboot = mkCoreboot {
            name = "qemu-q35";
            defconfig = "emulation_qemu_x86_q35_smm_tseg";
            vboot = true;
            extraConfig = ''
              CONFIG_VBOOT_MOCK_SECDATA=y
              CONFIG_DEFAULT_CONSOLE_LOGLEVEL_8=y
            '';
          };
          cwwk-adln-nas-vboot = mkCoreboot {
            name = "cwwk-adln-nas";
            defconfig = "cwwk_adln_nas_vboot";
            vboot = true;
            useBlobs = true;
            useFsp = true;
          };

          release = pkgs.runCommand "coreboot-apu2-apu3-cwwk-crabefi-${self.shortRev or self.dirtyShortRev or "unknown"}" { } ''
            mkdir -p $out
            install -m644 ${apu2-vboot}/coreboot.rom $out/apu2-vboot-coreboot.rom
            install -m644 ${apu2-vboot}/config $out/apu2-vboot.config
            install -m644 ${apu3-vboot}/coreboot.rom $out/apu3-vboot-coreboot.rom
            install -m644 ${apu3-vboot}/config $out/apu3-vboot.config
            install -m644 ${cwwk-adln-nas-vboot}/coreboot.rom $out/cwwk-adln-nas-vboot-coreboot.rom
            install -m644 ${cwwk-adln-nas-vboot}/config $out/cwwk-adln-nas-vboot.config
            (cd $out && sha256sum *.rom *.config > SHA256SUMS)
          '';

        in
        {
          packages = {
            crabefi = crabefi.package;
            crabefi-tests = crabefi.tests;
            inherit
              apu2-vboot
              apu3-vboot
              q35-vboot
              cwwk-adln-nas-vboot
              release
              ;
            futility = pkgs.futility;
            default = apu2-vboot;
          };

          checks = {
            crabefi-tests = crabefi.tests;

            q35-vboot = pkgs.testers.runNixOSTest (
              import ./tests/q35-vboot.nix {
                inherit pkgs;
                rom = q35-vboot;
              }
            );
          };
        };
    in
    legacy
    // {
      packages = forAllSystems (system: (mkSystem system).packages);
      checks = forAllSystems (system: (mkSystem system).checks);
    };
}
