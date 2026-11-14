#import "CtlSplashView.h"
#import <QuartzCore/QuartzCore.h>

static UIColor *C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return [UIColor colorWithRed:r green:g blue:b alpha:a]; }
#define SP_GREEN C(0.24, 1.00, 0.43, 1)
#define SP_CYAN  C(0.24, 0.86, 1.00, 1)
static const CGFloat kBarW = 420, kBarH = 6, kBarY = 620, kBase = 284;      // kBase = centro della zona delle tracce

@implementation CtlSplashView {
    CALayer *_traces, *_track, *_fill;
    NSMutableArray<CAShapeLayer *> *_lines; NSMutableArray<CALayer *> *_dots;   // ECG, pletismografia, capnogramma
    CAGradientLayer *_shine;
    UILabel *_status, *_percent, *_version;
    NSArray<NSArray *> *_stages; NSTimeInterval _minStage; void (^_done)(void);
    CGFloat _progress;
}

static double Gauss(double x, double c, double w) { double d = (x - c) / w; return exp(-d * d); }

// Tre tracce come sul monitor: ECG II (verde), pletismografia SpO2 (azzurra, in ritardo sul QRS), capnogramma (giallo)
- (UIBezierPath *)pathFor:(NSInteger)kind {
    UIBezierPath *p = [UIBezierPath bezierPath]; CGFloat W = self.bounds.size.width, period = 176;
    for (CGFloat x = 40; x <= W - 40; x += 1.5) {
        double t = fmod(x - 40 + period * 0.45, period);          // posizione dentro il battito
        CGFloat y;
        if (kind == 0) {
            double v = 7 * Gauss(t, 44, 9)                                                        // P
                     - 7 * Gauss(t, 73, 2.6) + 66 * Gauss(t, 79, 3.0) - 15 * Gauss(t, 85.5, 3.0)  // QRS
                     + 14 * Gauss(t, 124, 15);                                                    // T
            y = 218 - (CGFloat)v;
        } else if (kind == 1) {
            double u = fmod(t - 79 - 34 + 2 * period, period);    // l'onda di polso arriva dopo il QRS
            double v = 34 * Gauss(u, 22, u < 22 ? 9 : 17) + 9 * Gauss(u, 62, 13);                 // picco sistolico + onda dicrota
            y = 322 - (CGFloat)v;
        } else {
            double u = fmod(x - 40 + 60, 372) / 372;              // un atto respiratorio ogni 372 pt
            double up = 1 / (1 + exp(-(u - 0.22) * 90)), down = 1 / (1 + exp(-(u - 0.60) * 110));
            double v = (30 + 8 * (u - 0.22) / 0.38) * up * (1 - down);                            // plateau in lieve salita
            y = 410 - (CGFloat)v;
        }
        if (x == 40) [p moveToPoint:CGPointMake(x, y)]; else [p addLineToPoint:CGPointMake(x, y)];
    }
    return p;
}

- (instancetype)initWithFrame:(CGRect)frame version:(NSString *)version {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES; self.userInteractionEnabled = YES;      // durante la splash i tocchi non arrivano al monitor
        CGFloat W = frame.size.width, H = frame.size.height;
        _traces = [CALayer layer]; _traces.frame = self.bounds;
        _lines = [NSMutableArray array]; _dots = [NSMutableArray array];
        NSArray<UIColor *> *cols = @[SP_GREEN, SP_CYAN, C(0.95, 0.88, 0.35, 1)];
        for (NSInteger k = 0; k < 3; k++) {
            UIColor *col = cols[k];
            CAShapeLayer *l = [CAShapeLayer layer]; l.frame = self.bounds; l.path = [self pathFor:k].CGPath;
            l.strokeColor = col.CGColor; l.fillColor = nil; l.lineWidth = k == 0 ? 2.5 : 2.2;
            l.lineJoin = kCALineJoinRound; l.lineCap = kCALineCapRound;
            l.shadowColor = col.CGColor; l.shadowRadius = 7; l.shadowOpacity = 0.55; l.shadowOffset = CGSizeZero;   // alone leggero
            l.strokeEnd = 0;
            [_traces addSublayer:l]; [_lines addObject:l];
            // punto luminoso in testa alla traccia
            CALayer *d = [CALayer layer]; d.bounds = CGRectMake(0, 0, 8, 8); d.cornerRadius = 4;
            d.backgroundColor = C(0.95, 1, 0.97, 1).CGColor;
            d.shadowColor = col.CGColor; d.shadowRadius = 8; d.shadowOpacity = 1; d.shadowOffset = CGSizeZero;
            d.opacity = 0;
            [_traces addSublayer:d]; [_dots addObject:d];
        }
        CAGradientLayer *mask = [CAGradientLayer layer]; mask.frame = self.bounds;
        mask.startPoint = CGPointMake(0, 0.5); mask.endPoint = CGPointMake(1, 0.5);
        mask.colors = @[(id)C(0, 0, 0, 0).CGColor, (id)C(0, 0, 0, 1).CGColor, (id)C(0, 0, 0, 1).CGColor, (id)C(0, 0, 0, 0).CGColor];
        mask.locations = @[@0.05, @0.20, @0.80, @0.95];
        _traces.mask = mask;
        [self.layer addSublayer:_traces];

        // barra di caricamento: binario sottile, riempimento sfumato verde -> azzurro con un riflesso che scorre
        _track = [CALayer layer]; _track.frame = CGRectMake((W - kBarW) / 2, kBarY, kBarW, kBarH);
        _track.backgroundColor = C(1, 1, 1, 0.10).CGColor; _track.cornerRadius = kBarH / 2; _track.masksToBounds = YES;
        _fill = [CALayer layer]; _fill.anchorPoint = CGPointMake(0, 0); _fill.frame = CGRectMake(0, 0, 0, kBarH);
        _fill.masksToBounds = YES; _fill.cornerRadius = kBarH / 2;
        CAGradientLayer *grad = [CAGradientLayer layer]; grad.frame = CGRectMake(0, 0, kBarW, kBarH);
        grad.startPoint = CGPointMake(0, 0.5); grad.endPoint = CGPointMake(1, 0.5);
        grad.colors = @[(id)C(0.04, 0.52, 1.0, 1).CGColor, (id)SP_CYAN.CGColor];
        [_fill addSublayer:grad];
        _shine = [CAGradientLayer layer]; _shine.frame = CGRectMake(-90, 0, 90, kBarH);
        _shine.startPoint = CGPointMake(0, 0.5); _shine.endPoint = CGPointMake(1, 0.5);
        _shine.colors = @[(id)C(1, 1, 1, 0).CGColor, (id)C(1, 1, 1, 0.75).CGColor, (id)C(1, 1, 1, 0).CGColor];
        [_fill addSublayer:_shine];
        [_track addSublayer:_fill]; [self.layer addSublayer:_track];

        UIFont *num = [UIFont fontWithName:@"AvenirNext-Medium" size:15] ?: [UIFont systemFontOfSize:15];
        _status = [[UILabel alloc] initWithFrame:CGRectMake((W - kBarW) / 2, kBarY + 14, kBarW - 60, 24)];
        _status.font = [UIFont fontWithName:@"AvenirNext-Regular" size:15] ?: [UIFont systemFontOfSize:15];
        _status.textColor = C(0.62, 0.66, 0.70, 1); _status.backgroundColor = [UIColor clearColor];
        [self addSubview:_status];
        _percent = [[UILabel alloc] initWithFrame:CGRectMake((W + kBarW) / 2 - 60, kBarY + 14, 60, 24)];
        _percent.font = num; _percent.textAlignment = NSTextAlignmentRight;
        _percent.textColor = C(0.80, 0.84, 0.88, 1); _percent.backgroundColor = [UIColor clearColor];
        [self addSubview:_percent];
        _version = [[UILabel alloc] initWithFrame:CGRectMake(W - 220, H - 34, 204, 20)];
        _version.textAlignment = NSTextAlignmentRight; _version.font = [UIFont systemFontOfSize:13];
        _version.textColor = C(0.40, 0.42, 0.45, 1); _version.backgroundColor = [UIColor clearColor];
        _version.text = version.length ? [@"versione " stringByAppendingString:version] : @"";
        [self addSubview:_version];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef g = UIGraphicsGetCurrentContext(); CGRect b = self.bounds; CGFloat W = b.size.width, H = b.size.height;
    // sfondo: sfumatura verticale + luce morbida dietro alla traccia
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat c1[] = { 0.055, 0.075, 0.095, 1,  0.020, 0.026, 0.034, 1 };
    CGGradientRef g1 = CGGradientCreateWithColorComponents(cs, c1, NULL, 2);
    CGContextDrawLinearGradient(g, g1, CGPointMake(0, 0), CGPointMake(0, H), 0); CGGradientRelease(g1);
    CGFloat c2[] = { 0.10, 0.50, 0.36, 0.20,  0.10, 0.50, 0.36, 0 };
    CGGradientRef g2 = CGGradientCreateWithColorComponents(cs, c2, NULL, 2);
    CGContextDrawRadialGradient(g, g2, CGPointMake(W / 2, kBase), 0, CGPointMake(W / 2, kBase), 540, 0); CGGradientRelease(g2);
    CGColorSpaceRelease(cs);
    // reticolo da monitor appena accennato, che sfuma verso i bordi
    CGFloat gy0 = 140, gy1 = 428, st = 32, cy = (gy0 + gy1) / 2, hh = (gy1 - gy0) / 2;
    for (CGFloat x = 0; x <= W; x += st) for (CGFloat y = gy0; y < gy1; y += st) {
        CGFloat fx = MAX(0, 1 - pow(fabs(x - W / 2) / (W * 0.46), 2.2)), fx2 = MAX(0, 1 - pow(fabs(x + st / 2 - W / 2) / (W * 0.46), 2.2));
        CGFloat fy = MAX(0, 1 - pow(fabs(y + st / 2 - cy) / hh, 2.2)), fy2 = MAX(0, 1 - pow(fabs(y - cy) / hh, 2.2));
        [C(1, 1, 1, (fmod(x, 160) == 0 ? 0.06 : 0.03) * fx * fy) setFill]; UIRectFillUsingBlendMode(CGRectMake(x, y, 1, st), kCGBlendModeNormal);
        [C(1, 1, 1, 0.035 * fx2 * fy2) setFill]; UIRectFillUsingBlendMode(CGRectMake(x, y, st, 1), kCGBlendModeNormal);
    }
    // titolo
    UIFont *f1 = [UIFont fontWithName:@"AvenirNext-DemiBold" size:66] ?: [UIFont boldSystemFontOfSize:66];
    UIFont *f2 = [UIFont fontWithName:@"AvenirNext-UltraLight" size:66] ?: [UIFont systemFontOfSize:66];
    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:@"similFranz" attributes:@{ NSFontAttributeName: f1, NSForegroundColorAttributeName: C(0.96, 0.97, 0.97, 1) }];
    [t appendAttributedString:[[NSAttributedString alloc] initWithString:@" Controller" attributes:@{ NSFontAttributeName: f2, NSForegroundColorAttributeName: C(0.04, 0.52, 1.0, 1) }]];
    CGSize ts = [t size]; [t drawAtPoint:CGPointMake((W - ts.width) / 2, 446)];
    NSDictionary *sub = @{ NSFontAttributeName: [UIFont fontWithName:@"AvenirNext-Regular" size:21] ?: [UIFont systemFontOfSize:21],
                           NSForegroundColorAttributeName: C(0.62, 0.66, 0.70, 1), NSKernAttributeName: @0.6 };
    NSString *s = @"La regia dell'istruttore per la simulazione sanitaria"; CGSize ss = [s sizeWithAttributes:sub];
    [s drawAtPoint:CGPointMake((W - ss.width) / 2, 538) withAttributes:sub];
    NSDictionary *dis = @{ NSFontAttributeName: [UIFont systemFontOfSize:13], NSForegroundColorAttributeName: C(0.45, 0.47, 0.50, 1), NSKernAttributeName: @1.6 };
    s = @"SIMULAZIONE  ·  NON PER USO CLINICO"; ss = [s sizeWithAttributes:dis];
    [s drawAtPoint:CGPointMake((W - ss.width) / 2, H - 34) withAttributes:dis];
}

- (void)makeStatic { _traces.hidden = YES; _track.hidden = YES; _status.hidden = YES; _percent.hidden = YES; _version.hidden = YES; }

- (void)setProgress:(CGFloat)p {
    p = MAX(_progress, MIN(1, p));
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"bounds.size.width"];
    a.fromValue = @(((CALayer *)(_fill.presentationLayer ?: _fill)).bounds.size.width); a.toValue = @(kBarW * p); a.duration = 1.0;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _fill.bounds = CGRectMake(0, 0, kBarW * p, kBarH);
    [CATransaction commit];
    [_fill addAnimation:a forKey:@"load"];
    _progress = p;
    _percent.text = [NSString stringWithFormat:@"%ld%%", (long)lround(p * 100)];
}

- (void)setStatus:(NSString *)s {
    CATransition *f = [CATransition animation]; f.type = kCATransitionFade; f.duration = 0.5;
    [_status.layer addAnimation:f forKey:@"fade"];
    _status.text = s;
}

- (void)startAnimations {
    // sweep da monitor: la traccia si disegna da sinistra a destra con il punto in testa, sfuma e ricomincia
    const CFTimeInterval T = 6.4;                 // lento come lo sweep di un monitor vero
    for (NSUInteger k = 0; k < _lines.count; k++) {
        CAShapeLayer *line = _lines[k]; CALayer *dot = _dots[k];
        CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        draw.fromValue = @0; draw.toValue = @1; draw.duration = T * 0.78; draw.fillMode = kCAFillModeForwards;
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = @[@1, @1, @0]; fade.keyTimes = @[@0, @0.84, @1]; fade.duration = T;
        CAAnimationGroup *grp = [CAAnimationGroup animation]; grp.animations = @[draw, fade]; grp.duration = T; grp.repeatCount = HUGE_VALF;
        line.strokeEnd = 1; [line addAnimation:grp forKey:@"sweep"];
        CAKeyframeAnimation *move = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        move.path = line.path; move.calculationMode = kCAAnimationPaced; move.duration = T * 0.78; move.fillMode = kCAFillModeForwards;
        CAKeyframeAnimation *dfade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        dfade.values = @[@1, @1, @0, @0]; dfade.keyTimes = @[@0, @0.76, @0.80, @1]; dfade.duration = T;
        CAAnimationGroup *dg = [CAAnimationGroup animation]; dg.animations = @[move, dfade]; dg.duration = T; dg.repeatCount = HUGE_VALF;
        [dot addAnimation:dg forKey:@"head"];
    }
    // riflesso che scorre sulla barra
    CABasicAnimation *sh = [CABasicAnimation animationWithKeyPath:@"position.x"];
    sh.fromValue = @(-45); sh.toValue = @(kBarW + 45); sh.duration = 2.6; sh.repeatCount = HUGE_VALF;
    [_shine addAnimation:sh forKey:@"shine"];
}

- (void)runStages:(NSArray<NSArray *> *)stages minStage:(NSTimeInterval)minStage completion:(void (^)(void))done {
    _stages = [stages copy]; _minStage = minStage; _done = [done copy];
    [self startAnimations];
    [self setProgress:0.04];
    [self runStage:0];
}

// fase che aspetta un evento esterno (es. il monitor che risponde): la barra avanza piano finché arriva o scade il tempo
- (void)wait:(BOOL (^)(void))ready until:(CFTimeInterval)deadline stage:(NSUInteger)i started:(CFTimeInterval)t0 {
    if (!self.superview) return;
    CFTimeInterval now = CACurrentMediaTime(); NSUInteger n = _stages.count;
    BOOL done = ready() || now >= deadline;
    if (done && now - t0 >= _minStage - 0.55) { [self setProgress:(i + 1.0) / n]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self runStage:i + 1]; }); return; }
    CGFloat frac = MIN(0.95, (now - t0) / MAX(0.5, deadline - t0));
    [self setProgress:(i + 0.45 + 0.5 * frac) / n];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self wait:ready until:deadline stage:i started:t0]; });
}

- (void)runStage:(NSUInteger)i {
    if (!self.superview) return;                                  // tolta dall'esterno (autotest): la catena si ferma
    NSUInteger n = _stages.count;
    if (i >= n) {
        [self setProgress:1]; [self setStatus:@"Pronto"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.9 animations:^{ self.alpha = 0; } completion:^(BOOL f) {
                [self removeFromSuperview]; if (self->_done) self->_done();
            }];
        });
        return;
    }
    NSArray *st = _stages[i];
    [self setStatus:st[0]];
    [self setProgress:(i + 0.45) / n];
    // un attimo perché l'etichetta arrivi sullo schermo, poi il lavoro vero della fase
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFTimeInterval t0 = CACurrentMediaTime();
        if (st.count > 1 && st[1] != [NSNull null]) ((void (^)(void))st[1])();
        BOOL (^ready)(void) = st.count > 2 && st[2] != [NSNull null] ? st[2] : nil;
        CFTimeInterval maxWait = st.count > 3 ? [st[3] doubleValue] : 0;
        if (ready) { [self wait:ready until:t0 + maxWait stage:i started:t0]; return; }
        [self setProgress:(i + 1.0) / n];
        CFTimeInterval left = MAX(0.05, self->_minStage - 0.55 - (CACurrentMediaTime() - t0));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(left * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self runStage:i + 1]; });
    });
}
@end
