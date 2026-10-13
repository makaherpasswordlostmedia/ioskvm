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

#include "javacall_events.h"
#include "javacall_logging.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/time.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Event queue: bounded ring of malloc'd messages guarded by a pthread mutex
 * and a condition variable. Replaces the PSP kernel mailbox implementation.
 * Producers: UI thread (touch/keys), timer threads, socket/audio callbacks.
 * Consumer: the VM thread (javacall_event_receive).
 */
#define QUEUE_SIZE 64

typedef struct { int len; unsigned char* data; } ev_t;

static ev_t            queue[QUEUE_SIZE];
static int             q_head = 0, q_count = 0;
static pthread_mutex_t q_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  q_cond = PTHREAD_COND_INITIALIZER;

javacall_result javacall_event_receive(long timeTowaitInMillisec,
                                       /*OUT*/ unsigned char* binaryBuffer,
                                       /*IN*/  int binaryBufferMaxLen,
                                       /*OUT*/ int* outEventLen) {
    static int busy_count = 0;
    ev_t ev;

    /* The VM polls with timeout 0 in tight loops while Java threads are idle:
       force a short sleep every so often so the CPU (and battery) can rest. */
    if (busy_count > 40 && timeTowaitInMillisec == 0) {
        timeTowaitInMillisec = 30;
        busy_count = 0;
    }

    pthread_mutex_lock(&q_lock);
    if (q_count == 0) {
        if (timeTowaitInMillisec < 0) {
            busy_count = 0;
            while (q_count == 0) pthread_cond_wait(&q_cond, &q_lock);
        } else if (timeTowaitInMillisec == 0) {
            busy_count++;
        } else {
            struct timeval  tv;
            struct timespec ts;
            busy_count = 0;
            gettimeofday(&tv, NULL);
            ts.tv_sec  = tv.tv_sec + timeTowaitInMillisec / 1000;
            ts.tv_nsec = (tv.tv_usec + (timeTowaitInMillisec % 1000) * 1000L) * 1000L;
            if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
            while (q_count == 0) {
                if (pthread_cond_timedwait(&q_cond, &q_lock, &ts) == ETIMEDOUT) break;
            }
        }
    }
    if (q_count == 0) {
        pthread_mutex_unlock(&q_lock);
        if (outEventLen) *outEventLen = 0;
        return JAVACALL_FAIL;
    }
    ev = queue[q_head];
    q_head = (q_head + 1) % QUEUE_SIZE;
    q_count--;
    pthread_mutex_unlock(&q_lock);

    if (binaryBufferMaxLen < ev.len) {
        free(ev.data);
        if (outEventLen) *outEventLen = 0;
        return JAVACALL_OUT_OF_MEMORY;
    }
    memcpy(binaryBuffer, ev.data, ev.len);
    if (outEventLen) *outEventLen = ev.len;
    free(ev.data);
    return JAVACALL_OK;
}

javacall_result javacall_event_send(unsigned char* binaryBuffer, int binaryBufferLen) {
    unsigned char* p = (unsigned char*)malloc(binaryBufferLen > 0 ? binaryBufferLen : 1);
    if (!p) return JAVACALL_FAIL;
    memcpy(p, binaryBuffer, binaryBufferLen);

    pthread_mutex_lock(&q_lock);
    if (q_count >= QUEUE_SIZE) {
        pthread_mutex_unlock(&q_lock);
        free(p);
        javacall_printf("javacall_event_send: queue full, event discarded\n");
        return JAVACALL_FAIL;
    }
    queue[(q_head + q_count) % QUEUE_SIZE].len  = binaryBufferLen;
    queue[(q_head + q_count) % QUEUE_SIZE].data = p;
    q_count++;
    pthread_cond_signal(&q_cond);
    pthread_mutex_unlock(&q_lock);
    return JAVACALL_OK;
}

javacall_result javacall_events_init(void) {
    pthread_mutex_lock(&q_lock);
    q_head = q_count = 0;
    pthread_mutex_unlock(&q_lock);
    return JAVACALL_OK;
}

javacall_result javacall_events_finalize(void) {
    pthread_mutex_lock(&q_lock);
    while (q_count > 0) {
        free(queue[q_head].data);
        q_head = (q_head + 1) % QUEUE_SIZE;
        q_count--;
    }
    pthread_mutex_unlock(&q_lock);
    return JAVACALL_OK;
}

#ifdef __cplusplus
}
#endif
