{
  pkgs,
  crane,
  crabefi-src,
}:
let
  # Clear UNIT ATTENTION sense data before retrying TEST UNIT READY, so a USB
  # mass storage device that latches unit attention at power-up becomes ready.
  src = pkgs.applyPatches {
    name = "crabefi-src";
    src = crabefi-src;
    patches = [ ./0001-usb-clear-sense-before-retry.patch ];
  };

  toolchain = pkgs.rust-bin.fromRustupToolchainFile (
    src + "/rust-toolchain.toml"
  );
  craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

  cargoVendorDir = craneLib.vendorMultipleCargoDeps {
    cargoLockList = [
      "${src}/Cargo.lock"
      "${toolchain}/lib/rustlib/src/rust/library/Cargo.lock"
    ];
  };
in
{
  package = craneLib.buildPackage {
    pname = "crabefi";
    version = crabefi-src.shortRev or "unstable";
    inherit src cargoVendorDir;

    CARGO_BUILD_TARGET = "x86_64-unknown-none";
    RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
    # The APU2/APU3 have no framebuffer; leave the `ui` feature off.
    cargoExtraArgs = "-p crabefi-coreboot --locked";

    doCheck = false;
    dontStrip = true;
    strictDeps = true;

    postPatch = ''
      # Upstream ships a dangling convenience symlink.
      find . -maxdepth 1 -type l -name crabefi.org -delete
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 target/x86_64-unknown-none/release/crabefi \
        $out/lib/crabefi/crabefi.elf
      runHook postInstall
    '';
  };

  # The payload is built for x86_64-unknown-none, so its tests cannot run on
  # the build host. Run the host-target unit tests in a separate derivation.
  tests = craneLib.mkCargoDerivation {
    pname = "crabefi-tests";
    version = crabefi-src.shortRev or "unstable";
    inherit src cargoVendorDir;
    cargoArtifacts = null;

    RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
    doInstallCargoArtifacts = false;

    buildPhaseCargoCommand = ''
      set -o pipefail
      cargo test -p crabefi-core \
        init_requests_sense_and_recovers_from_unit_attention 2>&1 | tee test.log
      grep -q 'init_requests_sense_and_recovers_from_unit_attention ... ok' \
        test.log
    '';
  };
}
