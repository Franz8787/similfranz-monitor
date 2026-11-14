// similFranz Monitor — collegamento DIRETTO fra iPad, senza rete Wi-Fi (Multipeer Connectivity, iOS 7+).
// Il monitor si annuncia come servizio "similfranz"; l'app controller per iPad lo trova, lo invita e poi
// parla la STESSA API JSON del server HTTP, incapsulata in messaggi:
//
//   richiesta  {"id": 7, "method": "POST", "path": "/api/v1/command",
//               "headers": {"X-SimulaFranz-Token": "<PIN>", "X-SimulaFranz-Client": "<id>", ...},
//               "body": {"command": "set_heart_rate", "value": 110}}
//   risposta   {"id": 7, "status": 200, "body": {"ok": true, "state": {...}, "controller": {...}}}
//
// Appena un controller si collega riceve {"event": "hello", ...discoveryInfo}.
// L'invito è sempre accettato: la sicurezza è il PIN, richiesto in ogni messaggio come via HTTP
// (stesso blocco dopo 5 PIN errati). La sessione è cifrata (MCEncryptionRequired).
// Funziona sia sulla stessa rete Wi-Fi sia senza alcuna rete (Wi-Fi e/o Bluetooth accesi sui due iPad).
#import <Foundation/Foundation.h>
#import "LocalHTTPServer.h"

extern NSString *const SFPeerServiceType;     // "similfranz"

@interface SFPeerLink : NSObject
- (instancetype)initWithDisplayName:(NSString *)name
                      discoveryInfo:(NSDictionary<NSString *, NSString *> *)info
                            handler:(SLHTTPHandler)handler;
- (void)start;
- (void)stop;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly, copy) NSString *displayName;      // nome con cui il monitor compare nel controller
@property (nonatomic, readonly, copy) NSString *lastError;        // annuncio non riuscito
@property (nonatomic, readonly, copy) NSArray<NSString *> *peerNames;   // controller collegati ora
@property (nonatomic, copy) void (^onChange)(void);               // main thread
@end
