#ifndef PSPKVM_LCD_IOS_H
#define PSPKVM_LCD_IOS_H
/* Interface between javacall lcd.c (VM thread) and the UIKit host (main thread). */
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const uint32_t* pixels;   /* BGRA8888 premultiplied-first, little endian (0xAARRGGBB), alpha = 0xFF */
    int      width, height;
    unsigned frame;           /* increments on every flush */
} ios_lcd_frame;

/* Host sets the initial Java canvas size BEFORE starting the VM (default 240x320). */
void pspkvm_ios_set_screen_size(int w, int h);

/* Returns 1 and fills *f if a new frame has been flushed since the last call, else 0.
 * The pixel pointer stays valid for at least two further flushes (triple buffering). */
int  pspkvm_ios_lcd_get_frame(ios_lcd_frame* f);

/* Host callback, invoked on the VM thread when the Java screen size changes.
 * Implemented by the host (ios/KVMBridge.m). */
extern void pspkvm_ios_screen_resized(int w, int h);

/* Video overlay API used by the AVFoundation media backend. */
void pspkvm_ios_set_video_mask(int on, unsigned short color565);
void pspkvm_ios_set_video_overlay(const void* owner, const uint32_t* px, int x, int y, int w, int h);
void pspkvm_ios_lcd_refresh(void);

#ifdef __cplusplus
}
#endif
#endif
