// similFranz Monitor — pannello "Collegamento del controller" (si apre dal tasto (i) di ogni layout).
// Mostra i due modi di collegare un controller e chi sta comandando:
//   1 · con una rete Wi-Fi  -> web app (QR / indirizzo) oppure app controller per iPad (trova da sola il monitor)
//   2 · diretto, senza rete -> app controller per iPad (Multipeer, vedi SFPeerLink)
// più il PIN (uguale per tutti i canali) e la pagina "Reti Wi-Fi" per scegliere la rete senza uscire dall'app.
#import <UIKit/UIKit.h>

@interface SFConnectPanel : UIView
// Dati da mostrare, riletti a ogni refresh. Chiavi (tutte facoltative):
//   version, deviceId, ip, port (NSNumber), pin, serverStatus, audio,
//   directName, directOn (NSNumber BOOL), directError, peers (NSArray<NSString *>),
//   controller (NSDictionary {name, kind, transport}) oppure assente se nessuno comanda
@property (nonatomic, copy) NSDictionary *(^info)(void);
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onVolumes)(void);
@property (nonatomic, readonly) NSTimeInterval lastInteraction;   // per la chiusura automatica
@property (nonatomic, readonly) BOOL busy;                        // pagina Wi-Fi aperta o collegamento in corso: non chiudere
- (void)refresh;
- (void)showWifi;
- (void)showMain;
// verifica da Mac: collega alla rete con questo nome (password facoltativa)
- (void)debugJoin:(NSString *)ssid password:(NSString *)pw;
@end
