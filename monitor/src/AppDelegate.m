// SimulaFranz_Monitor — avvio app, configurazione (PIN/porta), server HTTP e Bonjour.
#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "SimulationState.h"
#import "APIController.h"
#import "LocalHTTPServer.h"
#import "MonitorViewController.h"
#import "SFLog.h"
#import "SFControl.h"
#import "SFScenarioStore.h"
#import "SFSessionLog.h"
#import "SFPeerLink.h"

static NSString *const kPinKey  = @"sf_pin";    // stesse chiavi di Settings.bundle
static NSString *const kPortKey = @"sf_port";

@interface AppDelegate () <NSNetServiceDelegate>
@end

@implementation AppDelegate {
    SimulationState *_state;
    APIController *_api;
    LocalHTTPServer *_server;
    MonitorViewController *_monitor;
    NSNetService *_bonjour, *_bonjourApp;
    SFPeerLink *_peer;                 // collegamento diretto fra iPad, senza rete
    uint16_t _port;
}

#pragma mark - Configurazione

// PIN del controller: impostabile in Impostazioni › SimulaFranz_Monitor.
// Se assente o troppo corto, ne genera uno casuale di 6 cifre e lo salva.
+ (NSString *)currentPin {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *pin = [[d stringForKey:kPinKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (pin.length < 4) {
        pin = [NSString stringWithFormat:@"%06u", arc4random_uniform(1000000)];
        [d setObject:pin forKey:kPinKey];
        [d synchronize];
    }
    return pin;
}

// Nome con cui il monitor compare nei controller (Impostazioni › similFranz Monitor › Nome).
// Il numero distingue più monitor nella stessa sala.
+ (NSString *)monitorName {
    NSString *n = [[[NSUserDefaults standardUserDefaults] stringForKey:@"sf_name"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return n.length ? n : @"similFranz Monitor 1";
}

- (uint16_t)configuredPort {
    NSInteger p = [[NSUserDefaults standardUserDefaults] integerForKey:kPortKey];
    return (p >= 1024 && p <= 65535) ? (uint16_t)p : 8080;
}

#pragma mark - Ciclo di vita

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kPortKey: @8080}];
    SFLog(@"avvio similFranz Monitor %@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    application.idleTimerDisabled = YES;            // lo schermo resta acceso durante la simulazione

    _state = [[SimulationState alloc] initWithDeviceId:@"monitor-01"];
    _state.clock = ^NSTimeInterval { return CACurrentMediaTime(); };

    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"index.html", @"style.css", @"app.js", @"body.svg"]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:[name stringByDeletingPathExtension]
                                                         ofType:[name pathExtension] inDirectory:@"web-console"];
        NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (d) files[name] = d; else SFLog(@"file controller mancante: %@", name);
    }
    _api = [[APIController alloc] initWithState:_state
                                    pinProvider:^NSString *{ return [AppDelegate currentPin]; }
                                    staticFiles:files];
    _api.clock = ^NSTimeInterval { return CACurrentMediaTime(); };
    // scenari a fasi: salvati sul monitor, condivisi da web app e app controller
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    _api.scenarios = [[SFScenarioStore alloc] initWithPath:[support stringByAppendingPathComponent:@"similFranz/scenari.json"] state:_state];
    // registro della sessione per il debriefing: osserva lo stato una volta al secondo (leggero) e resta salvato su file
    _api.sessionLog = [[SFSessionLog alloc] initWithPath:[support stringByAppendingPathComponent:@"similFranz/registro.json"] state:_state];
    // aggiornamenti dalla regia web (computer): pacchetti dei controller conservati qui; ricerca su GitHub solo nella versione pubblica
    _api.packagesDir = [support stringByAppendingPathComponent:@"similFranz/pacchetti"];
    _api.updateRepo = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SFUpdateRepo"] ?: @"";
    _api.appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    __weak SFSessionLog *slog = _api.sessionLog;
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:[NSBlockOperation blockOperationWithBlock:^{ [slog observe]; }] selector:@selector(main) userInfo:nil repeats:YES];
    __weak APIController *api = _api;

    _monitor = [[MonitorViewController alloc] initWithState:_state];
    _monitor.pinProvider = ^NSString *{ return [AppDelegate currentPin]; };

    // Un solo controller alla volta, su qualsiasi canale (web app, app nativa via Wi-Fi, app nativa in diretto)
    _api.control.onChange = ^{
        NSDictionary *o = [api.control owner];
        SFLog(@"controller attivo: %@", o ? [NSString stringWithFormat:@"%@ (%@, %@)", o[@"name"], o[@"kind"], o[@"transport"]] : @"nessuno");
        NSString *ev = api.control.lastEvent;          // ogni cambio di mano resta nel registro della sessione (trasparenza)
        if (ev.length) [api.sessionLog add:@"note" text:ev tag:nil by:@"regia"];
    };
    // Collegamento diretto (Multipeer): stessa API del server HTTP, senza rete Wi-Fi
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    _peer = [[SFPeerLink alloc] initWithDisplayName:[AppDelegate monitorName]
                                      discoveryInfo:@{@"type": @"monitor", @"id": _state.deviceId, @"ver": ver, @"api": @"v1"}
                                            handler:^SLHTTPResponse *(SLHTTPRequest *req) { return [api handle:req]; }];
    __weak SFPeerLink *peer = _peer;
    SimulationState *st = _state;
    _monitor.onResetScenario = ^{
        APIController *a = api;
        [a.scenarios stop];
        [st applyCommand:@{@"command": @"reset_scenario"} error:NULL];
        [a.sessionLog noteCommand:@{@"command": @"reset_scenario"} by:@"monitor"];
    };
    _monitor.linkInfo = ^NSDictionary *{
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"version"] = ver;
        d[@"directName"] = peer.displayName ?: @"";
        d[@"directOn"] = @((BOOL)peer.running);
        if (peer.lastError) d[@"directError"] = peer.lastError;
        d[@"peers"] = peer.peerNames ?: @[];
        NSDictionary *o = [api.control owner];
        if (o) d[@"controller"] = o;
        return d;
    };

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.window.rootViewController = _monitor;
    [self.window makeKeyAndVisible];

    [AppDelegate currentPin];   // genera il PIN al primo avvio
    [self startServer];
    return YES;
}

- (void)startServer {
    [_peer start];                                   // il collegamento diretto non dipende dal server HTTP
    if (_server.running) return;
    _port = [self configuredPort];
    __weak APIController *api = _api;
    _server = [[LocalHTTPServer alloc] initWithPort:_port handler:^SLHTTPResponse *(SLHTTPRequest *req) {
        return [api handle:req];
    }];
    NSError *err = nil;
    if ([_server start:&err]) {
        _monitor.serverStatus = [NSString stringWithFormat:@"attivo sulla porta %u", _port];
        SFLog(@"server HTTP attivo sulla porta %u", _port);
        // Bonjour opzionale: il fallback resta sempre l'IP mostrato a schermo
        _bonjour = [[NSNetService alloc] initWithDomain:@"local." type:@"_http._tcp."
                                                   name:[NSString stringWithFormat:@"similFranz Monitor %@", _state.deviceId] port:_port];
        _bonjour.delegate = self;
        [_bonjour publish];
        // Servizio dedicato: l'app controller sulla stessa rete Wi-Fi trova il monitor senza scrivere l'indirizzo
        // (non "_similfranz._tcp": quel nome è già usato da Multipeer per il collegamento diretto)
        _bonjourApp = [[NSNetService alloc] initWithDomain:@"local." type:@"_similfranz-http._tcp."
                                                      name:[AppDelegate monitorName] port:_port];
        NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
        NSMutableDictionary *txt = [NSMutableDictionary dictionary];
        for (NSArray *kv in @[@[@"type", @"monitor"], @[@"id", _state.deviceId], @[@"ver", ver], @[@"api", @"v1"]])
            txt[kv[0]] = [kv[1] dataUsingEncoding:NSUTF8StringEncoding];
        [_bonjourApp setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txt]];
        _bonjourApp.delegate = self;
        [_bonjourApp publish];
    } else {
        _monitor.serverStatus = [NSString stringWithFormat:@"ERRORE: %@", err.localizedDescription];
        SFLog(@"avvio server fallito: %@", err);
    }
    _monitor.serverPort = _port;
}

- (void)stopServer {
    [_peer stop];
    [_bonjour stop]; _bonjour = nil;
    [_bonjourApp stop]; _bonjourApp = nil;
    [_server stop]; _server = nil;
}

// In background iOS sospende l'app: chiudo il socket e lo riapro al ritorno.
- (void)applicationDidEnterBackground:(UIApplication *)application { [_api.sessionLog flush]; [self stopServer]; }
- (void)applicationWillEnterForeground:(UIApplication *)application { [self startServer]; }
- (void)applicationDidBecomeActive:(UIApplication *)application {
    application.idleTimerDisabled = YES;
    [self startServer];
}

// simulafranz-monitor://selftest -> autotest dell'interfaccia del defibrillatore (log + screenshot in Caches/selftest)
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url sourceApplication:(NSString *)src annotation:(id)ann {
    if ([url.host isEqualToString:@"selftest-extrah"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_monitor runSelfTestExtraH]; });
    }
    if ([url.host isEqualToString:@"selftest-dae"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_monitor runSelfTestDae]; });
    }
    // simulafranz-monitor://tap?key=XXX -> tocco simulato del discente sul tasto XXX (verifica degli scenari da Mac)
    if ([url.host isEqualToString:@"tap"]) {
        NSString *key = nil;
        for (NSString *kv in [url.query componentsSeparatedByString:@"&"]) if ([kv hasPrefix:@"key="]) key = [[kv substringFromIndex:4] stringByRemovingPercentEncoding];
        if (key) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_monitor debugTap:key]; });
    }
    // simulafranz-monitor://shot?name=xxx -> screenshot immediato (verifica grafica da Mac via SSH)
    if ([url.host isEqualToString:@"shot"]) {
        NSString *name = @"shot";
        for (NSString *kv in [url.query componentsSeparatedByString:@"&"]) if ([kv hasPrefix:@"name="]) name = [[kv substringFromIndex:5] lastPathComponent];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_monitor saveShot:name]; });
    }
    if ([url.host isEqualToString:@"splash"]) { [_monitor debugSplash:url.query ?: @""]; }
    if ([url.host isEqualToString:@"selftest"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_monitor runSelfTest]; });
    }
    return YES;
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
    SFLog(@"Bonjour non pubblicato: %@", errorDict);
}

@end
