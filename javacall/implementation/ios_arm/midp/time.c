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

#include "javacall_time.h"
#include <pthread.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Timers: one detached pthread per slot sleeping on a condition variable with
 * an absolute deadline (replaces sceKernelSetAlarm). Callbacks are invoked on
 * the timer thread, exactly like the PSP alarm handler (which runs in an
 * interrupt-like context) - the VM callbacks only post events.
 */
#define MAX_TIMERS 8

typedef struct {
    int             used;
    int             cancelled;
    unsigned int    generation;
    javacall_bool   cyclic;
    int             periodMs;
    javacall_callback_func cbFunc;
    pthread_mutex_t lock;
    pthread_cond_t  cond;
} timer_slot;

static timer_slot timers[MAX_TIMERS];
static pthread_mutex_t slots_lock = PTHREAD_MUTEX_INITIALIZER;
static int slots_inited = 0;

typedef struct { int slot; unsigned int gen; } thread_arg;

static void init_slots(void) {
    int i;
    if (slots_inited) return;
    for (i = 0; i < MAX_TIMERS; i++) {
        pthread_mutex_init(&timers[i].lock, NULL);
        pthread_cond_init(&timers[i].cond, NULL);
    }
    slots_inited = 1;
}

static void* timer_thread(void* p) {
    thread_arg a = *(thread_arg*)p;
    timer_slot* t = &timers[a.slot];
    free(p);

    pthread_mutex_lock(&t->lock);
    for (;;) {
        struct timeval  tv;
        struct timespec ts;
        int rc = 0;
        gettimeofday(&tv, NULL);
        ts.tv_sec  = tv.tv_sec + t->periodMs / 1000;
        ts.tv_nsec = (tv.tv_usec + (long)(t->periodMs % 1000) * 1000L) * 1000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }

        while (!t->cancelled && t->generation == a.gen && rc != ETIMEDOUT) {
            rc = pthread_cond_timedwait(&t->cond, &t->lock, &ts);
        }
        if (t->cancelled || t->generation != a.gen) break;

        {
            javacall_callback_func f = t->cbFunc;
            javacall_bool cyc = t->cyclic;
            pthread_mutex_unlock(&t->lock);
            if (f) f((javacall_handle)(long)a.slot);
            pthread_mutex_lock(&t->lock);
            if (!cyc) break;
        }
    }
    pthread_mutex_unlock(&t->lock);
    return NULL;
}

javacall_result javacall_time_initialize_timer(
                    int                      wakeupInMilliSecondsFromNow,
                    javacall_bool            cyclic,
                    javacall_callback_func   func,
                    /*OUT*/ javacall_handle *handle) {
    int i, slot = -1;
    pthread_t th;
    thread_arg* arg;

    if (wakeupInMilliSecondsFromNow <= 0) {
        javacall_print("javacall_time_initialize_timer invalid param!\n");
        return JAVACALL_FAIL;
    }
    pthread_mutex_lock(&slots_lock);
    init_slots();
    for (i = 0; i < MAX_TIMERS; i++) {
        if (!timers[i].used) { timers[i].used = 1; slot = i; break; }
    }
    pthread_mutex_unlock(&slots_lock);
    if (slot < 0) {
        javacall_print("[Javacall Error]No available timer!\n");
        return JAVACALL_FAIL;
    }

    pthread_mutex_lock(&timers[slot].lock);
    timers[slot].cancelled = 0;
    timers[slot].generation++;
    timers[slot].cyclic   = cyclic;
    timers[slot].periodMs = wakeupInMilliSecondsFromNow;
    timers[slot].cbFunc   = func;
    pthread_mutex_unlock(&timers[slot].lock);

    arg = (thread_arg*)malloc(sizeof(thread_arg));
    arg->slot = slot;
    arg->gen  = timers[slot].generation;
    if (pthread_create(&th, NULL, timer_thread, arg) != 0) {
        free(arg);
        timers[slot].used = 0;
        javacall_print("[Javacall Error]pthread_create failed for timer\n");
        return JAVACALL_FAIL;
    }
    pthread_detach(th);
    *handle = (javacall_handle)(long)slot;
    return JAVACALL_OK;
}

javacall_result javacall_time_finalize_timer(javacall_handle handle) {
    int i = (int)(long)handle;
    if (i < 0 || i >= MAX_TIMERS || !slots_inited) {
        javacall_print("javacall_time_finalize_timer try to finalize invalid timer\n");
        return JAVACALL_FAIL;
    }
    pthread_mutex_lock(&timers[i].lock);
    timers[i].cancelled = 1;
    timers[i].generation++;
    pthread_cond_broadcast(&timers[i].cond);
    pthread_mutex_unlock(&timers[i].lock);
    timers[i].used = 0;
    return JAVACALL_OK;
}

char* javacall_time_get_local_timezone(void) {
    static char tz[16];
    time_t now = time(NULL);
    struct tm lt;
    long off;
    localtime_r(&now, &lt);
    off = lt.tm_gmtoff;                       /* seconds east of UTC, DST included */
    snprintf(tz, sizeof(tz), "GMT%c%02ld:%02ld",
             off < 0 ? '-' : '+', (off < 0 ? -off : off) / 3600, ((off < 0 ? -off : off) % 3600) / 60);
    return tz;
}

/* java.lang.System.currentTimeMillis() is UTC based on MIDP; the VM adds the
 * timezone itself from javacall_time_get_local_timezone(). */
javacall_int64 javacall_time_get_milliseconds_since_1970(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (javacall_int64)tv.tv_sec * 1000LL + tv.tv_usec / 1000;
}

javacall_time_seconds javacall_time_get_seconds_since_1970(void) {
    return (javacall_time_seconds)(time(NULL) & 0xFFFFFFFF);
}

javacall_time_milliseconds javacall_time_get_clock_milliseconds(void) {
#ifdef __APPLE__
    static mach_timebase_info_data_t tb;
    uint64_t t = mach_absolute_time();
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (javacall_time_milliseconds)((t * tb.numer / tb.denom) / 1000000ULL);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (javacall_time_milliseconds)(ts.tv_sec * 1000LL + ts.tv_nsec / 1000000);
#endif
}

#ifdef __cplusplus
}
#endif
