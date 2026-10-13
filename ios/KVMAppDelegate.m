#import "KVMAppDelegate.h"
#import "KVMBridge.h"
#import "KVMScreenView.h"
#import "KVMPadView.h"

@interface KVMViewController : UIViewController
@end

@implementation KVMViewController {
    KVMScreenView* _screen;
    KVMPadView* _pad;
}
- (void)loadView { self.view = [[UIView alloc] init]; self.view.backgroundColor = [UIColor blackColor]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    _screen = [[KVMScreenView alloc] init];
    _pad = [[KVMPadView alloc] init];
    [self.view addSubview:_screen];
    [self.view addSubview:_pad];
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotate { return YES; }
- (void)viewDidLayoutSubviews {
    CGRect b = self.view.bounds;
    if (b.size.width > b.size.height) {                       // landscape: screen fills, pad overlaid at the bottom
        _screen.frame = b;
        _pad.frame = CGRectMake(0, b.size.height - 150, b.size.width, 150);
        _pad.alpha = 0.55; _pad.backgroundColor = [UIColor clearColor];
    } else {                                                   // portrait: screen on top, pad below
        CGFloat padH = MIN(220, b.size.height * 0.34);
        _screen.frame = CGRectMake(0, 0, b.size.width, b.size.height - padH);
        _pad.frame = CGRectMake(0, b.size.height - padH, b.size.width, padH);
        _pad.alpha = 1; _pad.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    }
}
@end

@implementation KVMAppDelegate
- (BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)o {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[KVMViewController alloc] init];
    [self.window makeKeyAndVisible];
    app.idleTimerDisabled = YES;
    KVMStartVM();
    return YES;
}
- (void)applicationWillResignActive:(UIApplication*)a { KVMPause(); }
- (void)applicationDidBecomeActive:(UIApplication*)a  { KVMResume(); }
@end
