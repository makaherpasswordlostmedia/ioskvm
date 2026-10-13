#include <javacall_misc.h>

/* The PSP port used this to underclock/overclock the CPU. iOS has no such control. */
void javacall_misc_set_cpu_speed(int speed) {
    javacall_printf("javacall_misc_set_cpu_speed(%d) ignored on iOS\n", speed);
}
