// SimulaFranz_Monitor — tasti "fisici" dei layout dei dispositivi (non GENERIC ICU):
// rilievo lieve (riflesso dall'alto + ombra corta) e animazione di pressione (il tasto scende di 1 pt,
// si stringe del 4 %, l'ombra si accorcia; al rilascio torna su con un piccolo rimbalzo).
#import <UIKit/UIKit.h>

@interface SFTactile : NSObject
// face: la parte visibile del tasto (può coincidere con control); control: chi riceve i tocchi.
// radius: raggio degli angoli della faccia. strength: intensità del rilievo (1 = normale; 0 = solo animazione di pressione).
+ (void)applyToFace:(UIView *)face control:(UIControl *)control radius:(CGFloat)radius strength:(CGFloat)strength;
+ (void)applyToButton:(UIButton *)button;                    // faccia = pulsante stesso
// tasto a bilanciere (es. ▼ ENERGY SELECT ▲): la faccia si inclina verso il lato premuto
+ (void)applyRockerToFace:(UIView *)face left:(UIControl *)left right:(UIControl *)right radius:(CGFloat)radius;
@end
