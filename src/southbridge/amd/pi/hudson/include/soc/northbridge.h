/* SPDX-License-Identifier: GPL-2.0-only */

#ifndef AMD_HUDSON_NORTHBRIDGE_H
#define AMD_HUDSON_NORTHBRIDGE_H

#include <device/pci_def.h>
#include <types.h>

/* Platform Security Processor D8F0 */
#define PSP_FTPM_BAR			PCI_BASE_ADDRESS_2 /* BKDG: "BAR1" */
#define PSP_MAILBOX_BAR			PCI_BASE_ADDRESS_2 /* Not BAR3 as one would think */

#define PSP_BAR_ENABLES			0x48
#define  BAR0_EN			BIT(0) /* Bit to enable BAR0 access */
#define  BAR1_EN			BIT(2) /* Bit to enable BAR1 access */
#define  BAR2_EN			BIT(3) /* Bit to enable BAR2 access */
#define  BAR3_EN			BIT(4) /* Bit to enable BAR3 access */
#define  BAR_MSIX_EN			BIT(5) /* Bit to enable MSI-X BAR access */
#define  BAR3HIDE			BIT(12) /* Bit to hide BAR3 addr */
#define  BAR3LOCK			BIT(20) /* Bit to lock BAR3 addr */

#endif /* AMD_HUDSON_NORTHBRIDGE_H */
