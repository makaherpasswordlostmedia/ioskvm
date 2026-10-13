#include "psp_shim.h"
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/time.h>

#define MAX_THREADS 128
#define MAX_ALARMS  64

typedef struct {
    int used;
    SceKernelThreadEntry entry;
    int stackSize;
} thr_slot;

static thr_slot thr[MAX_THREADS];
static pthread_mutex_t thr_lock = PTHREAD_MUTEX_INITIALIZER;

typedef struct { SceKernelThreadEntry entry; SceSize argSize; unsigned char* args; int id; } start_pkt;

static void* thread_main(void* p) {
    start_pkt* pk = (start_pkt*)p;
    pk->entry(pk->argSize, pk->args);
    pthread_mutex_lock(&thr_lock);
    thr[pk->id].used = 0;
    pthread_mutex_unlock(&thr_lock);
    free(pk->args);
    free(pk);
    return NULL;
}

SceUID sceKernelCreateThread(const char* name, SceKernelThreadEntry entry,
                             int prio, int stackSize, unsigned attr, void* opt) {
    int i;
    (void)name; (void)prio; (void)attr; (void)opt;
    pthread_mutex_lock(&thr_lock);
    for (i = 0; i < MAX_THREADS; i++) {
        if (!thr[i].used) {
            thr[i].used = 1; thr[i].entry = entry; thr[i].stackSize = stackSize;
            pthread_mutex_unlock(&thr_lock);
            return i;
        }
    }
    pthread_mutex_unlock(&thr_lock);
    return -1;
}

int sceKernelStartThread(SceUID id, SceSize argSize, void* argp) {
    pthread_t t;
    pthread_attr_t at;
    start_pkt* pk;
    size_t stack;
    if (id < 0 || id >= MAX_THREADS || !thr[id].used) return -1;
    pk = (start_pkt*)malloc(sizeof(start_pkt));
    if (!pk) return -1;
    pk->entry = thr[id].entry; pk->argSize = argSize; pk->id = id;
    pk->args = (unsigned char*)malloc(argSize ? argSize : 1);
    if (argSize && argp) memcpy(pk->args, argp, argSize);
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    /* iOS secondary threads default to 512 KB; PSP code asked for 8-16 KB, give a sane floor */
    stack = thr[id].stackSize < 128 * 1024 ? 128 * 1024 : (size_t)thr[id].stackSize;
    pthread_attr_setstacksize(&at, stack);
    if (pthread_create(&t, &at, thread_main, pk) != 0) {
        free(pk->args); free(pk);
        pthread_attr_destroy(&at);
        thr[id].used = 0;
        return -1;
    }
    pthread_attr_destroy(&at);
    return 0;
}

int sceKernelExitDeleteThread(int status) {
    (void)status;
    /* The PSP code calls this as the last statement of the thread function and
     * then returns anyway, so returning from here is equivalent and avoids
     * leaking the start packet that thread_main frees after entry() returns. */
    return 0;
}

int sceKernelDelayThread(SceUInt usec) {
    usleep(usec);
    return 0;
}

/* ---- alarms ---- */
typedef struct {
    int used;
    volatile int cancelled;
    SceUInt usec;
    SceKernelAlarmHandler handler;
    void* common;
} alarm_slot;

static alarm_slot alarms[MAX_ALARMS];
static pthread_mutex_t alarm_lock = PTHREAD_MUTEX_INITIALIZER;

static void* alarm_main(void* p) {
    int id = (int)(long)p;
    alarm_slot* a = &alarms[id];
    SceUInt next = a->usec;
    while (next && !a->cancelled) {
        usleep(next);
        if (a->cancelled) break;
        next = a->handler(a->common);   /* returns re-arm interval or 0 */
    }
    pthread_mutex_lock(&alarm_lock);
    a->used = 0;
    pthread_mutex_unlock(&alarm_lock);
    return NULL;
}

SceUID sceKernelSetAlarm(SceUInt usec, SceKernelAlarmHandler handler, void* common) {
    int i;
    pthread_t t;
    pthread_attr_t at;
    pthread_mutex_lock(&alarm_lock);
    for (i = 0; i < MAX_ALARMS; i++) if (!alarms[i].used) break;
    if (i == MAX_ALARMS) { pthread_mutex_unlock(&alarm_lock); return -1; }
    alarms[i].used = 1; alarms[i].cancelled = 0;
    alarms[i].usec = usec; alarms[i].handler = handler; alarms[i].common = common;
    pthread_mutex_unlock(&alarm_lock);
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&t, &at, alarm_main, (void*)(long)i) != 0) {
        alarms[i].used = 0;
        pthread_attr_destroy(&at);
        return -1;
    }
    pthread_attr_destroy(&at);
    return i;
}

int sceKernelCancelAlarm(SceUID id) {
    if (id >= 0 && id < MAX_ALARMS) alarms[id].cancelled = 1;
    return 0;
}
