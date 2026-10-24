# SPDX-License-Identifier: GPL-2.0-only

romstage-y += dimmSpd.c

ramstage-y += northbridge.c
ramstage-y += iommu.c
ramstage-y += acpi_tables.c
ramstage-$(CONFIG_PSP_FTPM) += psp.c

romstage-y += state_machine.c
ramstage-y += state_machine.c
