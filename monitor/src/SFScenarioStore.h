// similFranz Monitor — scenari a fasi, salvati sul monitor (così web app e app controller vedono gli stessi).
// Uno scenario = nome + note + elenco ordinato di FASI. Una fase = nome + blocco di parametri del paziente
// (ritmo, FC, PA, SpO2, FR, EtCO2, temperatura, refill) + tempo di transizione + nota per l'istruttore.
// Le fasi NON avanzano da sole: è l'istruttore che decide quando passare alla successiva (o a una qualsiasi).
// Fra una fase e l'altra il paziente resta dov'è, e l'istruttore può sempre ritoccare i parametri a mano.
// Foundation pura: testabile su macOS.
#import <Foundation/Foundation.h>
@class SimulationState;

@interface SFScenarioStore : NSObject
// path: file JSON dove salvare (nil = solo in memoria). Se il file non esiste si parte con gli scenari di esempio.
- (instancetype)initWithPath:(NSString *)path state:(SimulationState *)state;

- (NSArray<NSDictionary *> *)scenarios;
// Salva (nuovo o modifica, per id). Ritorna lo scenario normalizzato, o nil con *error leggibile.
- (NSDictionary *)save:(NSDictionary *)scenario error:(NSString **)error;
- (BOOL)deleteId:(NSString *)sid error:(NSString **)error;

// Conduzione: avvio dalla fase indicata (di solito 0), salto a una fase, fase successiva, fine.
- (BOOL)start:(NSString *)sid phase:(NSInteger)phase error:(NSString **)error;
- (BOOL)gotoPhase:(NSInteger)phase error:(NSString **)error;
- (BOOL)next:(NSString **)error;
- (void)stop;
// {active, id, name, phase, phases, phase_name, phase_note, phase_time_s, next_name}; senza scenario: {active:false}
- (NSDictionary *)runInfo;

+ (NSArray<NSDictionary *> *)exampleScenarios;
@end
