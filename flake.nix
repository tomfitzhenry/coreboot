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

  outputs =
    inputs@{
      self,
      nixpkgs,
      rust-overlay,
      crane,
      coreboot-blobs,
      coreboot-vboot,
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

          corebootPkgs = pkgs.extend (import ./overlays/coreboot-utils.nix);

          mkCoreboot =
            {
              name,
              defconfig,
              vboot ? false,
              useBlobs ? false,
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
              ] ++ lib.optional vboot pkgs.openssl;

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
                # vboot's futility is built in-tree and signs the RW slots.
                # Its scripts and objects are copied from the pinned submodule,
                # so make them writable before patching the interpreters.
                chmod -R u+w 3rdparty/vboot
                patchShebangs 3rdparty/vboot
                # coreboot generates a test-only GBB HWID with this script
                # when CONFIG_GBB_HWID is empty.
                patchShebangs util/chromeos/gen_test_hwid.sh

                # glibc 2.44 (C23) keeps const on strchr()/strrchr() results,
                # which the pinned vboot assigns to `char *`. Keep the warning
                # but do not let it abort the futility build.
                substituteInPlace util/futility/Makefile.mk \
                  --replace-fail \
                    'WERROR="-Werror -Wno-deprecated-declarations"' \
                    'WERROR="-Werror -Wno-deprecated-declarations -Wno-error=discarded-qualifiers"'
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
CONFIG_PAYLOAD_FILE="${crabefi}/lib/crabefi/crabefi.elf"
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
          # Experimental: requires hardware validation. The fTPM NVRAM, ACPI,
          # CRB and bootloader assumptions are unverified, and vboot still uses
          # CONFIG_VBOOT_MOCK_SECDATA=y. Keep optional; not in release/default.
          apu2-vboot-ftpm = mkCoreboot {
            name = "pcengines-apu2-ftpm";
            defconfig = "pcengines_apu2";
            vboot = true;
            useBlobs = true;
            extraConfig = ''
              CONFIG_PSP_FTPM=y
              CONFIG_TPM2=y
              CONFIG_VBOOT_MOCK_SECDATA=y
            '';
          };
          apu3-vboot-ftpm = mkCoreboot {
            name = "pcengines-apu3-ftpm";
            defconfig = "pcengines_apu3";
            vboot = true;
            useBlobs = true;
            extraConfig = ''
              CONFIG_PSP_FTPM=y
              CONFIG_TPM2=y
              CONFIG_VBOOT_MOCK_SECDATA=y
            '';
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

          release = pkgs.runCommand "pcengines-apu2-apu3-crabefi-${self.shortRev or self.dirtyShortRev or "unknown"}" { } ''
            mkdir -p $out
            install -m644 ${apu2-vboot}/coreboot.rom $out/apu2-vboot-coreboot.rom
            install -m644 ${apu2-vboot}/config $out/apu2-vboot.config
            install -m644 ${apu3-vboot}/coreboot.rom $out/apu3-vboot-coreboot.rom
            install -m644 ${apu3-vboot}/config $out/apu3-vboot.config
            (cd $out && sha256sum *.rom *.config > SHA256SUMS)
          '';

        in
        {
          packages = {
            inherit
              crabefi
              apu2-vboot
              apu3-vboot
              apu2-vboot-ftpm
              apu3-vboot-ftpm
              q35-vboot
              release
              ;
            coreboot-utils = corebootPkgs.coreboot-utils;
            default = apu2-vboot;
          };

          checks = {
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
      overlays = {
        default = import ./overlays/coreboot-utils.nix;
        coreboot-utils = import ./overlays/coreboot-utils.nix;
      };

      packages = forAllSystems (system: (mkSystem system).packages);
      checks = forAllSystems (system: (mkSystem system).checks);
    };
}
