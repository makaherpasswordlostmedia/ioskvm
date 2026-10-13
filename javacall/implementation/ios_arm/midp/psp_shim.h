#ifndef PSP_SHIM_H
#define PSP_SHIM_H
/*
 * Tiny pthread-backed emulation of the handful of PSP kernel thread/alarm
 * calls that the stock socket/network code uses, so that code can stay
 * structurally identical to the PSP port.
 */
#ifdef __cplusplus
extern "C" {
#endif

typedef int          SceUID;
typedef unsigned int SceSize;
typedef unsigned int SceUInt;

#define PSP_THREAD_ATTR_USER 0x80000000

typedef int (*SceKernelThreadEntry)(SceSize args, void* argp);
typedef SceUInt (*SceKernelAlarmHandler)(void* common);

SceUID sceKernelCreateThread(const char* name, SceKernelThreadEntry entry,
                             int initPriority, int stackSize, unsigned attr, void* opt);
int    sceKernelStartThread(SceUID id, SceSize argSize, void* argp);
int    sceKernelExitDeleteThread(int status);
int    sceKernelDelayThread(SceUInt usec);

SceUID sceKernelSetAlarm(SceUInt usec, SceKernelAlarmHandler handler, void* common);
int    sceKernelCancelAlarm(SceUID id);

#ifdef __cplusplus
}
#endif
#endif
