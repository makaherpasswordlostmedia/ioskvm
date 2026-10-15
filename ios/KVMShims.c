/*
 * Shims for symbols the CLDC VM expects from its ARM assembly layer.
 *
 * The iOS build runs the portable C interpreter (ENABLE_C_INTERPRETER, no
 * generated assembly stubs), but the VM sources are still compiled with -DARM,
 * which makes them reference these two ARM-only symbols. Provide plain C
 * versions so the final link succeeds.
 */
#include <string.h>

/* Cached ROM constant pool pointer (set in ROM.cpp, only read by ARM asm). */
int *_rom_constant_pool_fast;

/* Zero 'length' bytes at 'start' (same contract as the inline C fallback). */
void fast_memclear(void *start, int length) {
    memset(start, 0, (size_t)length);
}
