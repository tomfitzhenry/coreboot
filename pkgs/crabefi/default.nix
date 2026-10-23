{
  pkgs,
  crane,
  crabefi-src,
}:
let
  toolchain = pkgs.rust-bin.fromRustupToolchainFile (
    crabefi-src + "/rust-toolchain.toml"
  );
  craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
in
craneLib.buildPackage {
  pname = "crabefi";
  version = crabefi-src.shortRev or "unstable";
  src = crabefi-src;

  cargoVendorDir = craneLib.vendorMultipleCargoDeps {
    cargoLockList = [
      "${crabefi-src}/Cargo.lock"
      "${toolchain}/lib/rustlib/src/rust/library/Cargo.lock"
    ];
  };

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
}
