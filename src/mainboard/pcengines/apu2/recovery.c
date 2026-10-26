/* SPDX-License-Identifier: GPL-2.0-only */

#include <bootmode.h>
#include <console/console.h>
#include <console/uart.h>
#include <gpio.h>
#include <timer.h>

#include "gpio_ftns.h"

#define RECOVERY_TIMEOUT_MS 1000

/*
 * S1 (MODESW#) is active-low: pressing it shorts the net to GND, while R125
 * is the external 10k pull-up to V3. It has no hardware latch, so the button
 * must be held through romstage and memory init.
 *
 * APU2/APU3/APU4 route MODESW# to GPIO_32; APU5 uses GPIO_22.
 */
static int recovery_button_pressed(void)
{
#if CONFIG(BOARD_PCENGINES_APU5)
	return !gpio_get(GPIO_22);
#else
	return !gpio_get(GPIO_32);
#endif
}

int get_recovery_mode_switch(void)
{
#if CONFIG(CONSOLE_SERIAL)
	struct stopwatch sw;
#endif

	if (recovery_button_pressed()) {
		printk(BIOS_INFO, "Recovery mode requested by S1 button.\n");
		return 1;
	}

#if CONFIG(CONSOLE_SERIAL)
	if (!uart_platform_base(CONFIG_UART_FOR_CONSOLE))
		return 0;

	/*
	 * Waiting up to one second is the cost of a reliable manual trigger;
	 * it only applies when a serial console is configured.
	 */
	printk(BIOS_INFO,
	       "Press 'r' or hold the S1 recovery button within %d ms "
	       "for recovery...\n",
	       RECOVERY_TIMEOUT_MS);

	stopwatch_init_msecs_expire(&sw, RECOVERY_TIMEOUT_MS);
	while (!stopwatch_expired(&sw)) {
		unsigned char c;

		if (recovery_button_pressed()) {
			printk(BIOS_INFO,
			       "Recovery mode requested by S1 button.\n");
			return 1;
		}

		c = uart_rx_byte(CONFIG_UART_FOR_CONSOLE);
		if (c == 'r' || c == 'R') {
			printk(BIOS_INFO,
			       "Recovery mode requested over UART.\n");
			return 1;
		}
	}
#endif

	return 0;
}
