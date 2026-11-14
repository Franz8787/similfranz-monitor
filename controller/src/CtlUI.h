// similFranz Controller — elementi comuni dell'interfaccia: colori, carte, pulsanti, riga di regolazione di un parametro.
#import <UIKit/UIKit.h>

static inline UIColor *CtlRGB(CGFloat r, CGFloat g, CGFloat b) { return [UIColor colorWithRed:r green:g blue:b alpha:1]; }
#define CTL_BG     CtlRGB(0.035, 0.045, 0.060)     // pagina
#define CTL_CARD   CtlRGB(0.085, 0.105, 0.135)     // carte
#define CTL_CARD2  CtlRGB(0.130, 0.155, 0.195)     // elementi in rilievo dentro le carte
#define CTL_LINE   [UIColor colorWithWhite:1 alpha:0.09]
#define CTL_INK    CtlRGB(0.94, 0.96, 0.98)
#define CTL_INK2   CtlRGB(0.66, 0.71, 0.77)
#define CTL_INK3   CtlRGB(0.45, 0.50, 0.56)
#define CTL_TINT   CtlRGB(0.04, 0.52, 1.00)        // azzurro di sistema: tutto ciò che si tocca
#define CTL_GREEN  CtlRGB(0.19, 0.82, 0.35)
#define CTL_RED    CtlRGB(1.00, 0.27, 0.23)
#define CTL_ORANGE CtlRGB(1.00, 0.62, 0.04)
#define CTL_YELLOW CtlRGB(1.00, 0.84, 0.04)
// colori dei parametri = convenzioni dei monitor
#define CTL_HR     CtlRGB(0.24, 0.92, 0.45)
#define CTL_BP     CtlRGB(1.00, 0.36, 0.32)
#define CTL_SPO2   CtlRGB(0.24, 0.84, 1.00)
#define CTL_CO2    CtlRGB(0.95, 0.88, 0.35)
#define CTL_TEMP   CtlRGB(0.80, 0.64, 1.00)

UIView *CtlCard(CGRect frame);
UILabel *CtlLabel(CGRect frame, NSString *text, CGFloat size, BOOL bold, UIColor *color);
UIFont *CtlDigits(CGFloat size, BOOL bold);            // cifre a larghezza fissa (i numeri non "ballano")

// Elenco che scorre anche partendo con il dito sopra un pulsante (di norma un pulsante "trattiene" il tocco).
@interface CtlScrollView : UIScrollView
@end

typedef NS_ENUM(NSInteger, CtlButtonStyle) { CtlButtonFilled, CtlButtonTinted, CtlButtonQuiet };

// Pulsante con risposta al tocco (si abbassa di tono mentre è premuto) e tre stili.
@interface CtlButton : UIButton
+ (instancetype)buttonWithTitle:(NSString *)title style:(CtlButtonStyle)style color:(UIColor *)color frame:(CGRect)frame
                         target:(id)target action:(SEL)action;
- (void)setStyle:(CtlButtonStyle)style color:(UIColor *)color;
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic) NSInteger maxLines;      // righe ammesse per il testo (default 2)
// Icona disegnata (nessuna emoji): nome fra quelli di CtlIcon. sopra = YES: icona sopra il testo; NO: a sinistra.
- (void)setIcon:(NSString *)name above:(BOOL)above;
@end

// Icone vettoriali monocromatiche: pause, play, bell, bell.slash, gauge (NIBP), cpr, lungs, tap, monitor, plus, next, stop, trash
UIImage *CtlIcon(NSString *name, CGFloat size, UIColor *color);

// Riga di regolazione: titolo, valore grande, cursore con − e + ai lati.
// onChange(valore, definitivo): definitivo = NO mentre si trascina, YES al rilascio o con − / +.
@interface CtlParamRow : UIView
- (instancetype)initWithFrame:(CGRect)frame title:(NSString *)title unit:(NSString *)unit color:(UIColor *)color
                          min:(double)min max:(double)max step:(double)step decimals:(NSInteger)decimals;
@property (nonatomic, readonly) double value;
@property (nonatomic, readonly) BOOL dragging;
@property (nonatomic, copy) void (^onChange)(double value, BOOL final);
- (void)showValue:(double)value pending:(BOOL)pending;     // dal modello (ignorato mentre si trascina)
- (void)setNote:(NSString *)note;                          // riga piccola sotto il titolo (es. "→ 45 in 11 s")
- (void)debugSet:(double)value;                            // verifica da Mac: come un rilascio del cursore
@end
