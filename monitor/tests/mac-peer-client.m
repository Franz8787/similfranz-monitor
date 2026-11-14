// CLIENT DI PROVA SU MAC per il collegamento diretto (Multipeer) — NON è il prodotto.
// Fa quello che farà l'app controller per iPad: cerca i monitor "similfranz", invita il primo,
// poi usa la stessa API JSON del server HTTP incapsulata in messaggi (vedi src/SFPeerLink.h).
// Uso: build/mac/mac-peer-client <PIN> [secondi di attesa, default 40]
#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>

@interface Client : NSObject <MCNearbyServiceBrowserDelegate, MCSessionDelegate>
@property NSString *pin; @property int failures;
@end
@implementation Client { MCPeerID *_me; MCNearbyServiceBrowser *_br; MCSession *_s; NSArray *_steps; NSUInteger _i; MCPeerID *_mon; NSDate *_t0; }
- (void)start {
    _t0 = [NSDate date];
    _me = [[MCPeerID alloc] initWithDisplayName:@"Mac di prova"];
    _s = [[MCSession alloc] initWithPeer:_me securityIdentity:nil encryptionPreference:MCEncryptionRequired];
    _s.delegate = self;
    _br = [[MCNearbyServiceBrowser alloc] initWithPeer:_me serviceType:@"similfranz"];
    _br.delegate = self; [_br startBrowsingForPeers];
    NSDictionary *H = @{@"X-SimulaFranz-Token": self.pin, @"X-SimulaFranz-Client": @"mac-test-1", @"X-SimulaFranz-Client-Name": @"Mac%20di%20prova", @"X-SimulaFranz-Client-Kind": @"ipad"};
    // @[descrizione, messaggio, stato atteso]
    _steps = @[
      @[@"health senza PIN", @{@"method": @"GET", @"path": @"/api/v1/health"}, @200],
      @[@"state senza PIN -> 401", @{@"method": @"GET", @"path": @"/api/v1/state"}, @401],
      @[@"pagina web non disponibile in diretto -> 404", @{@"method": @"GET", @"path": @"/index.html"}, @404],
      @[@"prendo il controllo", @{@"method": @"POST", @"path": @"/api/v1/control", @"headers": H, @"body": @{@"action": @"take"}}, @200],
      @[@"state con PIN", @{@"method": @"GET", @"path": @"/api/v1/state", @"headers": H}, @200],
      @[@"comando (cancel_transitions)", @{@"method": @"POST", @"path": @"/api/v1/command", @"headers": H, @"body": @{@"command": @"cancel_transitions"}}, @200],
      @[@"comando non valido -> 400", @{@"method": @"POST", @"path": @"/api/v1/command", @"headers": H, @"body": @{@"command": @"set_spo2", @"value": @140}}, @400],
      @[@"pausa di 3 s col controllo (per lo screenshot)", @{@"method": @"GET", @"path": @"/api/v1/control", @"headers": H, @"_wait": @3}, @200],
      @[@"rilascio", @{@"method": @"POST", @"path": @"/api/v1/control", @"headers": H, @"body": @{@"action": @"release"}}, @200],
    ];
}
- (void)log:(NSString *)s { printf("[%5.1f s] %s\n", -[_t0 timeIntervalSinceNow], s.UTF8String); fflush(stdout); }
- (void)browser:(MCNearbyServiceBrowser *)b foundPeer:(MCPeerID *)p withDiscoveryInfo:(NSDictionary *)info {
    [self log:[NSString stringWithFormat:@"trovato \"%@\" %@", p.displayName, info]];
    if (_mon || ![info[@"type"] isEqualToString:@"monitor"]) return;
    _mon = p; [b invitePeer:p toSession:_s withContext:nil timeout:20];
}
- (void)browser:(MCNearbyServiceBrowser *)b lostPeer:(MCPeerID *)p { [self log:[@"perso " stringByAppendingString:p.displayName]]; }
- (void)browser:(MCNearbyServiceBrowser *)b didNotStartBrowsingForPeers:(NSError *)e { [self log:[NSString stringWithFormat:@"ricerca NON avviata: %@", e]]; exit(2); }
- (void)session:(MCSession *)s peer:(MCPeerID *)p didChangeState:(MCSessionState)st {
    [self log:[NSString stringWithFormat:@"sessione con \"%@\": %@", p.displayName, st == MCSessionStateConnected ? @"COLLEGATA" : (st == MCSessionStateConnecting ? @"in collegamento" : @"chiusa")]];
    if (st == MCSessionStateConnected) dispatch_async(dispatch_get_main_queue(), ^{ [self next]; });
    if (st == MCSessionStateNotConnected && _i < _steps.count) { printf("FAIL sessione chiusa prima della fine\n"); exit(1); }
}
- (void)next {
    if (_i >= _steps.count) { printf("\nCollegamento diretto: %d errori su %lu passi\n", self.failures, (unsigned long)_steps.count); exit(self.failures ? 1 : 0); }
    NSMutableDictionary *m = [_steps[_i][1] mutableCopy]; m[@"id"] = @(_i);
    NSNumber *wait = m[@"_wait"]; [m removeObjectForKey:@"_wait"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *e = nil;
        if (![self->_s sendData:[NSJSONSerialization dataWithJSONObject:m options:0 error:NULL] toPeers:@[self->_mon] withMode:MCSessionSendDataReliable error:&e])
            { printf("FAIL invio: %s\n", e.description.UTF8String); exit(1); }
    });
}
- (void)session:(MCSession *)s didReceiveData:(NSData *)d fromPeer:(MCPeerID *)p {
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (j[@"event"]) { [self log:[NSString stringWithFormat:@"evento %@", j]]; return; }
        NSArray *step = self->_steps[self->_i];
        BOOL ok = [j[@"id"] isEqual:@(self->_i)] && [j[@"status"] isEqual:step[2]];
        if (!ok) self.failures++;
        NSDictionary *b = j[@"body"]; NSMutableString *brief = [NSMutableString string];
        for (NSString *k in @[@"ok", @"error", @"message", @"service", @"version", @"controller", @"revision"]) if (b[k] && b[k] != [NSNull null]) [brief appendFormat:@" %@=%@", k, [[b[k] description] stringByReplacingOccurrencesOfString:@"\n" withString:@""]];
        [self log:[NSString stringWithFormat:@"%@ %@ -> %@%@", ok ? @"PASS" : @"FAIL", step[0], j[@"status"], brief]];
        self->_i++; [self next];
    });
}
- (void)session:(MCSession *)s didReceiveCertificate:(NSArray *)c fromPeer:(MCPeerID *)p certificateHandler:(void (^)(BOOL))h { h(YES); }
- (void)session:(MCSession *)s didReceiveStream:(NSInputStream *)st withName:(NSString *)n fromPeer:(MCPeerID *)p {}
- (void)session:(MCSession *)s didStartReceivingResourceWithName:(NSString *)n fromPeer:(MCPeerID *)p withProgress:(NSProgress *)pr {}
- (void)session:(MCSession *)s didFinishReceivingResourceWithName:(NSString *)n fromPeer:(MCPeerID *)p atURL:(NSURL *)u withError:(NSError *)e {}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "uso: mac-peer-client <PIN> [secondi]\n"); return 2; }
        Client *c = [Client new]; c.pin = @(argv[1]); [c start];
        double limit = argc > 2 ? atof(argv[2]) : 40;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ printf("FAIL tempo scaduto (%.0f s): monitor non trovato o nessuna risposta\n", limit); exit(1); });
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
