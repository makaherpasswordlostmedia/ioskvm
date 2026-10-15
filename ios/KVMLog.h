// Runtime logging for the iOS port.
// Everything goes to Documents/pspkvm/logs/kvm.log (previous run: kvm.prev.log), which is
// visible in the Files app / iTunes file sharing. VM stdout/stderr (Java System.out,
// javacall logging, NSLog) is captured too, and crashes are written before the app dies.
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Call first thing, once. Opens the log, rotates the old one, captures stdout/stderr, installs crash handlers. */
void KVMLogInit(void);
/* Printf-style app log line: [time] [tag] message */
void KVMLogf(const char* tag, NSString* fmt, ...) NS_FORMAT_FUNCTION(2, 3);
/* Absolute path of the current log file (nil before KVMLogInit). */
NSString* KVMLogPath(void);
#ifdef __cplusplus
}
#endif
#define KVMLOG(tag, ...) KVMLogf((tag), __VA_ARGS__)
