#import "KVMScreenView.h"
#import <QuartzCore/QuartzCore.h>
#include "lcd_ios.h"

extern void pspkvm_ios_pen(int x, int y, int type);   // keypress.c

static void releaseNothing(void* info, const void* data, size_t size) {}

@implementation KVMScreenView {
    CADisplayLink* _link;
    CGColorSpaceRef _cs;
    int _cw, _ch;           // current canvas size
    BOOL _touching;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor blackColor];
        self.multipleTouchEnabled = NO;
        self.layer.contentsGravity = kCAGravityResizeAspect;
        self.layer.magnificationFilter = kCAFilterLinear;
        self.layer.opaque = YES;
        _cs = CGColorSpaceCreateDeviceRGB();
        _cw = 240; _ch = 320;
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.frameInterval = 2;                         // 30 fps: plenty for J2ME, kinder to an A4
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc { [_link invalidate]; if (_cs) CGColorSpaceRelease(_cs); }

- (void)tick:(CADisplayLink*)l {
    ios_lcd_frame fr;
    if (!pspkvm_ios_lcd_get_frame(&fr)) return;
    _cw = fr.width; _ch = fr.height;
    CGDataProviderRef p = CGDataProviderCreateWithData(NULL, fr.pixels,
                              (size_t)fr.width * fr.height * 4, releaseNothing);
    CGImageRef img = CGImageCreate(fr.width, fr.height, 8, 32, (size_t)fr.width * 4, _cs,
                                   kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
                                   p, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(p);
    if (img) {
        // CALayer keeps the CGImage; its pixel pointer is valid for >=2 more flushes (triple buffer)
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.layer.contents = (__bridge id)img;
        [CATransaction commit];
        CGImageRelease(img);
    }
}

// aspect-fit rect of the canvas inside the view, same as kCAGravityResizeAspect
- (CGRect)canvasRect {
    CGSize b = self.bounds.size;
    CGFloat s = MIN(b.width / _cw, b.height / _ch);
    CGFloat w = _cw * s, h = _ch * s;
    return CGRectMake((b.width - w) / 2, (b.height - h) / 2, w, h);
}

- (void)sendTouch:(UITouch*)t type:(int)type {
    CGPoint pt = [t locationInView:self];
    CGRect r = [self canvasRect];
    int x = (int)((pt.x - r.origin.x) * _cw / r.size.width);
    int y = (int)((pt.y - r.origin.y) * _ch / r.size.height);
    if (x < 0) x = 0; if (x >= _cw) x = _cw - 1;
    if (y < 0) y = 0; if (y >= _ch) y = _ch - 1;
    pspkvm_ios_pen(x, y, type);
}

- (void)touchesBegan:(NSSet*)ts withEvent:(UIEvent*)e { _touching = YES; [self sendTouch:ts.anyObject type:1]; }
- (void)touchesMoved:(NSSet*)ts withEvent:(UIEvent*)e { if (_touching) [self sendTouch:ts.anyObject type:3]; }
- (void)touchesEnded:(NSSet*)ts withEvent:(UIEvent*)e { if (_touching) [self sendTouch:ts.anyObject type:2]; _touching = NO; }
- (void)touchesCancelled:(NSSet*)ts withEvent:(UIEvent*)e { [self touchesEnded:ts withEvent:e]; }
@end
