#include <stdint.h>

extern char payload_start[];

#ifndef PAYLOAD_ENTRY_OFFSET
#define PAYLOAD_ENTRY_OFFSET 0
#endif

#define STR_IMPL(x) #x
#define STR(x) STR_IMPL(x)

__asm__(
    ".section .note.Xen,\"a\"\n"
    ".align 4\n"
    ".long 4\n"
    ".long 4\n"
    ".long 18\n"
    ".asciz \"Xen\"\n"
    ".align 4\n"
    ".long pvh_entry\n"
    ".previous\n");

__attribute__((naked, noreturn))
void pvh_entry(void)
{
    __asm__ volatile(
        "cld\n\t"
        "xorq %%rbp, %%rbp\n\t"
        "leaq payload_start(%%rip), %%rax\n\t"
    "addq $" STR(PAYLOAD_ENTRY_OFFSET) ", %%rax\n\t"
        "jmp *%%rax\n\t"
        :
        :
        : "rax");
}
