#import "KVMLog.h"
#import <UIKit/UIKit.h>
#include <execinfo.h>
#include <signal.h>
#include <string.h>
#include <sys/ucontext.h>
#include <mach-o/dyld.h>
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
static void wstr(const char* s) { write(gLogFd, s, strlen(s)); }
static void whex(const char* label, unsigned long v) {
    char b[32]; int n = 0;
    b[n++] = '0'; b[n++] = 'x';
    for (int sh = (int)sizeof(unsigned long) * 8 - 4; sh >= 0; sh -= 4) b[n++] = "0123456789abcdef"[(v >> sh) & 0xf];
    b[n++] = ' ';
    wstr(label); write(gLogFd, b, n);
}

static void sigHandler(int sig, siginfo_t* si, void* ctx) {
    if (gLogFd >= 0) {
        wstr("\n!!!! FATAL SIGNAL, native backtrace follows:\n");
        whex("signal=", (unsigned long)sig);
        whex("code=", (unsigned long)si->si_code);
        whex("fault_addr=", (unsigned long)si->si_addr);
        wstr("\n");
#if defined(__arm__)
        ucontext_t* uc = (ucontext_t*)ctx;
        if (uc && uc->uc_mcontext) {
            _STRUCT_ARM_THREAD_STATE* r = &uc->uc_mcontext->__ss;
            whex("pc=", r->__pc); whex("lr=", r->__lr); whex("sp=", r->__sp); whex("cpsr=", r->__cpsr); wstr("\n");
            static const char* rn[13] = {"r0=","r1=","r2=","r3=","r4=","r5=","r6=","r7=","r8=","r9=","r10=","r11=","r12="};
            for (int i = 0; i < 13; i++) whex(rn[i], r->__r[i]);
            wstr("\n");
        }
#endif
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
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = sigHandler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) sigaction(sigs[i], &sa, NULL);

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
    KVMLogf("init", @"main image ASLR slide=0x%lx (subtract from crash addresses before nm/atos)",
            (unsigned long)_dyld_get_image_vmaddr_slide(0));

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
