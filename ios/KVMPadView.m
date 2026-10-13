#import "KVMPadView.h"
#include "pspctrl.h"

typedef struct { const char* label; unsigned mask; CGFloat cx, cy, w, h; } PadBtn;   // cx,cy,w,h in 0..1 of the pad view

static const PadBtn kBtns[] = {
    {"^", PSP_CTRL_UP,       0.17, 0.30, 0.10, 0.22}, {"v", PSP_CTRL_DOWN,    0.17, 0.78, 0.10, 0.22},
    {"<", PSP_CTRL_LEFT,     0.07, 0.54, 0.10, 0.22}, {">", PSP_CTRL_RIGHT,   0.27, 0.54, 0.10, 0.22},
    {"\u25B3", PSP_CTRL_TRIANGLE, 0.83, 0.30, 0.10, 0.22}, {"\u2715", PSP_CTRL_CROSS,  0.83, 0.78, 0.10, 0.22},
    {"\u25A1", PSP_CTRL_SQUARE,   0.73, 0.54, 0.10, 0.22}, {"\u25CB", PSP_CTRL_CIRCLE, 0.93, 0.54, 0.10, 0.22},
    {"L", PSP_CTRL_LTRIGGER, 0.08, 0.08, 0.12, 0.14}, {"R", PSP_CTRL_RTRIGGER, 0.92, 0.08, 0.12, 0.14},
    {"SEL", PSP_CTRL_SELECT, 0.42, 0.88, 0.12, 0.14}, {"START", PSP_CTRL_START, 0.58, 0.88, 0.12, 0.14},
};
#define NB (sizeof(kBtns)/sizeof(kBtns[0]))

@implementation KVMPadView {
    UILabel* _lbl[NB];
    unsigned _down;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.multipleTouchEnabled = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        for (int i = 0; i < (int)NB; i++) {
            UILabel* l = [[UILabel alloc] init];
            l.text = [NSString stringWithUTF8String:kBtns[i].label];
            l.textAlignment = NSTextAlignmentCenter;
            l.textColor = [UIColor whiteColor];
            l.font = [UIFont boldSystemFontOfSize:18];
            l.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
            l.layer.cornerRadius = 10; l.layer.masksToBounds = YES;
            l.userInteractionEnabled = NO;
            [self addSubview:l];
            _lbl[i] = l;
        }
    }
    return self;
}

- (CGRect)rectFor:(int)i {
    CGSize s = self.bounds.size;
    CGFloat w = kBtns[i].w * s.width * 1.25, h = kBtns[i].h * s.height * 1.25;
    // keep d-pad / face buttons roughly square-ish and finger sized
    CGFloat m = MAX(MIN(w, h), 44); if (kBtns[i].mask >= PSP_CTRL_TRIANGLE || kBtns[i].mask <= PSP_CTRL_RIGHT) { w = h = m; }
    return CGRectMake(kBtns[i].cx * s.width - w / 2, kBtns[i].cy * s.height - h / 2, w, h);
}

- (void)layoutSubviews {
    for (int i = 0; i < (int)NB; i++) _lbl[i].frame = [self rectFor:i];
}

- (void)updateTouches:(UIEvent*)e {
    unsigned now = 0;
    for (UITouch* t in [e touchesForView:self]) {
        if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) continue;
        CGPoint p = [t locationInView:self];
        for (int i = 0; i < (int)NB; i++)
            if (CGRectContainsPoint(CGRectInset([self rectFor:i], -6, -6), p)) now |= kBtns[i].mask;
    }
    unsigned changed = now ^ _down;
    if (!changed) return;
    for (int i = 0; i < (int)NB; i++) {
        if (changed & kBtns[i].mask) {
            pspkvm_ios_set_button(kBtns[i].mask, (now & kBtns[i].mask) != 0);
            _lbl[i].backgroundColor = (now & kBtns[i].mask) ? [UIColor colorWithWhite:0.55 alpha:1]
                                                             : [UIColor colorWithWhite:0.22 alpha:1];
        }
    }
    _down = now;
}

- (void)touchesBegan:(NSSet*)ts withEvent:(UIEvent*)e     { [self updateTouches:e]; }
- (void)touchesMoved:(NSSet*)ts withEvent:(UIEvent*)e     { [self updateTouches:e]; }
- (void)touchesEnded:(NSSet*)ts withEvent:(UIEvent*)e     { [self updateTouches:e]; }
- (void)touchesCancelled:(NSSet*)ts withEvent:(UIEvent*)e { [self updateTouches:e]; }
@end
