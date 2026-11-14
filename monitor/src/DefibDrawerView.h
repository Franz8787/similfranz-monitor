// SimulaFranz_Monitor — cassetto del defibrillatore (sotto il monitor).
// Modalità: DAE (semiautomatico, con voce), MANUALE (energia, carica, shock, SYNC/cardioversione), PACER (transcutaneo).
// La logica (tempi, esiti degli shock, cattura) è in SimulationState: qui solo interfaccia, suoni e rilevazione dell'onda R.
#import <UIKit/UIKit.h>
@class SimulationState, SLSnapshot, WaveformEngine, SoundEngine;

@interface DefibDrawerView : UIView

- (instancetype)initWithFrame:(CGRect)frame state:(SimulationState *)state
                       engine:(WaveformEngine *)engine sound:(SoundEngine *)sound;

@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic) BOOL active;
- (BOOL)tapNamed:(NSString *)name;      // verifica da Mac: CARICA, SHOCK, ANALIZZA, ANNULLA, SYNC, PIASTRE, CHIUDI, PACING, MODO:off|aed|manual|pacer      // YES solo a cassetto aperto: i pulsanti agiscono solo allora

// a ogni cambio di revisione dello stato
- (void)updateWithSnapshot:(SLSnapshot *)s;
// a ogni frame (anche a cassetto chiuso: voce, toni di carica, sync)
- (void)tick:(NSTimeInterval)now snapshot:(SLSnapshot *)s visible:(BOOL)visible;
- (void)resetTraceAt:(NSTimeInterval)t;

// Autotest dell'interfaccia (avviato con simulafranz-monitor://selftest): tocchi simulati con hit-test reale
- (void)runSelfTestWithShot:(void (^)(NSString *name))shot done:(void (^)(NSInteger fails))done;

@end
