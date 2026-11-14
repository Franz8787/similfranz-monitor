#import "SFTactile.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const void *kFaceKey = &kFaceKey;
static const void *kSheenKey = &kSheenKey;
static const void *kSideKey = &kSideKey;          // -1 = metà sinistra del bilanciere, +1 = metà destra

@implementation SFTactile

+ (instancetype)shared {
    static SFTactile *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SFTactile new]; });
    return s;
}

+ (void)applyToButton:(UIButton *)button {
    [self applyToFace:button control:button radius:button.layer.cornerRadius strength:1.0];
}

+ (void)applyToFace:(UIView *)face control:(UIControl *)control radius:(CGFloat)radius strength:(CGFloat)k {
    if (!face || !control || objc_getAssociatedObject(control, kFaceKey)) return;
    if (k <= 0) {                                         // solo animazione di pressione (tasti già disegnati in rilievo)
        objc_setAssociatedObject(control, kFaceKey, face, OBJC_ASSOCIATION_ASSIGN);
        [self addTargetsTo:control];
        return;
    }
    k = MIN(1.5, k);
    CAGradientLayer *old = objc_getAssociatedObject(face, kSheenKey);
    if (old) {                                            // stessa faccia, altro controllo (es. ▼ ... ▲): niente doppio rilievo
        objc_setAssociatedObject(control, kFaceKey, face, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(control, kSheenKey, old, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addTargetsTo:control];
        return;
    }
    // riflesso: chiaro in alto, neutro al centro, leggermente scuro in basso (sopra lo sfondo, sotto testo e icone)
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = face.bounds; g.cornerRadius = radius;
    g.colors = @[ (id)[UIColor colorWithWhite:1 alpha:0.30 * k].CGColor,
                  (id)[UIColor colorWithWhite:1 alpha:0.06 * k].CGColor,
                  (id)[UIColor colorWithWhite:0 alpha:0.0].CGColor,
                  (id)[UIColor colorWithWhite:0 alpha:0.16 * k].CGColor ];
    g.locations = @[@0.0, @0.42, @0.6, @1.0];
    [face.layer insertSublayer:g atIndex:0];
    // ombra corta sotto il tasto (dà la sensazione di tasto in rilievo)
    face.layer.masksToBounds = NO;
    face.layer.shadowColor = [UIColor blackColor].CGColor;
    face.layer.shadowOpacity = 0.38 * MIN(1.0, k);
    face.layer.shadowRadius = 1.6;
    face.layer.shadowOffset = CGSizeMake(0, 1.8);
    face.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:face.bounds cornerRadius:radius].CGPath;
    objc_setAssociatedObject(control, kFaceKey, face, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(control, kSheenKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(face, kSheenKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addTargetsTo:control];
}

+ (void)applyRockerToFace:(UIView *)face left:(UIControl *)left right:(UIControl *)right radius:(CGFloat)radius {
    [self applyToFace:face control:left radius:radius strength:1.0];
    [self applyToFace:face control:right radius:radius strength:1.0];
    objc_setAssociatedObject(left, kSideKey, @(-1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(right, kSideKey, @(1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// inclinazione del bilanciere: rotazione attorno all'asse verticale con prospettiva (il lato premuto "affonda")
static CATransform3D SFRockerTransform(NSInteger side) {
    CATransform3D t = CATransform3DIdentity; t.m34 = -1.0 / 420.0;
    t = CATransform3DRotate(t, side * 9.0 * M_PI / 180.0, 0, 1, 0);
    return CATransform3DTranslate(t, 0, 0.6, 0);
}

+ (void)addTargetsTo:(UIControl *)control {
    SFTactile *t = [self shared];
    [control addTarget:t action:@selector(down:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [control addTarget:t action:@selector(up:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside
                                                               | UIControlEventTouchCancel | UIControlEventTouchDragExit];
}

- (void)down:(UIControl *)c {
    UIView *face = objc_getAssociatedObject(c, kFaceKey);
    CAGradientLayer *g = objc_getAssociatedObject(c, kSheenKey);
    if (!face) return;
    NSInteger side = [objc_getAssociatedObject(c, kSideKey) integerValue];
    [UIView animateWithDuration:0.06 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         if (side) face.layer.transform = SFRockerTransform(side);
                         else face.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 1.0), 0.96, 0.96);
                     } completion:nil];
    [CATransaction begin]; [CATransaction setAnimationDuration:0.06];
    if (g) { face.layer.shadowOffset = CGSizeMake(0, 0.4); face.layer.shadowRadius = 0.8; g.opacity = 0.35; }                                     // il riflesso si spegne: tasto "schiacciato"
    [CATransaction commit];
}

- (void)up:(UIControl *)c {
    UIView *face = objc_getAssociatedObject(c, kFaceKey);
    CAGradientLayer *g = objc_getAssociatedObject(c, kSheenKey);
    if (!face) return;
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ face.layer.transform = CATransform3DIdentity; } completion:nil];
    [CATransaction begin]; [CATransaction setAnimationDuration:0.16];
    if (g) { face.layer.shadowOffset = CGSizeMake(0, 1.8); face.layer.shadowRadius = 1.6; g.opacity = 1.0; }
    [CATransaction commit];
}

@end
