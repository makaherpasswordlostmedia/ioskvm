#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Prepares the sandbox (Documents/pspkvm), starts the VM thread. Call once. */
void KVMStartVM(void);
/* UIApplication lifecycle forwarding */
void KVMPause(void);
void KVMResume(void);
/* Posted on the main queue when the Java canvas size changes: userInfo @{@"w":,@"h":} */
extern NSString* const KVMScreenResizedNotification;
#ifdef __cplusplus
}
#endif
