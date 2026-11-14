// similFranz Pocket — la ROTELLA: si gira con il pollice (orario = più, antiorario = meno), a scatti con un clic udibile.
// Piano = un'unità per scatto; veloce = salti più grandi (x2, x5). Intorno, l'arco del valore nel suo intervallo:
// pallino bianco = valore scelto, tacca chiara = valore attuale del paziente. Al centro il valore grande.
#import <UIKit/UIKit.h>

@interface PkDial : UIView
- (void)configureTitle:(NSString *)title unit:(NSString *)unit color:(UIColor *)color
                   min:(double)min max:(double)max step:(double)step decimals:(NSInteger)decimals;
@property (nonatomic, readonly) double value;           // valore scelto
@property (nonatomic, readonly) BOOL turning;           // il dito è sulla rotella
@property (nonatomic, copy) void (^onChange)(double value, BOOL final);   // final = dito sollevato
@property (nonatomic, copy) void (^onCenterTap)(void);  // tocco al centro senza girare
- (void)showValue:(double)value current:(double)current note:(NSString *)note;   // dal modello (ignorato mentre si gira)
- (void)debugTurn:(NSInteger)steps;                     // verifica da Mac: come girare di N scatti e sollevare
@end

void PkClick(void);     // clic breve (l'iPod non vibra): anche per i tasti
