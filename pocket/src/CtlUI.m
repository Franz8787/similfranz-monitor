#import "CtlUI.h"
#import <QuartzCore/QuartzCore.h>
#import "SFLog.h"
BOOL CtlFitLog = NO;      // diagnosi: scrive nel log come è stato adattato il testo di ogni pulsante

UIView *CtlCard(CGRect frame) {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor = CTL_CARD; v.layer.cornerRadius = 12;
    return v;
}
UILabel *CtlLabel(CGRect frame, NSString *text, CGFloat size, BOOL bold, UIColor *color) {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text; l.textColor = color; l.backgroundColor = [UIColor clearColor];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    return l;
}
UIFont *CtlDigits(CGFloat size, BOOL bold) {
    return [UIFont monospacedDigitSystemFontOfSize:size weight:bold ? UIFontWeightBold : UIFontWeightRegular];
}

@implementation CtlScrollView
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.delaysContentTouches = NO; self.canCancelContentTouches = YES; } return self; }
- (BOOL)touchesShouldCancelInContentView:(UIView *)view { return ![view isKindOfClass:[UISlider class]]; }     // se il dito si muove vince lo scorrimento, anche sopra un pulsante
@end

#pragma mark - Icone

UIImage *CtlIcon(NSString *name, CGFloat S, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(S, S), NO, 0);
    CGContextRef g = UIGraphicsGetCurrentContext();
    [color setStroke]; [color setFill];
    CGFloat u = S / 24.0;                       // disegnate su una griglia 24x24
    CGContextSetLineWidth(g, 2 * u); CGContextSetLineCap(g, kCGLineCapRound); CGContextSetLineJoin(g, kCGLineJoinRound);
#define PT(x, y) CGPointMake((x) * u, (y) * u)
    UIBezierPath *p = [UIBezierPath bezierPath]; p.lineWidth = 2 * u; p.lineCapStyle = kCGLineCapRound; p.lineJoinStyle = kCGLineJoinRound;
    if ([name isEqualToString:@"pause"]) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6 * u, 5 * u, 4 * u, 14 * u) cornerRadius:1.2 * u] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(14 * u, 5 * u, 4 * u, 14 * u) cornerRadius:1.2 * u] fill];
    } else if ([name isEqualToString:@"play"] || [name isEqualToString:@"next"]) {
        [p moveToPoint:PT(7, 5)]; [p addLineToPoint:PT(19, 12)]; [p addLineToPoint:PT(7, 19)]; [p closePath]; [p fill]; [p stroke];
    } else if ([name isEqualToString:@"stop"]) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6 * u, 6 * u, 12 * u, 12 * u) cornerRadius:2 * u] fill];
    } else if ([name hasPrefix:@"bell"]) {
        [p moveToPoint:PT(5, 17)]; [p addCurveToPoint:PT(7, 10) controlPoint1:PT(7, 15.5) controlPoint2:PT(7, 13)];
        [p addCurveToPoint:PT(12, 5) controlPoint1:PT(7, 7) controlPoint2:PT(9.2, 5)];
        [p addCurveToPoint:PT(17, 10) controlPoint1:PT(14.8, 5) controlPoint2:PT(17, 7)];
        [p addCurveToPoint:PT(19, 17) controlPoint1:PT(17, 13) controlPoint2:PT(17, 15.5)]; [p closePath]; [p stroke];
        UIBezierPath *c = [UIBezierPath bezierPath]; c.lineWidth = 2 * u; c.lineCapStyle = kCGLineCapRound;
        [c moveToPoint:PT(10.3, 20)]; [c addQuadCurveToPoint:PT(13.7, 20) controlPoint:PT(12, 21.6)]; [c stroke];
        if ([name hasSuffix:@"slash"]) { UIBezierPath *l = [UIBezierPath bezierPath]; l.lineWidth = 2 * u; l.lineCapStyle = kCGLineCapRound; [l moveToPoint:PT(4.5, 4.5)]; [l addLineToPoint:PT(19.5, 20.5)]; [l stroke]; }
    } else if ([name isEqualToString:@"gauge"]) {            // manometro: misura della pressione
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(4 * u, 4 * u, 16 * u, 16 * u)] stroke];
        [p moveToPoint:PT(12, 12)]; [p addLineToPoint:PT(16, 8.5)]; [p stroke];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10.6 * u, 10.6 * u, 2.8 * u, 2.8 * u)] fill];
        for (int k = 0; k < 5; k++) { double a = M_PI * (1.0 + k / 4.0); UIBezierPath *t = [UIBezierPath bezierPath]; t.lineWidth = 1.4 * u; t.lineCapStyle = kCGLineCapRound;
            [t moveToPoint:PT(12 + 6.2 * cos(a), 12 + 6.2 * sin(a))]; [t addLineToPoint:PT(12 + 5 * cos(a), 12 + 5 * sin(a))]; [t stroke]; }
    } else if ([name isEqualToString:@"cpr"]) {              // cuore con le compressioni
        [p moveToPoint:PT(12, 20)]; [p addCurveToPoint:PT(4, 10.5) controlPoint1:PT(8, 17) controlPoint2:PT(4, 14)];
        [p addCurveToPoint:PT(12, 8.5) controlPoint1:PT(4, 6.2) controlPoint2:PT(10, 5.2)];
        [p addCurveToPoint:PT(20, 10.5) controlPoint1:PT(14, 5.2) controlPoint2:PT(20, 6.2)];
        [p addCurveToPoint:PT(12, 20) controlPoint1:PT(20, 14) controlPoint2:PT(16, 17)]; [p closePath]; [p stroke];
        UIBezierPath *e = [UIBezierPath bezierPath]; e.lineWidth = 1.6 * u; e.lineCapStyle = kCGLineCapRound; e.lineJoinStyle = kCGLineJoinRound;
        [e moveToPoint:PT(7, 12.5)]; [e addLineToPoint:PT(10, 12.5)]; [e addLineToPoint:PT(11.2, 10.2)]; [e addLineToPoint:PT(12.8, 15)]; [e addLineToPoint:PT(14, 12.5)]; [e addLineToPoint:PT(17, 12.5)]; [e stroke];
    } else if ([name isEqualToString:@"tap"]) {              // tocco: punto con due onde
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9.5 * u, 9.5 * u, 5 * u, 5 * u)] fill];
        UIBezierPath *r1 = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(6 * u, 6 * u, 12 * u, 12 * u)]; r1.lineWidth = 1.6 * u; [r1 stroke];
        CGContextSetAlpha(g, 0.5);
        UIBezierPath *r2 = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(2.6 * u, 2.6 * u, 18.8 * u, 18.8 * u)]; r2.lineWidth = 1.4 * u; [r2 stroke];
    } else if ([name isEqualToString:@"monitor"]) {          // schermo con una traccia
        UIBezierPath *r = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3 * u, 5 * u, 18 * u, 13 * u) cornerRadius:2.4 * u]; r.lineWidth = 2 * u; [r stroke];
        UIBezierPath *e = [UIBezierPath bezierPath]; e.lineWidth = 1.5 * u; e.lineCapStyle = kCGLineCapRound; e.lineJoinStyle = kCGLineJoinRound;
        [e moveToPoint:PT(6, 12)]; [e addLineToPoint:PT(9.5, 12)]; [e addLineToPoint:PT(11, 8.5)]; [e addLineToPoint:PT(13, 15)]; [e addLineToPoint:PT(14.3, 12)]; [e addLineToPoint:PT(18, 12)]; [e stroke];
    } else if ([name isEqualToString:@"lungs"]) {            // polmoni: trachea e due lobi
        [p moveToPoint:PT(12, 4)]; [p addLineToPoint:PT(12, 11)]; [p moveToPoint:PT(12, 10)]; [p addLineToPoint:PT(9.5, 12.5)]; [p moveToPoint:PT(12, 10)]; [p addLineToPoint:PT(14.5, 12.5)]; [p stroke];
        UIBezierPath *l = [UIBezierPath bezierPath]; l.lineWidth = 1.8 * u; l.lineJoinStyle = kCGLineJoinRound;
        [l moveToPoint:PT(9.5, 8)]; [l addCurveToPoint:PT(4, 19) controlPoint1:PT(6, 9) controlPoint2:PT(3.5, 14)];
        [l addCurveToPoint:PT(9.5, 18) controlPoint1:PT(5, 20.5) controlPoint2:PT(8, 20)]; [l closePath]; [l stroke];
        UIBezierPath *r = [UIBezierPath bezierPath]; r.lineWidth = 1.8 * u; r.lineJoinStyle = kCGLineJoinRound;
        [r moveToPoint:PT(14.5, 8)]; [r addCurveToPoint:PT(20, 19) controlPoint1:PT(18, 9) controlPoint2:PT(20.5, 14)];
        [r addCurveToPoint:PT(14.5, 18) controlPoint1:PT(19, 20.5) controlPoint2:PT(16, 20)]; [r closePath]; [r stroke];
    } else if ([name isEqualToString:@"plus"]) {
        [p moveToPoint:PT(12, 5)]; [p addLineToPoint:PT(12, 19)]; [p moveToPoint:PT(5, 12)]; [p addLineToPoint:PT(19, 12)]; [p stroke];
    } else if ([name isEqualToString:@"trash"]) {
        [p moveToPoint:PT(5, 7)]; [p addLineToPoint:PT(19, 7)]; [p moveToPoint:PT(9.5, 7)]; [p addLineToPoint:PT(10.3, 4.5)]; [p addLineToPoint:PT(13.7, 4.5)]; [p addLineToPoint:PT(14.5, 7)];
        [p moveToPoint:PT(7, 7)]; [p addLineToPoint:PT(8, 20)]; [p addLineToPoint:PT(16, 20)]; [p addLineToPoint:PT(17, 7)]; [p stroke];
    }
#undef PT
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Pulsante

@implementation CtlButton { CtlButtonStyle _style; UIColor *_color; UIFont *_base, *_applied; NSString *_icon; BOOL _iconAbove, _styled; UIImageView *_iconView; UIColor *_iconInk; }

+ (instancetype)buttonWithTitle:(NSString *)title style:(CtlButtonStyle)style color:(UIColor *)color frame:(CGRect)frame target:(id)target action:(SEL)action {
    CtlButton *b = [CtlButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    b.maxLines = 2; b.titleLabel.textAlignment = NSTextAlignmentCenter; b.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    b.layer.cornerRadius = 10;
    [b setStyle:style color:color];
    if (target && action) [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [b addTarget:b action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)fire { if (self.onTap) self.onTap(); }
- (UIColor *)inkColor { return _style == CtlButtonFilled ? [UIColor whiteColor] : (_style == CtlButtonTinted ? _color : CTL_INK); }
- (void)setStyle:(CtlButtonStyle)style color:(UIColor *)color {
    UIColor *c = color ?: CTL_TINT;
    if (_styled && style == _style && [c isEqual:_color]) return;       // chiamato a ogni aggiornamento: niente lavoro se non cambia nulla
    _styled = YES;
    _style = style; _color = c;
    switch (style) {
        case CtlButtonFilled: self.backgroundColor = _color; break;
        case CtlButtonTinted: self.backgroundColor = [_color colorWithAlphaComponent:0.18]; break;
        case CtlButtonQuiet:  self.backgroundColor = CTL_CARD2; break;
    }
    [self setTitleColor:[self inkColor] forState:UIControlStateNormal];
    [self setTitleColor:CTL_INK3 forState:UIControlStateDisabled];
    if (_icon) [self setIcon:_icon above:_iconAbove];       // l'icona segue il colore del testo
}
- (void)setIcon:(NSString *)name above:(BOOL)above {
    UIColor *ink = [self inkColor];
    if (_iconView && [name isEqualToString:_icon] && above == _iconAbove && [ink isEqual:_iconInk]) return;
    _iconInk = ink;
    _icon = [name copy]; _iconAbove = above;
    if (!_iconView) { _iconView = [[UIImageView alloc] init]; _iconView.userInteractionEnabled = NO; [self addSubview:_iconView]; }
    _iconView.image = name ? CtlIcon(name, above ? 24 : 20, [self inkColor]) : nil;
    _iconView.hidden = name == nil;
    [self setNeedsLayout];
}
- (void)setTitle:(NSString *)t forState:(UIControlState)s { [super setTitle:t forState:s]; _applied = nil; [self setNeedsLayout]; }

// Il testo deve stare nel pulsante SENZA puntini e SENZA parole spezzate o lettere orfane:
// si riduce il carattere finché ogni riga (o ogni parola, se va a capo) entra nello spazio disponibile.
- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *l = self.titleLabel; NSString *t = [self titleForState:UIControlStateNormal] ?: @"";
    if (!_applied || ![l.font isEqual:_applied]) _base = l.font;            // carattere scelto da chi ha creato il pulsante
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    BOOL icon = _icon != nil;
    CGFloat isz = _iconAbove ? 24 : 20;
    CGRect area = CGRectInset(self.bounds, 8, 4);
    if (icon && _iconAbove) area = CGRectMake(6, 6 + isz + 2, W - 12, H - 12 - isz - 2);
    else if (icon) area = CGRectMake(10 + isz + 6, 4, W - 10 - isz - 6 - 8, H - 8);
    NSInteger maxLines = (icon && _iconAbove) ? 1 : MAX(1, self.maxLines);     // (UIButton su iOS 9 riporta a 1 il numberOfLines dell'etichetta: si tiene qui)
    l.numberOfLines = maxLines; l.lineBreakMode = NSLineBreakByWordWrapping;
    NSArray<NSString *> *explicit = [t componentsSeparatedByString:@"\n"];
    UIFont *f = _base; CGFloat size = _base.pointSize;
    for (; size >= 9; size -= 0.5) {
        f = [_base fontWithSize:size];
        NSDictionary *at = @{NSFontAttributeName: f};
        BOOL ok = YES;
        if (explicit.count > 1 || maxLines == 1) {           // righe decise da chi scrive: ognuna deve stare su una riga
            for (NSString *line in explicit) if (ceil([line sizeWithAttributes:at].width) > area.size.width) ok = NO;
            if (explicit.count * f.lineHeight > area.size.height + 1) ok = NO;
        } else {                                              // a capo libero: nessuna parola più larga del pulsante, al massimo maxLines righe
            for (NSString *w in [t componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) if (ceil([w sizeWithAttributes:at].width) > area.size.width) ok = NO;
            CGRect r = [t boundingRectWithSize:CGSizeMake(area.size.width, 1000) options:NSStringDrawingUsesLineFragmentOrigin attributes:at context:nil];
            if (lround(r.size.height / f.lineHeight) > maxLines || r.size.height > area.size.height + 2) ok = NO;
        }
        if (ok) break;
    }
    if (CtlFitLog) SFLog(@"FIT «%@» base %.1f -> %.1f area %.0fx%.0f maxLines %ld", t, _base.pointSize, size, area.size.width, area.size.height, (long)maxLines);
    if (![l.font isEqual:f]) l.font = f;
    _applied = f;
    l.frame = area;
    if (icon) {
        CGSize ts = [t boundingRectWithSize:CGSizeMake(area.size.width, 1000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: f} context:nil].size;
        if (_iconAbove) {
            CGFloat total = isz + 3 + ceil(ts.height), y0 = floor((H - total) / 2);
            _iconView.frame = CGRectMake(floor((W - isz) / 2), y0, isz, isz);
            l.frame = CGRectMake(6, y0 + isz + 3, W - 12, ceil(ts.height));
        } else {
            CGFloat total = isz + 6 + ceil(ts.width), x0 = MAX(8, floor((W - total) / 2));
            _iconView.frame = CGRectMake(x0, floor((H - isz) / 2), isz, isz);
            l.frame = CGRectMake(x0 + isz + 6, 4, MIN(area.size.width, ceil(ts.width) + 2), H - 8);
        }
    }
}
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:h ? 0.05 : 0.25 animations:^{ self.alpha = h ? 0.55 : (self.enabled ? 1 : 0.45); self.transform = h ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity; }];
}
- (void)setEnabled:(BOOL)e { [super setEnabled:e]; self.alpha = e ? 1 : 0.45; }
@end

@implementation CtlParamRow {
    UILabel *_title, *_valueLabel, *_unit, *_note;
    UISlider *_slider; CtlButton *_minus, *_plus;
    double _min, _max, _step; NSInteger _dec; UIColor *_color;
    NSTimer *_repeat; double _repeatDir; int _holdTicks;
}

- (instancetype)initWithFrame:(CGRect)f title:(NSString *)title unit:(NSString *)unit color:(UIColor *)color
                          min:(double)min max:(double)max step:(double)step decimals:(NSInteger)decimals {
    if ((self = [super initWithFrame:f])) {
        _min = min; _max = max; _step = step; _dec = decimals; _color = color;
        CGFloat W = f.size.width;
        _title = CtlLabel(CGRectMake(0, 0, W - 190, 24), title, 17, YES, CTL_INK); [self addSubview:_title];
        _note = CtlLabel(CGRectMake(0, 24, W - 190, 18), @"", 13, NO, CTL_INK3); [self addSubview:_note];
        _valueLabel = CtlLabel(CGRectMake(W - 250, 0, 180, 50), @"--", 46, YES, color);
        _valueLabel.font = CtlDigits(46, YES); _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.adjustsFontSizeToFitWidth = YES; _valueLabel.minimumScaleFactor = 0.6;
        [self addSubview:_valueLabel];
        _unit = CtlLabel(CGRectMake(W - 64, 22, 64, 20), unit, 13, NO, CTL_INK2); [self addSubview:_unit];
        _minus = [CtlButton buttonWithTitle:@"−" style:CtlButtonQuiet color:nil frame:CGRectMake(0, 56, 52, 48) target:nil action:NULL];
        _plus  = [CtlButton buttonWithTitle:@"+" style:CtlButtonQuiet color:nil frame:CGRectMake(W - 52, 56, 52, 48) target:nil action:NULL];
        for (CtlButton *b in @[_minus, _plus]) {
            b.titleLabel.font = [UIFont systemFontOfSize:28];
            [b addTarget:self action:@selector(stepDown:) forControlEvents:UIControlEventTouchDown];
            [b addTarget:self action:@selector(stepUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [self addSubview:b];
        }
        _slider = [[UISlider alloc] initWithFrame:CGRectMake(64, 62, W - 128, 36)];
        _slider.minimumValue = (float)min; _slider.maximumValue = (float)max;
        _slider.minimumTrackTintColor = color; _slider.maximumTrackTintColor = CTL_CARD2;
        [_slider addTarget:self action:@selector(slid) forControlEvents:UIControlEventValueChanged];
        [_slider addTarget:self action:@selector(slideEnd) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self addSubview:_slider];
        _value = min;
    }
    return self;
}

- (void)setAccessibilityIdentifier:(NSString *)i {
    [super setAccessibilityIdentifier:i];
    _minus.accessibilityIdentifier = [i stringByAppendingString:@".meno"]; _plus.accessibilityIdentifier = [i stringByAppendingString:@".piu"];
}

- (double)snap:(double)v { v = round(v / _step) * _step; return MAX(_min, MIN(_max, v)); }
- (void)render:(BOOL)pending {
    _valueLabel.text = _dec > 0 ? [[NSString stringWithFormat:@"%.*f", (int)_dec, _value] stringByReplacingOccurrencesOfString:@"." withString:@","]
                                : [NSString stringWithFormat:@"%ld", (long)lround(_value)];
    _valueLabel.textColor = pending ? CTL_YELLOW : _color;
}
- (void)showValue:(double)v pending:(BOOL)pending {
    if (_dragging || _repeat) return;
    _value = [self snap:v]; _slider.value = (float)_value; [self render:pending];
}
- (void)setNote:(NSString *)note { _note.text = note ?: @""; }

- (void)slid { _dragging = YES; _value = [self snap:_slider.value]; [self render:YES]; if (self.onChange) self.onChange(_value, NO); }
- (void)slideEnd { _value = [self snap:_slider.value]; _slider.value = (float)_value; _dragging = NO; [self render:YES]; if (self.onChange) self.onChange(_value, YES); }

// − / +: un tocco = un passo; tenendo premuto i passi si ripetono (dopo mezzo secondo, poi più in fretta);
// al rilascio il valore diventa definitivo
- (void)stepDown:(UIButton *)b {
    _repeatDir = b == _minus ? -1 : 1; _holdTicks = 0;
    [self bump:1];
    [_repeat invalidate];
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.12 target:self selector:@selector(repeatTick) userInfo:nil repeats:YES];
}
- (void)repeatTick {
    _holdTicks++;
    if (_holdTicks > 4) [self bump:_holdTicks > 20 ? 5 : 1];
}
- (void)bump:(int)steps {
    _value = [self snap:_value + _repeatDir * _step * steps]; _slider.value = (float)_value; [self render:YES];
    if (self.onChange) self.onChange(_value, NO);
}
- (void)stepUp:(UIButton *)b {
    if (!_repeat) return;
    [_repeat invalidate]; _repeat = nil;
    [self render:YES];
    if (self.onChange) self.onChange(_value, YES);
}
// riga ricostruita mentre il dito tiene premuto: ferma la ripetizione e rende definitivo il valore
- (void)willMoveToWindow:(UIWindow *)w { if (!w && _repeat) [self stepUp:nil]; }
- (void)debugSet:(double)v { _value = [self snap:v]; _slider.value = (float)_value; [self render:YES]; if (self.onChange) self.onChange(_value, YES); }
@end
