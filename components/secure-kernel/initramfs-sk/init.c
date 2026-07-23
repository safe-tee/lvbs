/* Minimal init for Plane 1 secure kernel — no libc dependency.
 * Uses raw syscalls so it can be compiled with -nostdlib.
 * Keeps the kernel running without requiring a root filesystem.
 */

static void sys_write(int fd, const char *buf, unsigned long len)
{
	__asm__ volatile (
		"syscall"
		: : "a"(1), "D"(fd), "S"(buf), "d"(len)
		: "rcx", "r11", "memory"
	);
}

static void sys_pause(void)
{
	__asm__ volatile (
		"syscall"
		: : "a"(34)
		: "rcx", "r11", "memory"
	);
}

void _start(void)
{
	const char msg[] = "Plane-1 secure kernel ready\n";
	sys_write(1, msg, sizeof(msg) - 1);

	for (;;)
		sys_pause();
}
