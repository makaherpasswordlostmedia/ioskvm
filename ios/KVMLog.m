#import "KVMLog.h"
#import <UIKit/UIKit.h>
#include <execinfo.h>
#include <signal.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <unistd.h>

#define KVM_LOG_MAX_BYTES (2 * 1024 * 1024)   /* rotate at 2 MB so a chatty MIDlet can't fill the device */

static int  gLogFd  = -1;       // kvm.log
static int  gOrigErr = -1;      // the real stderr (Xcode / device console), saved before redirect
static NSString* gLogDir, *gLogPath, *gPrevPath;
static dispatch_queue_t gQ;
static off_t gSize;

static NSString* stamp(void) {
    struct timeval tv; gettimeofday(&tv, NULL);
    struct tm t; time_t s = tv.tv_sec; localtime_r(&s, &t);
    char b[40];
    snprintf(b, sizeof(b), "%02d-%02d %02d:%02d:%02d.%03d", t.tm_mon + 1, t.tm_mday,
             t.tm_hour, t.tm_min, t.tm_sec, (int)(tv.tv_usec / 1000));
    return [NSString stringWithUTF8String:b];
}

static void openLog(BOOL rotate) {
    if (gLogFd >= 0) { close(gLogFd); gLogFd = -1; }
    if (rotate) {
        NSFileManager* fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:gPrevPath error:nil];
        [fm moveItemAtPath:gLogPath toPath:gPrevPath error:nil];
    }
    gLogFd = open(gLogPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    gSize = 0;
}

// Serialised append: file + real stderr. Safe to call from any thread.
static void emit(NSString* line) {
    if (!gQ) return;
    dispatch_sync(gQ, ^{
        const char* c = line.UTF8String;
        size_t n = strlen(c);
        if (gLogFd >= 0) {
            if (gSize + (off_t)n > KVM_LOG_MAX_BYTES) {
                openLog(YES);
                static const char m[] = "---- log rotated (size limit) ----\n";
                if (gLogFd >= 0) { write(gLogFd, m, sizeof(m) - 1); }
            }
            if (gLogFd >= 0 && write(gLogFd, c, n) > 0) gSize += n;
        }
        if (gOrigErr >= 0) write(gOrigErr, c, n);
    });
}

void KVMLogf(const char* tag, NSString* fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString* msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    emit([NSString stringWithFormat:@"[%@] [%s] %@\n", stamp(), tag ?: "app", msg]);
}

NSString* KVMLogPath(void) { return gLogPath; }

// ---- capture stdout/stderr (Java System.out, javacall logging, NSLog, C printf) ----
static void* pipeReader(void* arg) {
    int rfd = (int)(intptr_t)arg;
    char buf[2048]; char line[4096]; size_t ll = 0;
    ssize_t n;
    while ((n = read(rfd, buf, sizeof(buf))) > 0) {
        for (ssize_t i = 0; i < n; i++) {
            char ch = buf[i];
            if (ch == '\n' || ll >= sizeof(line) - 1) {
                line[ll] = 0;
                @autoreleasepool { KVMLogf("vm", @"%s", line); }
                ll = 0;
                if (ch != '\n') line[ll++] = ch;
            } else line[ll++] = ch;
        }
    }
    return NULL;
}

static void captureStdio(void) {
    int fds[2];
    if (pipe(fds) != 0) return;
    gOrigErr = dup(STDERR_FILENO);
    dup2(fds[1], STDOUT_FILENO);
    dup2(fds[1], STDERR_FILENO);
    close(fds[1]);
    setvbuf(stdout, NULL, _IOLBF, 0);   // line-buffered so Java println shows up immediately
    setvbuf(stderr, NULL, _IONBF, 0);
    pthread_attr_t at; pthread_t t;
    pthread_attr_init(&at);
    pthread_attr_setstacksize(&at, 256 * 1024);
    pthread_create(&t, &at, pipeReader, (void*)(intptr_t)fds[0]);
    pthread_detach(t);
}

// ---- crash reporting (async-signal-safe: write() + backtrace_symbols_fd only) ----
static void sigHandler(int sig) {
    static const char hdr[] = "\n!!!! FATAL SIGNAL, native backtrace follows:\n";
    char num[16]; int len = 0; int v = sig;
    char tmp[8]; int tl = 0;
    do { tmp[tl++] = '0' + v % 10; v /= 10; } while (v);
    while (tl) num[len++] = tmp[--tl];
    if (gLogFd >= 0) {
        write(gLogFd, hdr, sizeof(hdr) - 1);
        write(gLogFd, "signal ", 7); write(gLogFd, num, len); write(gLogFd, "\n", 1);
        void* frames[64];
        int n = backtrace(frames, 64);
        backtrace_symbols_fd(frames, n, gLogFd);
        fsync(gLogFd);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void excHandler(NSException* e) {
    KVMLogf("crash", @"Uncaught ObjC exception %@: %@\n%@", e.name, e.reason,
            [e.callStackSymbols componentsJoinedByString:@"\n"]);
}

void KVMLogInit(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;

    gQ = dispatch_queue_create("pspkvm.log", DISPATCH_QUEUE_SERIAL);
    NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    gLogDir  = [[docs stringByAppendingPathComponent:@"pspkvm"] stringByAppendingPathComponent:@"logs"];
    gLogPath = [gLogDir stringByAppendingPathComponent:@"kvm.log"];
    gPrevPath = [gLogDir stringByAppendingPathComponent:@"kvm.prev.log"];
    [[NSFileManager defaultManager] createDirectoryAtPath:gLogDir withIntermediateDirectories:YES attributes:nil error:nil];
    openLog(YES);

    captureStdio();

    NSSetUncaughtExceptionHandler(excHandler);
    int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP };
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) signal(sigs[i], sigHandler);

    struct utsname u; uname(&u);
    NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
    UIDevice* d = [UIDevice currentDevice];
    KVMLogf("init", @"==== PSPKVM %@ (build %@) ====", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]);
    KVMLogf("init", @"device=%s iOS %@ screen=%.0fx%.0f@%.0fx", u.machine, d.systemVersion,
            [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height,
            [UIScreen mainScreen].scale);
    KVMLogf("init", @"RAM=%.0f MB cpus=%lu", [NSProcessInfo processInfo].physicalMemory / 1048576.0,
            (unsigned long)[NSProcessInfo processInfo].processorCount);
    KVMLogf("init", @"log file: %@", gLogPath);

    // App lifecycle / memory pressure
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    NSOperationQueue* mq = [NSOperationQueue mainQueue];
    [nc addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:mq
        usingBlock:^(NSNotification* n) { KVMLogf("app", @"MEMORY WARNING"); }];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:mq
        usingBlock:^(NSNotification* n) { KVMLogf("app", @"entered background"); }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:mq
        usingBlock:^(NSNotification* n) { KVMLogf("app", @"entering foreground"); }];
    [nc addObserverForName:UIApplicationWillTerminateNotification object:nil queue:mq
        usingBlock:^(NSNotification* n) { KVMLogf("app", @"will terminate"); }];
}
