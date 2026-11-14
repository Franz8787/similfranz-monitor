// similFranz Controller — schermata unica dell'istruttore ("cabina di regia"):
//   in alto     le tessere con i valori VERI del paziente (toccarne una apre la sua regolazione al centro)
//   a sinistra  Stati (pacchetti one-tap) oppure Scenario (fasi che l'istruttore fa avanzare)
//   al centro   la regolazione del parametro scelto (cursore, − / +, valori rapidi, ritmi)
//   a destra    sonde applicate al paziente e azioni rapide
//   in basso    orologio di scenario, pausa, "applica le modifiche: subito / in N s", monitor collegato
#import <UIKit/UIKit.h>
@class CtlModel;

@interface CtlViewController : UIViewController
- (instancetype)initWithModel:(CtlModel *)model;
// verifica da Mac (URL simulafranz-controller://...): shot?name=, tap?id=, seg?id=&i=, val?id=&v=, sw?id=&on=, pin?v=, list
- (void)debug:(NSString *)host query:(NSDictionary<NSString *, NSString *> *)q;
@end
