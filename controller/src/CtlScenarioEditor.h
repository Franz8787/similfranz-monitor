// similFranz Controller — costruzione di uno scenario a fasi (salvato sul monitor, condiviso con la web app).
// A sinistra l'elenco delle fasi (aggiungi, duplica, sposta, elimina); a destra la fase scelta:
// nome, ritmo, parametri (ognuno con il suo interruttore "cambia in questa fase"), tempo di transizione, nota.
#import <UIKit/UIKit.h>

@interface CtlScenarioEditor : UIViewController
// scenario nil = nuovo. currentBlock = {rhythm, params, temperature_c, crt_s} del paziente adesso ("fase dai valori attuali").
- (instancetype)initWithScenario:(NSDictionary *)scenario currentBlock:(NSDictionary *)current;
@property (nonatomic, copy) void (^onSave)(NSDictionary *scenario);
@property (nonatomic, copy) void (^onDelete)(NSString *scenarioId);
- (void)showError:(NSString *)error;
@end
