// SimulaFranz_Monitor — variabilità fisiologica dei numerici nei layout dei dispositivi (come GENERIC ICU):
// piccola deriva casuale limitata, aggiornata ogni ~2 s, uguale per tutti i riquadri che mostrano lo stesso parametro.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

static inline double SFJitterOffset(NSString *key, double lim) {
    static NSMutableDictionary<NSString *, NSArray *> *st;
    if (!st) st = [NSMutableDictionary dictionary];
    NSTimeInterval now = CACurrentMediaTime();
    NSArray *e = st[key];
    double v = e ? [e[0] doubleValue] : 0; NSTimeInterval at = e ? [e[1] doubleValue] : 0;
    if (now - at >= 2.0) {
        v += ((double)arc4random_uniform(1001) / 1000.0 - 0.5) * lim * 0.9;
        v = MAX(-lim, MIN(lim, v * 0.85));
        st[key] = @[@(v), @(now)];
    }
    return v;
}
// valore mostrato = valore impostato + deriva (mai sotto 0; SpO2 mai sopra 100)
static inline NSInteger SFJ(NSString *key, NSInteger value, double lim) {
    if (value <= 0) return value;
    NSInteger r = MAX(0, value + lround(SFJitterOffset(key, lim)));
    return [key isEqualToString:@"spo2"] ? MIN(100, r) : r;
}
