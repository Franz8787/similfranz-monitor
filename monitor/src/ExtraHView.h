// similFranz Monitor — layout "extraH": monitor-defibrillatore preospedaliero ORIGINALE (non riproduce alcun
// dispositivo in commercio: disposizione dei tasti, colori, proporzioni e testi sono di similFranz).
//   a sinistra   le prese dei sensori (ECG, SpO2, NIBP, CO2, TEMP, piastre) e il tasto di accensione
//   al centro    lo schermo: tracce ECG / pletismografia / CO2, numerici, riquadro della terapia elettrica
//   sotto        la fila dei modi (MONITOR · DAE · MANUALE · PACER) e i tasti di servizio e del pacer
//   a destra     il defibrillatore in tre passi numerati: 1 energia, 2 carica, 3 scarica
// Frontale digitale pensato per un guscio stampato in 3D.
#import <UIKit/UIKit.h>
#import "AltLayout.h"

@interface ExtraHView : UIView <SFAltLayout>
@property (nonatomic, copy) void (^onLayoutMenu)(void);
@property (nonatomic, copy) void (^onInfo)(void);
@property (nonatomic, copy) void (^onVolumes)(void);
- (BOOL)tapKey:(NSString *)key;      // tocco simulato di un tasto (verifica da Mac e autotest)
@end
