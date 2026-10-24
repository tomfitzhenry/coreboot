/* SPDX-License-Identifier: GPL-2.0-only */

#ifndef _PI_HUDSON_SOC_PCI_DEVS_H_
#define _PI_HUDSON_SOC_PCI_DEVS_H_

#include <amdblocks/pci_devs.h>
#include <device/pci_def.h>
#include <southbridge/amd/pi/hudson/pci_devs.h>

/* Platform Security Processor */
#define PSP_DEV			0x8
#define PSP_FUNC		0
#define PSP_DEVFN		PCI_DEVFN(PSP_DEV, PSP_FUNC)
#define SOC_PSP_DEV		_SOC_DEV(PSP_DEV, PSP_FUNC)

#endif /* _PI_HUDSON_SOC_PCI_DEVS_H_ */
