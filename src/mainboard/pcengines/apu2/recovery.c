/* SPDX-License-Identifier: GPL-2.0-only */

#include <bootmode.h>
#include <console/console.h>
#include <console/uart.h>
#include <timer.h>

#define RECOVERY_TIMEOUT_MS 1000

#if CONFIG(CONSOLE_SERIAL)
int get_recovery_mode_switch(void)
{
	struct stopwatch sw;

	if (!uart_platform_base(CONFIG_UART_FOR_CONSOLE))
		return 0;

	/*
	 * Waiting up to one second is the cost of a reliable manual trigger;
	 * it only applies when a serial console is configured.
	 */
	printk(BIOS_INFO, "Press 'r' within %d ms for recovery...\n",
	       RECOVERY_TIMEOUT_MS);

	stopwatch_init_msecs_expire(&sw, RECOVERY_TIMEOUT_MS);
	while (!stopwatch_expired(&sw)) {
		unsigned char c = uart_rx_byte(CONFIG_UART_FOR_CONSOLE);
		if (c == 'r' || c == 'R') {
			printk(BIOS_INFO, "Recovery mode requested over UART.\n");
			return 1;
		}
	}

	return 0;
}
#else
int get_recovery_mode_switch(void)
{
	return 0;
}
#endif
