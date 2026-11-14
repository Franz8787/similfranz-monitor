#import "TraceView.h"

static const int kSubsamples = 3;     // sottocampioni per pixel (non perdere i picchi QRS)
static const int kEraseGap   = 14;    // pixel cancellati davanti al cursore

@implementation TraceView {
    float *_values;          // un valore per colonna (NAN = vuoto)
    uint8_t *_marks;         // marcatori per colonna
    uint8_t *_dash;          // colonna disegnata tratteggiata (sensore staccato quando il cursore ci è passato)
    NSTimeInterval _edgeT;   // istante dell'ultimo stacco / riattacco
    int _edgeKind;           // 0 nessuno, 1 stacco, 2 riattacco
    uint32_t _rng;
    int _width;
    int _cursor;
    NSTimeInterval _lastT;
    NSTimeInterval _lastScaleCheck;
    double _fraction;
    BOOL _hasTime;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES;
        self.backgroundColor = [UIColor blackColor];
        self.contentMode = UIViewContentModeRedraw;
        _traceColor = [UIColor greenColor];
        _minValue = -1; _maxValue = 1; _sweepSpeed = 100;
    }
    return self;
}

- (void)dealloc { free(_values); free(_marks); free(_dash); }
- (double)noise { _rng = _rng * 1664525u + 1013904223u; return ((_rng >> 8) / 8388608.0) - 1.0; }

- (void)ensureBuffer {
    int w = (int)floor(self.bounds.size.width);
    if (w == _width && _values) return;
    free(_values); free(_marks); free(_dash);
    _width = MAX(w, 1);
    _values = malloc(sizeof(float) * (size_t)_width);
    _marks = calloc((size_t)_width, 1);
    _dash = calloc((size_t)_width, 1);
    for (int i = 0; i < _width; i++) _values[i] = NAN;
    _cursor = 0;
}

- (void)layoutSubviews { [super layoutSubviews]; [self ensureBuffer]; }

- (void)resetAtTime:(NSTimeInterval)t {
    [self ensureBuffer];
    for (int i = 0; i < _width; i++) { _values[i] = NAN; _marks[i] = 0; _dash[i] = 0; }
    _cursor = 0; _lastT = t; _fraction = 0; _hasTime = YES; _edgeKind = 0;
    [self setNeedsDisplay];
}

- (void)setDisconnected:(BOOL)d {
    if (d == _disconnected) return;
    _disconnected = d;
    [self ensureBuffer];
    // come un monitor vero: niente cancellazione, il cursore prosegue e sovrascrive (onda vecchia visibile a destra)
    _edgeT = _lastT; _edgeKind = self.edgeArtifacts ? (d ? 1 : 2) : 0;
    if (!_rng) _rng = (uint32_t)(arc4random() | 1);
    [self setNeedsDisplay];
}

- (BOOL)advanceTo:(NSTimeInterval)t {
    [self ensureBuffer];
    if (!_hasTime) { _lastT = t; _hasTime = YES; return NO; }
    double dt = t - _lastT;
    if (dt <= 0) return NO;
    if (dt > 1.0) { _lastT = t - 1.0; dt = 1.0; }   // dopo una pausa lunga non recuperare tutto
    double px = dt * self.sweepSpeed + _fraction;
    int n = (int)floor(px);
    _fraction = px - n;
    if (n <= 0) return NO;
    double secPerPx = 1.0 / self.sweepSpeed;
    NSTimeInterval tPix = _lastT;
    int startCursor = _cursor;
    for (int i = 0; i < n; i++) {
        // tra i sottocampioni tengo quello più lontano dalla linea di base (picchi visibili)
        double best = 0; double bestAbs = -1;
        for (int k = 1; k <= kSubsamples; k++) {
            double v = self.sampler ? self.sampler(tPix + secPerPx * k / kSubsamples) : 0;
            if (fabs(v) > bestAbs) { bestAbs = fabs(v); best = v; }
        }
        _marks[_cursor] = (self.markerSampler && !_disconnected) ? (uint8_t)self.markerSampler(tPix, tPix + secPerPx) : 0;
        tPix += secPerPx;
        double range = self.maxValue - self.minValue, de = tPix - _edgeT;
        BOOL dash = NO;
        if (_disconnected) {
            if (_edgeKind == 1 && de < 0.45) {          // elettrodo che si stacca: scatto al bordo, poi ricade
                double a = de < 0.10 ? 1.0 : exp(-(de - 0.10) / 0.07);
                best = self.baselineValue + range * 0.92 * a + range * 0.03 * [self noise];
            } else { best = self.baselineValue; dash = YES; }
        } else if (_edgeKind == 2 && de < 1.8) {        // riattacco: linea di base che oscilla e si assesta
            best += range * (-0.45 * exp(-de / 0.35) * cos(de * 5.0)) + range * 0.06 * exp(-de / 0.6) * [self noise];
        }
        _values[_cursor] = (float)best;
        _dash[_cursor] = dash;
        _cursor = (_cursor + 1) % _width;
        for (int g = 0; g < kEraseGap; g++) { _values[(_cursor + g) % _width] = NAN; _marks[(_cursor + g) % _width] = 0; _dash[(_cursor + g) % _width] = 0; }
    }
    _lastT = tPix;
    if (self.autoScale && !_disconnected && t - _lastScaleCheck > 0.5) { _lastScaleCheck = t; [self rescaleIfNeeded]; }
    // Ridisegno PARZIALE: solo le colonne cambiate (nuovi campioni + fascia cancellata).
    // Il backing store del layer conserva il resto: ~95% di pixel in meno per frame (A5).
    int count = MIN(_width, n + kEraseGap + 2);
    int from = (startCursor - 1 + _width) % _width;
    [self invalidateColumnsFrom:from count:count];
    return YES;
}

- (void)invalidateColumnsFrom:(int)from count:(int)count {
    CGFloat h = self.bounds.size.height, pad = 7;   // margine: i triangoli sync sono larghi 10 px
    if (from + count <= _width) {
        [self setNeedsDisplayInRect:CGRectMake(from - pad, 0, count + 2 * pad, h)];
    } else {
        int first = _width - from;
        [self setNeedsDisplayInRect:CGRectMake(from - pad, 0, first + 2 * pad, h)];
        [self setNeedsDisplayInRect:CGRectMake(-pad, 0, count - first + 2 * pad, h)];
    }
}

// Riadatta la scala ai valori visibili (ultimo giro di sweep) quando escono dalla scala
// o la occupano troppo poco: i valori sono memorizzati grezzi, quindi basta ridisegnare.
- (void)rescaleIfNeeded {
    double mn = INFINITY, mx = -INFINITY;
    for (int i = 0; i < _width; i++) { float v = _values[i]; if (!isnan(v) && !_dash[i]) { mn = MIN(mn, v); mx = MAX(mx, v); } }
    if (!isfinite(mn) || !isfinite(mx)) return;
    if (self.autoScale == 3) {
        double lo = floor((mn - 12) / 10.0) * 10.0, hi = ceil((mx + 12) / 10.0) * 10.0;
        lo = MAX(0, lo); if (hi - lo < 40) hi = lo + 40;
        // cambia scala solo se serve davvero (onda fuori scala o troppo schiacciata): niente "saltellamenti"
        BOOL out = mx > self.maxValue || mn < self.minValue;
        BOOL loose = (mx - mn) < (self.maxValue - self.minValue) * 0.45;
        if (out || loose || self.minValue == 0) {
            if (lo != _minValue || hi != _maxValue) { _minValue = lo; _maxValue = hi; [self setNeedsDisplay]; }
        }
        return;
    }
    if (self.autoScale == 2) {
        static const double scales[] = {100, 150, 200, 250, 300};
        double top = 300;
        for (int i = 0; i < 5; i++) if (mx <= scales[i] * 0.92) { top = scales[i]; break; }
        if (top != self.maxValue || self.minValue != 0) { _minValue = 0; self.maxValue = top; [self setNeedsDisplay]; }
        return;
    }
    double span = MAX(mx - mn, self.minSpan > 0 ? self.minSpan : 0.1);
    double cur = self.maxValue - self.minValue;
    BOOL outOfRange = mx > self.maxValue || mn < self.minValue;
    BOOL tooSmall = span < cur * 0.55;                       // tracciato troppo schiacciato
    if (outOfRange || tooSmall) {
        double pad = span * 0.12;
        _minValue = mn - pad; _maxValue = mn - pad + span + 2 * pad;
        [self setNeedsDisplay];
    }
}

// Cambio di scala (es. ART): ridisegno completo, solo se il valore cambia davvero.
- (void)setMaxValue:(double)v { if (v != _maxValue) { _maxValue = v; [self setNeedsDisplay]; } }

// Le scritte sovrapposte cambiano raramente: in quel caso ridisegno tutto.
- (void)setFlatWhenNoSignal:(BOOL)v { if (v != _flatWhenNoSignal) { _flatWhenNoSignal = v; [self setNeedsDisplay]; } }
- (void)setNoSignalText:(NSString *)t {
    if ((t == nil && _noSignalText == nil) || [t isEqualToString:_noSignalText]) return;
    _noSignalText = [t copy]; [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    [[UIColor blackColor] setFill];
    CGContextFillRect(ctx, rect);

    // etichetta del canale (solo se l'area da ridisegnare la tocca)
    if (self.label.length && CGRectIntersectsRect(rect, CGRectMake(0, 0, 140, 20))) {
        [self.label drawAtPoint:CGPointMake(6, 2)
                 withAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:13],
                                  NSForegroundColorAttributeName: self.traceColor}];
    }
    if (!_values) return;

    double range = self.maxValue - self.minValue;
    if (range <= 0) range = 1;
    CGFloat top = 18, h = b.size.height - top - 4;

    // riempimento sotto la curva: una colonna verticale per pixel, dalla linea di base al valore
    if (self.filled && !_disconnected) {
        CGFloat yBase = top + h * (CGFloat)(1.0 - MAX(-0.05, MIN(1.05, (self.baselineValue - self.minValue) / range)));
        CGContextSetStrokeColorWithColor(ctx, [self.traceColor colorWithAlphaComponent:0.45].CGColor);
        CGContextSetLineWidth(ctx, 1.0);
        int fx0 = MAX(0, (int)floor(CGRectGetMinX(rect)) - 2), fx1 = MIN(_width, (int)ceil(CGRectGetMaxX(rect)) + 2);
        for (int x = fx0; x < fx1; x++) {
            float v = _values[x];
            if (isnan(v) || _dash[x]) continue;
            CGFloat yv = top + h * (CGFloat)(1.0 - MAX(-0.05, MIN(1.05, (v - self.minValue) / range)));
            if (yBase - yv < 1) continue;
            CGContextMoveToPoint(ctx, x + 0.5, yBase); CGContextAddLineToPoint(ctx, x + 0.5, yv);
        }
        CGContextStrokePath(ctx);
    }

    CGContextSetStrokeColorWithColor(ctx, self.traceColor.CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    int xs0 = MAX(0, (int)floor(CGRectGetMinX(rect)) - 2);
    // sensore scollegato: il tracciato continua a scorrere ma TRATTEGGIATO (9 px pieni, 7 vuoti),
    // con i tratti ancorati alla x assoluta: allineati anche nei ridisegni parziali
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    BOOL penDown = NO;
    int x0 = xs0;
    int x1 = MIN(_width, (int)ceil(CGRectGetMaxX(rect)) + 2);
    for (int x = x0; x < x1; x++) {
        float v = _values[x];
        if (isnan(v) || (_dash[x] && (x % 16) >= 9)) { penDown = NO; continue; }
        if (x > 0 && _dash[x] != _dash[x - 1]) penDown = NO;
        double norm = (v - self.minValue) / range;
        norm = MAX(-0.05, MIN(1.05, norm));
        CGFloat y = top + h * (CGFloat)(1.0 - norm);
        if (!penDown) { CGContextMoveToPoint(ctx, x, y); penDown = YES; }
        else CGContextAddLineToPoint(ctx, x, y);
    }
    CGContextStrokePath(ctx);

    // marcatori: spike del pacemaker (linea verticale) e sync (triangolo bianco sopra l'onda R)
    if (_marks) {
        for (int x = x0; x < x1; x++) {
            uint8_t m = _marks[x];
            if (!m) continue;
            if (m & 2) {
                CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
                CGContextSetLineWidth(ctx, 1.5);
                CGContextMoveToPoint(ctx, x + 0.5, top + h * 0.25); CGContextAddLineToPoint(ctx, x + 0.5, top + h * 0.80);
                CGContextStrokePath(ctx);
            }
            if (m & 1) {
                [[UIColor whiteColor] setFill];
                CGFloat my = top + self.markerYOffset;
                CGContextMoveToPoint(ctx, x - 5, my - 14); CGContextAddLineToPoint(ctx, x + 5, my - 14);
                CGContextAddLineToPoint(ctx, x, my - 5); CGContextClosePath(ctx); CGContextFillPath(ctx);
            }
        }
    }

    if (self.showScaleLabels && !_disconnected) {
        NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:11], NSForegroundColorAttributeName: [self.traceColor colorWithAlphaComponent:0.7]};
        // il margine sotto lo zero (es. -1 per staccare la linea di base dal bordo) si scrive come 0
        double loV = (self.minValue < 0 && self.minValue > -5) ? 0 : self.minValue;
        NSString *hiS = [NSString stringWithFormat:@"%.0f", self.maxValue], *loS = [NSString stringWithFormat:@"%.0f", loV];
        CGFloat yHi = top, yLo = top + h;
        CGRect rHi = CGRectMake(b.size.width - 34, yHi - 1, 32, 13), rLo = CGRectMake(b.size.width - 34, yLo - 13, 32, 13);
        // linee tratteggiate sottili ai bordi della scala
        CGFloat d[] = {3, 5};
        CGContextSetStrokeColorWithColor(ctx, [self.traceColor colorWithAlphaComponent:0.25].CGColor);
        CGContextSetLineWidth(ctx, 1); CGContextSetLineDash(ctx, 0, d, 2);
        CGContextMoveToPoint(ctx, MAX(x0, 0), yHi); CGContextAddLineToPoint(ctx, MIN(x1, b.size.width - 38), yHi);
        CGContextMoveToPoint(ctx, MAX(x0, 0), yLo); CGContextAddLineToPoint(ctx, MIN(x1, b.size.width - 38), yLo);
        CGContextStrokePath(ctx); CGContextSetLineDash(ctx, 0, NULL, 0);
        if (CGRectIntersectsRect(rect, rHi)) [hiS drawInRect:rHi withAttributes:a];
        if (CGRectIntersectsRect(rect, rLo)) [loS drawInRect:rLo withAttributes:a];
    }

    if (_disconnected && self.noSignalText.length) {
        NSDictionary *a = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:15], NSForegroundColorAttributeName: self.traceColor};
        CGSize sz = [self.noSignalText sizeWithAttributes:a];
        CGRect tr = CGRectMake((b.size.width - sz.width) / 2, top + 4, sz.width, sz.height);
        if (CGRectIntersectsRect(rect, CGRectInset(tr, -10, -4))) {
            [[UIColor blackColor] setFill];
            CGContextFillRect(ctx, CGRectInset(tr, -8, -2));
            [self.noSignalText drawAtPoint:tr.origin withAttributes:a];
        }
        return;
    }

    if (self.flatWhenNoSignal && self.noSignalText.length) {
        NSDictionary *a = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:16],
                            NSForegroundColorAttributeName: self.traceColor};
        CGSize s = [self.noSignalText sizeWithAttributes:a];
        [self.noSignalText drawAtPoint:CGPointMake((b.size.width - s.width) / 2, top + 8) withAttributes:a];
    }
}
@end
