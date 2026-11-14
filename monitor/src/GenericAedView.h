// similFranz Monitor — layout "DAE": defibrillatore semiautomatico generico ORIGINALE per l'accesso pubblico
// (non riproduce alcun dispositivo in commercio). Tre passi illustrati con la loro spia (1 applica le piastre,
// 2 non toccare: analisi, 3 premi scarica), schermo con le istruzioni a testo, tempo e barra della RCP,
// tasto di scarica che lampeggia quando è carico, tasto Bambino, presa delle piastre. Niente allarmi da monitor né bip.
#import <UIKit/UIKit.h>
#import "AltLayout.h"

@interface GenericAedView : UIView <SFAltLayout>
@property (nonatomic, copy) void (^onLayoutMenu)(void);
@property (nonatomic, copy) void (^onInfo)(void);
@property (nonatomic, copy) void (^onVolumes)(void);
- (BOOL)tapKey:(NSString *)key;
@end
