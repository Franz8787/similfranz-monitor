// SimulaFranz_Monitor — schermata principale del monitor multiparametrico simulato.
#import <UIKit/UIKit.h>
@class SimulationState;

@interface MonitorViewController : UIViewController
- (instancetype)initWithState:(SimulationState *)state;
// Informazioni tecniche mostrate nel pannello (i)
@property (nonatomic, copy) NSString *(^pinProvider)(void);
@property (nonatomic) uint16_t serverPort;
// Stato dei collegamenti per il pannello (i): version, directName, directOn, directError, peers, controller
@property (nonatomic, copy) NSDictionary *(^linkInfo)(void);
@property (nonatomic, copy) NSString *serverStatus;
// "Azzera e spegni" dal menu del monitor: stessa azione del controller (chiude lo scenario a fasi, nuova sessione del registro)
@property (nonatomic, copy) void (^onResetScenario)(void);   // es. "attivo" o messaggio d'errore
- (void)debugSplash:(NSString *)query;   // splash?static=1 | off=1 | (niente = animazione)
- (void)runSelfTest;
- (void)saveShot:(NSString *)name;
- (void)debugTap:(NSString *)key;       // tocco simulato del discente (verifica da Mac): tasto del layout o del cassetto   // screenshot in Caches/selftest/<name>.png
- (void)runSelfTestExtraH;  // layout originale extraH
- (void)runSelfTestDae;     // layout originale DAE
@end
