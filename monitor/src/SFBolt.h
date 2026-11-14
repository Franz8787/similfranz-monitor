// SimulaFranz_Monitor — fulmine vettoriale per i tasti SHOCK (stesso disegno in tutti i layout).
// Forma piena a zig-zag con punta in basso, angoli smussati, contorno sottile e ombra corta.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static inline UIBezierPath *SFBoltPath(CGRect r) {
    // proporzioni 0.62 x 1 centrate nel rettangolo
    CGFloat h = r.size.height, w = h * 0.62;
    CGFloat x = r.origin.x + (r.size.width - w) / 2, y = r.origin.y;
    CGPoint p[] = { {0.50, 0.00}, {0.92, 0.00}, {0.60, 0.40}, {0.98, 0.40}, {0.22, 1.00}, {0.42, 0.55}, {0.04, 0.55} };
    UIBezierPath *b = [UIBezierPath bezierPath];
    for (int i = 0; i < 7; i++) {
        CGPoint q = CGPointMake(x + p[i].x * w, y + p[i].y * h);
        if (i == 0) [b moveToPoint:q]; else [b addLineToPoint:q];
    }
    [b closePath];
    return b;
}

// Aggiunge (o sostituisce) il fulmine dentro la vista, alto `frac` della vista, nel colore dato.
static inline CAShapeLayer *SFAddBolt(UIView *v, UIColor *fill, UIColor *edge, CGFloat frac) {
    for (CALayer *l in [v.layer.sublayers copy]) if ([l.name isEqualToString:@"SFBolt"]) [l removeFromSuperlayer];
    CGFloat h = v.bounds.size.height * frac;
    CGRect r = CGRectMake(0, (v.bounds.size.height - h) / 2, v.bounds.size.width, h);
    CAShapeLayer *s = [CAShapeLayer layer];
    s.name = @"SFBolt"; s.frame = v.bounds; s.path = SFBoltPath(r).CGPath;
    s.fillColor = fill.CGColor; s.strokeColor = (edge ?: fill).CGColor;
    s.lineWidth = MAX(1.0, h * 0.035); s.lineJoin = kCALineJoinRound;   // spigoli smussati
    s.shadowColor = [UIColor blackColor].CGColor; s.shadowOpacity = 0.30; s.shadowRadius = 1.5; s.shadowOffset = CGSizeMake(0, 1);
    s.shadowPath = s.path;                         // ombra precalcolata: senza, verrebbe ricalcolata a ogni fotogramma
    [v.layer addSublayer:s];
    return s;
}
