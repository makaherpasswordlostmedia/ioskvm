#ifndef PSPCTRL_SHIM_H
#define PSPCTRL_SHIM_H
/* iOS shim: keeps the PSP button bitmask model so the stock keymap, the
 * KeymapSettingsForm and com.pspkvm.keypad.* Java classes work unchanged.
 * Buttons are fed by the UIKit host through pspkvm_ios_set_pad(). */
#ifdef __cplusplus
extern "C" {
#endif
#define PSP_CTRL_SELECT     0x000001
#define PSP_CTRL_START      0x000008
#define PSP_CTRL_UP         0x000010
#define PSP_CTRL_RIGHT      0x000020
#define PSP_CTRL_DOWN       0x000040
#define PSP_CTRL_LEFT       0x000080
#define PSP_CTRL_LTRIGGER   0x000100
#define PSP_CTRL_RTRIGGER   0x000200
#define PSP_CTRL_TRIANGLE   0x001000
#define PSP_CTRL_CIRCLE     0x002000
#define PSP_CTRL_CROSS      0x004000
#define PSP_CTRL_SQUARE     0x008000

/* Called from the UI thread. lx/ly: 0..255, 128 = centre. */
void pspkvm_ios_set_pad(unsigned int buttons, int lx, int ly);
void pspkvm_ios_set_button(unsigned int mask, int down);
#ifdef __cplusplus
}
#endif
#endif
