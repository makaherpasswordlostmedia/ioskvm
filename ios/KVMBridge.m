// Glue between UIKit and the phoneME/javacall port (ios_arm layer).
#import "KVMBridge.h"
#import "KVMLog.h"
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/stat.h>
#include "lcd_ios.h"

// javacall / phoneME entry points
extern int  JavaTask(void);
extern void javanotify_start(void);
extern void javanotify_pause(void);
extern void javanotify_resume(void);
extern void javacall_logging_channel(int channel);
extern void javacall_lcd_show_splash(void);
#define JAVACALL_LOG_CHANNEL_STDOUT 4   /* javacall_logging.h */

NSString* const KVMScreenResizedNotification = @"KVMScreenResized";

// ---- hooks the javacall layer expects the host to provide ----
void pspkvm_ios_log(const char* s) { fputs(s, stderr); }

const char* pspkvm_ios_locale(void) {
    static char buf[8];
    NSLocale* l = [NSLocale currentLocale];
    NSString* lang = [l objectForKey:NSLocaleLanguageCode] ?: @"en";
    NSString* cc   = [l objectForKey:NSLocaleCountryCode]  ?: @"US";
    snprintf(buf, sizeof(buf), "%.2s-%.2s", lang.UTF8String, cc.UTF8String);
    return buf;
}

void pspkvm_ios_screen_resized(int w, int h) {
    KVMLOG("lcd", @"canvas resized to %dx%d", w, h);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:KVMScreenResizedNotification
            object:nil userInfo:@{@"w":@(w), @"h":@(h)}];
    });
}

// ---- sandbox preparation ----
static NSString* const kBundleMarker = @".kvm_bundle_version";

static void copyTree(NSString* from, NSString* to) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSError* err = nil;
    [fm removeItemAtPath:to error:nil];
    if ([fm copyItemAtPath:from toPath:to error:&err])
        KVMLOG("sandbox", @"copied %@ -> %@", from.lastPathComponent, to);
    else
        KVMLOG("sandbox", @"ERROR copying %@ -> %@: %@", from, to, err.localizedDescription);
}

static NSString* prepareSandbox(void) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString* root = [docs stringByAppendingPathComponent:@"pspkvm"];
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];

    // Re-seed lib/ (romized classes, fonts) whenever the app build changes. appdb/ (installed
    // MIDlets, RMS) and pspkvm.ini / vmsettings.cfg are only seeded once so user data survives updates.
    NSString* ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"0";
    NSString* markerPath = [root stringByAppendingPathComponent:kBundleMarker];
    NSString* old = [NSString stringWithContentsOfFile:markerPath encoding:NSUTF8StringEncoding error:nil];
    NSString* res = [[NSBundle mainBundle] resourcePath];
    NSString* kvm = [res stringByAppendingPathComponent:@"kvm"];

    KVMLOG("sandbox", @"root=%@ bundleVersion=%@ seededVersion=%@", root, ver, old ?: @"(none)");
    if (![old isEqualToString:ver]) {
        KVMLOG("sandbox", @"build changed, re-seeding lib/ from bundle");
        copyTree([kvm stringByAppendingPathComponent:@"lib"], [root stringByAppendingPathComponent:@"lib"]);
        if (![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"appdb"]])
            copyTree([kvm stringByAppendingPathComponent:@"appdb"], [root stringByAppendingPathComponent:@"appdb"]);
        for (NSString* f in @[@"pspkvm.ini", @"vmsettings.cfg"]) {
            NSString* dst = [root stringByAppendingPathComponent:f];
            if (![fm fileExistsAtPath:dst]) {
                NSError* e = nil;
                if (![fm copyItemAtPath:[kvm stringByAppendingPathComponent:f] toPath:dst error:&e])
                    KVMLOG("sandbox", @"ERROR seeding %@: %@", f, e.localizedDescription);
                else KVMLOG("sandbox", @"seeded %@", f);
            }
        }
        [ver writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    // MIDlets dropped in via iTunes file sharing: Documents/pspkvm/root/
    [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"root"]
        withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}

// ---- VM thread ----
static void* vmThread(void* arg) {
    @autoreleasepool {
        // The PSP main() fired javanotify_start() from a 3 s alarm after JavaTask() had
        // initialised itself; do the same from a helper thread.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            KVMLOG("vm", @"javanotify_start()");
            javanotify_start();
        });
    }
    KVMLOG("vm", @"JavaTask() entering");
    int rc = JavaTask();   // blocks until the VM exits
    KVMLOG("vm", @"JavaTask returned rc=%d (VM has exited)", rc);
    return NULL;
}

void KVMStartVM(void) {
    static BOOL started = NO;
    if (started) return;
    started = YES;

    KVMLogInit();
    NSString* root = prepareSandbox();
    chdir(root.fileSystemRepresentation);          // javacall_dir root is "."
    setenv("HOME", root.fileSystemRepresentation, 1);

    KVMLOG("vm", @"cwd=%@, starting VM thread", root);
    javacall_logging_channel(JAVACALL_LOG_CHANNEL_STDOUT);
    pspkvm_ios_set_screen_size(240, 320);          // default MIDP canvas; MIDlets/settings may change it

    pthread_attr_t at;
    pthread_t t;
    pthread_attr_init(&at);
    pthread_attr_setstacksize(&at, 2 * 1024 * 1024);   // C interpreter + KNI need a roomy native stack
    pthread_create(&t, &at, vmThread, NULL);
    pthread_detach(t);
}

void KVMPause(void)  { KVMLOG("vm", @"pause"); javanotify_pause(); }
void KVMResume(void) { KVMLOG("vm", @"resume"); javanotify_resume(); }
