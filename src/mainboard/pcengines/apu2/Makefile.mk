# SPDX-License-Identifier: GPL-2.0-only

# The AMD AGESA include paths are added to CC_<stage> relative to the coreboot
# root. The external vboot library is built from 3rdparty/vboot, where those
# paths don't resolve, so GCC's -Werror=missing-include-dirs rejects them.
# This only affects this board's vboot builds; don't make that warning fatal.
CFLAGS_common += -Wno-missing-include-dirs

bootblock-y += bootblock.c

romstage-y += BiosCallOuts.c
romstage-y += OemCustomize.c
romstage-y += gpio_ftns.c
romstage-$(CONFIG_VBOOT) += recovery.c

ramstage-y += BiosCallOuts.c
ramstage-y += OemCustomize.c
ramstage-y += gpio_ftns.c

# Order of names in SPD_SOURCES is important!
SPD_SOURCES  = HYNIX-2G-1333
SPD_SOURCES += HYNIX-4G-1333-ECC

subdirs-y += variants/$(VARIANT_DIR)
