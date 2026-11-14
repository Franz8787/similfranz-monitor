// similFranz Pocket — una sola schermata verticale, a pollice:
//   in alto i valori del paziente (tessere: un tocco sceglie il parametro);
//   al centro, secondo la scheda: Parametri (rotella + valori rapidi), Ritmo, Sonde, Azioni;
//   sotto, per Parametri e Ritmo, il tempo di transizione e «Avvia».
// Con «Subito» ogni modifica parte quando si solleva il dito; con un tempo le modifiche si accodano e partono insieme.
#import <UIKit/UIKit.h>
@class CtlModel;

@interface PkViewController : UIViewController
- (instancetype)initWithModel:(CtlModel *)model;
- (void)debug:(NSString *)host query:(NSDictionary<NSString *, NSString *> *)q;   // simulafranz-pocket://host?…
@end
