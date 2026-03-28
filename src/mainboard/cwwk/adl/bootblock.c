/* SPDX-License-Identifier: GPL-2.0-or-later */

#include <bootblock_common.h>
#include <soc/gpio.h>
#include <superio/ite/common/ite.h>
#include <superio/ite/it8613e/it8613e.h>

#define UART_DEV PNP_DEV(0x2e, IT8613E_SP1)

void bootblock_mainboard_early_init(void)
{
#if CONFIG(INTEL_LPSS_UART_FOR_CONSOLE)
	/*
	 * Route UART0 to the debug header in bootblock so early console is
	 * available as soon as console_init() runs.
	 */
	static const struct pad_config early_uart_gpio_table[] = {
		PAD_CFG_NF(GPP_H10, NONE, DEEP, NF2), /* UART0_RXD */
		PAD_CFG_NF(GPP_H11, NONE, DEEP, NF2), /* UART0_TXD */
	};

	gpio_configure_pads(early_uart_gpio_table, ARRAY_SIZE(early_uart_gpio_table));
#endif

#if CONFIG(DRIVERS_UART_8250IO)
	ite_enable_serial(UART_DEV, CONFIG_TTYS0_BASE);
#endif
}
