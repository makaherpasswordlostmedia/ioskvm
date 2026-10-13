/*
 *
 * Copyright  1990-2007 Sun Microsystems, Inc. All Rights Reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version
 * 2 only, as published by the Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License version 2 for more details (a copy is
 * included at /legal/license.txt).
 * 
 * You should have received a copy of the GNU General Public License
 * version 2 along with this work; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 * 
 * Please contact Sun Microsystems, Inc., 4150 Network Circle, Santa
 * Clara, CA 95054 or visit www.sun.com if you need additional
 * information or have any questions.
 */

#include "javacall_lcd.h"
#include "javacall_properties.h"
#include "javacall_devemu.h"
#include "lcd_ios.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

extern const unsigned short DukeTango[];   /* imageRom.c: 480x272 RGB565 splash, 2-short header */
extern void javanotify_rotation(void);

/* Largest canvas we accept (width*height*2 bytes for the RGB565 back buffer). */
#define MAX_DIM 1024

static int vscr_w = 240;
static int vscr_h = 320;
static int resized = 0;

static javacall_pixel* scbuff = NULL;     /* what the VM draws into (RGB565) */
static int scbuff_w = 0, scbuff_h = 0;

/* triple-buffered BGRA shadow frames handed to the UI thread */
#define NBUF 3
static uint32_t* shadow[NBUF];
static int shadow_w = 0, shadow_h = 0;
static int shadow_write = 0;              /* buffer being written by the next flush  */
static int shadow_front = -1;             /* last completed buffer                    */
static unsigned frame_counter = 0, frame_taken = 0;
static pthread_mutex_t lcd_lock = PTHREAD_MUTEX_INITIALIZER;

static int _enable_lcd_flush = 1;

/* ---- native video overlay (MMAPI VideoControl, see jsr135_mmapi/multimedia.m) ----
 * The media thread publishes already-scaled BGRA frames; present() composites them
 * over the canvas, either everywhere or only where the canvas holds the mask colour
 * (javacall_media_set_video_alpha semantics). */
#define MAX_OVERLAYS 4
typedef struct { const void* owner; const uint32_t* px; int x, y, w, h; } vid_overlay;
static vid_overlay ovl[MAX_OVERLAYS];
static pthread_mutex_t ovl_lock = PTHREAD_MUTEX_INITIALIZER;
static int mask_on = 0;
static unsigned short mask565 = 0;

void pspkvm_ios_set_video_mask(int on, unsigned short color565) {
    pthread_mutex_lock(&ovl_lock);
    mask_on = on; mask565 = color565;
    pthread_mutex_unlock(&ovl_lock);
}

/* px == NULL removes the overlay owned by `owner`. The buffer must stay valid until replaced/removed. */
void pspkvm_ios_set_video_overlay(const void* owner, const uint32_t* px, int x, int y, int w, int h) {
    int i, free_i = -1;
    pthread_mutex_lock(&ovl_lock);
    for (i = 0; i < MAX_OVERLAYS; i++) {
        if (ovl[i].owner == owner && ovl[i].px != NULL) { free_i = i; break; }
        if (free_i < 0 && ovl[i].px == NULL) free_i = i;
    }
    if (free_i >= 0) {
        ovl[free_i].owner = owner; ovl[free_i].px = px;
        ovl[free_i].x = x; ovl[free_i].y = y; ovl[free_i].w = w; ovl[free_i].h = h;
    }
    pthread_mutex_unlock(&ovl_lock);
}

static void compose_overlays(const javacall_pixel* src, uint32_t* dst, int ystart, int yend, int cw) {
    int i, y, x;
    pthread_mutex_lock(&ovl_lock);
    for (i = 0; i < MAX_OVERLAYS; i++) {
        const vid_overlay* o = &ovl[i];
        int y0, y1, x0, x1;
        if (!o->px) continue;
        y0 = o->y < ystart ? ystart : o->y;
        y1 = (o->y + o->h) > yend ? yend : (o->y + o->h);
        x0 = o->x < 0 ? 0 : o->x;
        x1 = (o->x + o->w) > cw ? cw : (o->x + o->w);
        for (y = y0; y < y1; y++) {
            const uint32_t* vp = o->px + (size_t)(y - o->y) * o->w - o->x;
            uint32_t* pd = dst + (size_t)y * cw;
            const unsigned short* ps = (const unsigned short*)src + (size_t)y * cw;
            if (mask_on) {
                for (x = x0; x < x1; x++) if (ps[x] == mask565) pd[x] = vp[x];
            } else {
                for (x = x0; x < x1; x++) pd[x] = vp[x];
            }
        }
    }
    pthread_mutex_unlock(&ovl_lock);
}

static void present(const javacall_pixel* src, int ystart, int yend);
/* Re-composite the last canvas after the video frame changed (called from the media thread). */
void pspkvm_ios_lcd_refresh(void) {
    if (scbuff) present(scbuff, 0, vscr_h);
}

/* RGB565 -> 0xFFRRGGBB lookup for the two 5/6 bit channels would cost cache on A4;
 * plain shifts with bit replication are cheap enough and exact. */
static inline uint32_t px565(unsigned short c) {
    uint32_t r = (c >> 11) & 0x1F, g = (c >> 5) & 0x3F, b = c & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);
    return 0xFF000000u | (r << 16) | (g << 8) | b;
}

static int alloc_buffers(void) {
    int i;
    size_t n = (size_t)vscr_w * vscr_h;
    if (scbuff && scbuff_w == vscr_w && scbuff_h == vscr_h) return 1;

    pthread_mutex_lock(&lcd_lock);
    free(scbuff);
    scbuff = (javacall_pixel*)calloc(n, sizeof(javacall_pixel));
    for (i = 0; i < NBUF; i++) {
        free(shadow[i]);
        shadow[i] = (uint32_t*)calloc(n, sizeof(uint32_t));
    }
    shadow_w = scbuff_w = vscr_w;
    shadow_h = scbuff_h = vscr_h;
    shadow_write = 0; shadow_front = -1;
    pthread_mutex_unlock(&lcd_lock);
    return scbuff && shadow[0] && shadow[1] && shadow[2];
}

void pspkvm_ios_set_screen_size(int w, int h) {
    if (w >= 16 && h >= 16 && w <= MAX_DIM && h <= MAX_DIM) {
        vscr_w = w; vscr_h = h;
    }
}

int pspkvm_ios_lcd_get_frame(ios_lcd_frame* f) {
    int ok = 0;
    pthread_mutex_lock(&lcd_lock);
    if (shadow_front >= 0 && frame_counter != frame_taken) {
        f->pixels = shadow[shadow_front];
        f->width  = shadow_w;
        f->height = shadow_h;
        f->frame  = frame_counter;
        frame_taken = frame_counter;
        ok = 1;
    }
    pthread_mutex_unlock(&lcd_lock);
    return ok;
}

/* Convert rows [ystart,yend) of src (RGB565, vscr_w wide) into a new shadow frame. */
static void present(const javacall_pixel* src, int ystart, int yend) {
    int x, y, prev, w, h;
    uint32_t* dst;
    if (!_enable_lcd_flush || !src || !shadow[0]) return;

    w = shadow_w; h = shadow_h;
    if (ystart < 0) ystart = 0;
    if (yend > h) yend = h;
    if (ystart >= yend) return;

    pthread_mutex_lock(&lcd_lock);
    /* start from the previous frame so that partial flushes keep the rest of the picture */
    prev = shadow_front;
    dst  = shadow[shadow_write];
    if (prev >= 0 && prev != shadow_write) {
        if (ystart > 0)  memcpy(dst, shadow[prev], (size_t)ystart * w * 4);
        if (yend < h)    memcpy(dst + (size_t)yend * w, shadow[prev] + (size_t)yend * w, (size_t)(h - yend) * w * 4);
    }
    pthread_mutex_unlock(&lcd_lock);

    for (y = ystart; y < yend; y++) {
        const unsigned short* ps = (const unsigned short*)src + (size_t)y * w;
        uint32_t* pd = dst + (size_t)y * w;
        for (x = 0; x < w; x++) pd[x] = px565(ps[x]);
    }
    compose_overlays(src, dst, ystart, yend, w);

    pthread_mutex_lock(&lcd_lock);
    shadow_front = shadow_write;
    shadow_write = (shadow_write + 1) % NBUF;
    frame_counter++;
    pthread_mutex_unlock(&lcd_lock);
}

javacall_result javacall_lcd_init(void) {
    return alloc_buffers() ? JAVACALL_OK : JAVACALL_FAIL;
}

javacall_result javacall_lcd_finalize(void) {
    return JAVACALL_OK;   /* buffers are kept for the process lifetime */
}

javacall_pixel* javacall_lcd_get_screen(javacall_lcd_screen_type screenType,
                                        int* screenWidth,
                                        int* screenHeight,
                                        javacall_lcd_color_encoding_type* colorEncoding) {
    if (resized || !scbuff) {
        javacall_lcd_finalize();
        javacall_lcd_init();
        resized = 0;
    }
    *screenWidth   = vscr_w;
    *screenHeight  = vscr_h;
    *colorEncoding = JAVACALL_LCD_COLOR_RGB565;
    return scbuff;
}

javacall_result javacall_lcd_flush(void) {
    return javacall_lcd_flush_partial(0, vscr_h);
}

javacall_result javacall_lcd_set_full_screen_mode(javacall_bool useFullScreen) {
    return JAVACALL_OK;
}

javacall_result javacall_lcd_flush_partial(int ystart, int yend) {
    present(scbuff, ystart, yend);
    return JAVACALL_OK;
}

javacall_bool javacall_lcd_direct_flush(javacall_pixel* buf, int h) {
    if ((unsigned long)buf & 0x03) {
        return JAVACALL_FALSE;
    }
    if (_enable_lcd_flush && buf) {
        present(buf, 0, h);
        return JAVACALL_TRUE;
    }
    return JAVACALL_FALSE;
}

javacall_bool javacall_lcd_reverse_orientation() { return JAVACALL_FALSE; }
javacall_bool javacall_lcd_get_reverse_orientation() { return JAVACALL_FALSE; }
int javacall_lcd_get_screen_width()  { return vscr_w; }
int javacall_lcd_get_screen_height() { return vscr_h; }

/* Called by the pspkvm settings UI / rotation logic. */
void javacall_set_new_screen_size(int w, int h) {
    if (w == vscr_w && h == vscr_h) return;
    if (w < 16 || h < 16 || w > MAX_DIM || h > MAX_DIM) return;
    javacall_printf("javacall_set_new_screen_size: %d, %d\n", w, h);
    vscr_w = w;
    vscr_h = h;
    resized = 1;
    javanotify_rotation();
    pspkvm_ios_screen_resized(w, h);
}

void javacall_lcd_enable_flush(int enable) {
    _enable_lcd_flush = enable;
}

void javacall_lcd_show_splash() {
    int x, y;
    const unsigned short* p = DukeTango + 2;
    int sw = DukeTango[0], sh = DukeTango[1];
    int ox, oy;
    if (!alloc_buffers()) return;
    memset(scbuff, 0, (size_t)vscr_w * vscr_h * sizeof(javacall_pixel));
    ox = (vscr_w - sw) / 2; oy = (vscr_h - sh) / 2;
    for (y = 0; y < sh; y++) {
        int dy = y + oy;
        if (dy < 0 || dy >= vscr_h) continue;
        for (x = 0; x < sw; x++) {
            int dx = x + ox;
            if (dx < 0 || dx >= vscr_w) continue;
            scbuff[dx + dy * vscr_w] = p[x + y * sw];
        }
    }
    javacall_lcd_flush();
}

#ifdef __cplusplus
}
#endif
