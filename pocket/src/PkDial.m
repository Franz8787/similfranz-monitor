#import "PkDial.h"
#import "CtlUI.h"
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

static const NSInteger kDetents = 30;                 // scatti per giro (uno ogni 12°)

// Clic: 5 ms di sinusoide smorzata a 2,6 kHz, generato una volta in un WAV temporaneo (suono di sistema = latenza minima)
void PkClick(void) {
    static SystemSoundID sid; static dispatch_once_t once; static CFTimeInterval last;
    dispatch_once(&once, ^{
        enum { rate = 44100, n = 220 }; NSMutableData *d = [NSMutableData data];
        int16_t pcm[n]; for (int i = 0; i < n; i++) pcm[i] = (int16_t)(sin(2 * M_PI * 2600.0 * i / rate) * exp(-i / (n / 5.0)) * 14000);
        uint32_t dataLen = n * 2, riff = 36 + dataLen, fmtLen = 16, srate = rate, brate = rate * 2; uint16_t pcmTag = 1, ch = 1, align = 2, bits = 16;
        [d appendBytes:"RIFF" length:4]; [d appendBytes:&riff length:4]; [d appendBytes:"WAVEfmt " length:8]; [d appendBytes:&fmtLen length:4];
        [d appendBytes:&pcmTag length:2]; [d appendBytes:&ch length:2]; [d appendBytes:&srate length:4]; [d appendBytes:&brate length:4];
        [d appendBytes:&align length:2]; [d appendBytes:&bits length:2]; [d appendBytes:"data" length:4]; [d appendBytes:&dataLen length:4];
        [d appendBytes:pcm length:dataLen];
        NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"pk_click.wav"];
        [d writeToFile:p atomically:YES];
        AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:p], &sid);
    });
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.03) return;                   // girando veloce non diventa un ronzio
    last = now; if (sid) AudioServicesPlaySystemSound(sid);
}

@implementation PkDial {
    CAShapeLayer *_track, *_arc; CALayer *_knob, *_now, *_wheel;
    UILabel *_title, *_val, *_unit, *_note;
    UIColor *_color; NSString *_unitText;
    double _min, _max, _step, _value; NSInteger _dec;
    CGFloat _lastAngle, _acc; CFTimeInterval _lastT; BOOL _moved, _inCenter; CGFloat _wheelAngle;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor clearColor]; self.multipleTouchEnabled = NO;
        CGFloat S = MIN(f.size.width, f.size.height), R = S / 2 - 9; CGPoint c = CGPointMake(f.size.width / 2, f.size.height / 2);
        UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:c radius:R startAngle:M_PI * 0.75 endAngle:M_PI * 2.25 clockwise:YES];
        _track = [CAShapeLayer layer]; _track.path = p.CGPath; _track.fillColor = nil; _track.lineWidth = 8; _track.lineCap = kCALineCapRound;
        _track.strokeColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor; [self.layer addSublayer:_track];
        _arc = [CAShapeLayer layer]; _arc.path = p.CGPath; _arc.fillColor = nil; _arc.lineWidth = 8; _arc.lineCap = kCALineCapRound; _arc.strokeEnd = 0;
        [self.layer addSublayer:_arc];
        // rotella con le tacche: gira sotto il dito (la si vede muovere anche quando il valore è al limite)
        CGFloat r = R - 24;
        _wheel = [CALayer layer]; _wheel.bounds = CGRectMake(0, 0, 2 * r, 2 * r); _wheel.position = c; _wheel.cornerRadius = r;
        _wheel.backgroundColor = CTL_CARD.CGColor; _wheel.borderWidth = 1; _wheel.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
        CAShapeLayer *ticks = [CAShapeLayer layer]; ticks.frame = _wheel.bounds; UIBezierPath *tp = [UIBezierPath bezierPath];
        for (NSInteger i = 0; i < kDetents; i++) {
            CGFloat a = i * 2 * M_PI / kDetents, r0 = r - (i % 5 ? 9 : 14), r1 = r - 4;
            [tp moveToPoint:CGPointMake(r + cos(a) * r0, r + sin(a) * r0)]; [tp addLineToPoint:CGPointMake(r + cos(a) * r1, r + sin(a) * r1)];
        }
        ticks.path = tp.CGPath; ticks.strokeColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor; ticks.lineWidth = 1.5; ticks.lineCap = kCALineCapRound;
        [_wheel addSublayer:ticks];
        CALayer *grip = [CALayer layer]; grip.bounds = CGRectMake(0, 0, 9, 9); grip.cornerRadius = 4.5; grip.position = CGPointMake(r, 22);
        grip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor; [_wheel addSublayer:grip];
        _wheel.shouldRasterize = YES; _wheel.rasterizationScale = [UIScreen mainScreen].scale;
        [self.layer addSublayer:_wheel];
        _now = [CALayer layer]; _now.bounds = CGRectMake(0, 0, 10, 10); _now.cornerRadius = 5; _now.borderWidth = 2;
        _now.borderColor = [UIColor colorWithWhite:1 alpha:0.75].CGColor; _now.backgroundColor = CTL_BG.CGColor; [self.layer addSublayer:_now];
        _knob = [CALayer layer]; _knob.bounds = CGRectMake(0, 0, 18, 18); _knob.cornerRadius = 9; _knob.backgroundColor = [UIColor whiteColor].CGColor;
        _knob.shadowColor = [UIColor blackColor].CGColor; _knob.shadowOpacity = 0.5; _knob.shadowRadius = 3; _knob.shadowOffset = CGSizeZero;
        _knob.shadowPath = [UIBezierPath bezierPathWithOvalInRect:_knob.bounds].CGPath; [self.layer addSublayer:_knob];
        // testi al centro
        CGFloat w = 2 * r - 30;
        _title = CtlLabel(CGRectMake(c.x - w / 2, c.y - 62, w, 18), @"", 13, YES, CTL_INK2); _title.textAlignment = NSTextAlignmentCenter;
        _title.adjustsFontSizeToFitWidth = YES; _title.minimumScaleFactor = 0.7;
        _val = CtlLabel(CGRectMake(c.x - w / 2, c.y - 42, w, 60), @"", 52, YES, CTL_INK); _val.textAlignment = NSTextAlignmentCenter;
        _val.font = CtlDigits(52, YES); _val.adjustsFontSizeToFitWidth = YES; _val.minimumScaleFactor = 0.5;
        _unit = CtlLabel(CGRectMake(c.x - w / 2, c.y + 18, w, 16), @"", 12, NO, CTL_INK3); _unit.textAlignment = NSTextAlignmentCenter;
        _note = CtlLabel(CGRectMake(c.x - w / 2 - 6, c.y + 36, w + 12, 30), @"", 12, NO, CTL_INK2); _note.textAlignment = NSTextAlignmentCenter; _note.numberOfLines = 2;
        _note.adjustsFontSizeToFitWidth = YES; _note.minimumScaleFactor = 0.8;
        for (UILabel *l in @[_title, _val, _unit, _note]) { l.userInteractionEnabled = NO; [self addSubview:l]; }
    }
    return self;
}

- (void)configureTitle:(NSString *)title unit:(NSString *)unit color:(UIColor *)color min:(double)min max:(double)max step:(double)step decimals:(NSInteger)decimals {
    _title.text = title.uppercaseString; _unitText = unit; _unit.text = unit; _color = color; _min = min; _max = max; _step = step; _dec = decimals;
    _val.textColor = color; _arc.strokeColor = color.CGColor;
    _turning = NO;
}

- (double)snap:(double)v { v = MAX(_min, MIN(_max, v)); return round(v / _step) * _step; }
- (NSString *)fmt:(double)v { return _dec ? [NSString stringWithFormat:@"%.*f", (int)_dec, v] : [NSString stringWithFormat:@"%ld", (long)lround(v)]; }
- (CGPoint)pointFor:(double)v {
    double f = _max > _min ? (v - _min) / (_max - _min) : 0; CGFloat a = M_PI * 0.75 + f * M_PI * 1.5;
    CGFloat R = MIN(self.bounds.size.width, self.bounds.size.height) / 2 - 9;
    return CGPointMake(self.bounds.size.width / 2 + cos(a) * R, self.bounds.size.height / 2 + sin(a) * R);
}
- (void)render {
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    double f = _max > _min ? (_value - _min) / (_max - _min) : 0;
    _arc.strokeEnd = MAX(0.001, f); _knob.position = [self pointFor:_value];
    _wheel.transform = CATransform3DMakeRotation(_wheelAngle, 0, 0, 1);
    [CATransaction commit];
    _val.text = [self fmt:_value];
}

- (void)showValue:(double)value current:(double)current note:(NSString *)note {
    if (_turning) return;
    _value = [self snap:value];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _now.position = [self pointFor:[self snap:current]]; _now.hidden = fabs(current - _value) < _step / 2;
    [CATransaction commit];
    _note.text = note ?: @"";
    [self render];
}

#pragma mark - tocco

- (CGFloat)angleOf:(CGPoint)p { return atan2(p.y - self.bounds.size.height / 2, p.x - self.bounds.size.width / 2); }
- (CGFloat)distOf:(CGPoint)p { return hypot(p.x - self.bounds.size.width / 2, p.y - self.bounds.size.height / 2); }

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint p = [touches.anyObject locationInView:self];
    _lastAngle = [self angleOf:p]; _acc = 0; _lastT = CACurrentMediaTime(); _moved = NO; _turning = YES;
    _inCenter = [self distOf:p] < 46;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint p = [touches.anyObject locationInView:self];
    if ([self distOf:p] < 22) return;                 // troppo vicino al centro: l'angolo non è affidabile
    CGFloat a = [self angleOf:p], d = a - _lastAngle;
    if (d > M_PI) d -= 2 * M_PI; else if (d < -M_PI) d += 2 * M_PI;
    CFTimeInterval t = CACurrentMediaTime(), dt = MAX(0.008, t - _lastT);
    _lastAngle = a; _lastT = t; _acc += d; _wheelAngle += d;
    CGFloat detent = 2 * M_PI / kDetents;
    NSInteger steps = (NSInteger)(_acc / detent);
    if (steps) {
        _acc -= steps * detent; _moved = YES;
        double speed = fabs(d) / dt;                  // rad/s: più veloce = salti più grandi
        NSInteger mult = speed > 9 ? 5 : (speed > 4.5 ? 2 : 1);
        double v = [self snap:_value + steps * mult * _step];
        if (v != _value) { _value = v; PkClick(); if (self.onChange) self.onChange(_value, NO); }
    }
    [self render];
}
- (void)finishTouch {
    if (!_turning) return;
    _turning = NO;
    if (_moved) { if (self.onChange) self.onChange(_value, YES); }
    else if (_inCenter && self.onCenterTap) self.onCenterTap();
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouch]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouch]; }

- (void)debugTurn:(NSInteger)steps {
    _turning = YES; _moved = steps != 0;
    _wheelAngle += steps * 2 * M_PI / kDetents;
    _value = [self snap:_value + steps * _step]; [self render];
    if (self.onChange) self.onChange(_value, NO);
    [self finishTouch];
}
@end
