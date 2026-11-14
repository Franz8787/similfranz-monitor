// similFranz Controller — "Piano di debriefing": tutto lo scenario com'è andato, dal registro tenuto sul monitor.
// In alto il riepilogo (durata, tempi delle azioni critiche dall'arresto, scariche, farmaci, punti segnati),
// sotto la cronologia completa con i filtri per categoria.
#import <UIKit/UIKit.h>
@class CtlModel;

@interface CtlDebriefView : UIViewController
- (instancetype)initWithModel:(CtlModel *)model;
- (void)reload;
@end

// etichetta breve e colore di una categoria del registro (usati anche nella colonna Registro)
NSString *CtlLogKindName(NSString *kind);
UIColor *CtlLogKindColor(NSString *kind);
