# nixpkgs already packages vboot_reference's futility, so reuse it instead of
# building a second copy from coreboot's vboot submodule. Verified compatible
# with coreboot 26.06 vboot images (show/sign/GBB).
final: prev: {
  coreboot-utils = prev.coreboot-utils.overrideAttrs (old: {
    postBuild = (old.postBuild or "")
      + "\ninstall -Dm755 ${prev.futility}/bin/futility $out/bin/futility\n";
    passthru = (old.passthru or {}) // { futility = prev.futility; };
  });
}
