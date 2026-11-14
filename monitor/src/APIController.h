// SimulaFranz_Monitor — API JSON v1 + SimulaFranz_Controller Web (servita dall'app iPad).
// Foundation pura: testabile su macOS con un SimulationState reale.

#import <Foundation/Foundation.h>
#import "LocalHTTPServer.h"
@class SimulationState, SFControl, SFScenarioStore, SFSessionLog;

@interface APIController : NSObject

// pinProvider: PIN/token attuale (letto a ogni richiesta, quindi modificabile a caldo)
// staticFiles: nome file -> contenuto (whitelist; nessun accesso al filesystem dal path)
- (instancetype)initWithState:(SimulationState *)state
                  pinProvider:(NSString *(^)(void))pinProvider
                  staticFiles:(NSDictionary<NSString *, NSData *> *)staticFiles;

- (SLHTTPResponse *)handle:(SLHTTPRequest *)request;

// Parametri anti-forza-bruta (per IP): dopo maxFailures errori in failureWindow s,
// blocco per lockoutSeconds.
@property (nonatomic) NSUInteger maxFailures;        // default 5
@property (nonatomic) NSTimeInterval failureWindow;  // default 60
@property (nonatomic) NSTimeInterval lockoutSeconds; // default 30
@property (nonatomic, copy) NSTimeInterval (^clock)(void);

// Un solo controller alla volta (vedi SFControl.h): chi comanda, presa di controllo, rilascio.
@property (nonatomic, readonly) SFControl *control;

// Scenari a fasi salvati sul monitor (vedi SFScenarioStore.h). nil = endpoint /api/v1/scenarios non disponibile.
@property (nonatomic, strong) SFScenarioStore *scenarios;

// Registro della sessione per il debriefing (vedi SFSessionLog.h). nil = endpoint /api/v1/log non disponibile.
@property (nonatomic, strong) SFSessionLog *sessionLog;

// Aggiornamenti senza computer (vedi SFUpdate.h). Il telefono (console web) porta al monitor i pacchetti nuovi:
// quello del monitor viene installato, quelli di Controller e Pocket restano qui e i controller se li fanno passare
// dal collegamento diretto (/api/v1/update/chunk). nil = cartella non impostata: aggiornamenti non disponibili.
@property (nonatomic, copy) NSString *packagesDir;
@property (nonatomic, copy) NSString *updateRepo;          // "utente/repository" delle versioni pubbliche ("" = versione privata: niente ricerca)
@property (nonatomic, copy) NSString *appVersion;
// Test: sostituisce l'installazione vera del monitor (ritorna la versione o nil + errore)
@property (nonatomic, copy) NSString *(^installHandler)(NSData *deb, NSString **error);

@end
