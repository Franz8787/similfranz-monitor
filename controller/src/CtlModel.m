#import "CtlModel.h"
#import "SFLog.h"
#import "SFUpdate.h"
#import <UIKit/UIKit.h>

static NSString *const kPinKey = @"sf_pin", *const kMonKey = @"sf_monitor", *const kClientKey = @"sf_client";

@implementation CtlModel {
    NSString *_pin, *_wanted, *_clientId, *_clientName;
    NSTimer *_timer; BOOL _polling; NSInteger _cmdSeq;
    BOOL _authorized;
    NSMutableArray<NSDictionary *> *_logEntries; NSInteger _logNext; BOOL _logLoading; NSInteger _silent;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _pin = [d stringForKey:kPinKey]; _wanted = [d stringForKey:kMonKey];
        _clientId = [d stringForKey:kClientKey];
        if (!_clientId.length) {
            _clientId = [NSString stringWithFormat:@"ipad-%08x%08x", arc4random(), arc4random()];
            [d setObject:_clientId forKey:kClientKey];
        }
        // nome con cui questo controller compare sul monitor (preferenza "sf_name"; il numero distingue più controller)
        _clientName = [d stringForKey:@"sf_name"].length ? [d stringForKey:@"sf_name"] : @"similFranz Controller 1";
        _link = [[SFLink alloc] initWithDisplayName:_clientName];
        __weak CtlModel *me = self;
        _link.onChange = ^{ [me linkChanged]; };
    }
    return self;
}

- (void)notify { if (self.onUpdate) self.onUpdate(); }
- (NSArray<NSDictionary *> *)log { return [_logEntries copy] ?: @[]; }
// si può comandare: nessuno comanda, comandiamo noi, oppure chi comanda è fermo da più di un minuto (il primo comando passa)
- (BOOL)mine { return !_controller || [_controller[@"mine"] boolValue] || ![_controller[@"active"] boolValue] || [_controller[@"protected"] isEqual:@NO]; }
- (NSString *)monitorName { return _link.connectedName ?: _wanted; }

- (void)start {
    [_link start];
    if (!_timer) _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}
- (void)suspend {
    [_timer invalidate]; _timer = nil;
    // app in background (iPod in tasca, iPad bloccato): lascia libero il comando, così nessuno resta bloccato
    BOOL release = _authorized && [_controller[@"mine"] boolValue];
    if (release) [self control:@"release"];
    _authorized = NO; _stage = CtlStageSearching;
    if (release) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (!self->_timer) [self->_link stop]; });
    else [_link stop];
}

- (void)connect:(SFLinkMonitor *)m {
    _wanted = [m.name copy];
    [[NSUserDefaults standardUserDefaults] setObject:_wanted forKey:kMonKey];
    _pinError = nil;
    [_link connectTo:m];
}

- (void)forgetMonitor {
    _wanted = nil; [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMonKey];
    if (_authorized && self.mine) [self control:@"release"];
    _authorized = NO; _state = nil; _controller = nil; _scenario = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_link disconnect]; });
}

- (void)linkChanged {
    switch (_link.state) {
        case SFLinkIdle: {
            _authorized = NO; _stage = CtlStageSearching;
            // il monitor abbinato è di nuovo visibile: ci si ricollega da soli
            if (_wanted) for (SFLinkMonitor *m in _link.monitors) if ([m.name isEqualToString:_wanted]) { [_link connectTo:m]; break; }
            break;
        }
        case SFLinkConnecting: _stage = CtlStageConnecting; break;
        case SFLinkConnected:
            if (!_authorized) { _stage = _pin.length ? CtlStageConnecting : CtlStageNeedPin; if (_pin.length) [self poll]; }
            break;
    }
    [self notify];
}

- (NSDictionary *)headers {
    return @{@"X-SimulaFranz-Token": _pin ?: @"", @"X-SimulaFranz-Client": _clientId,
             @"X-SimulaFranz-Client-Name": [_clientName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]] ?: @"iPad",
             @"X-SimulaFranz-Client-Kind": @"ipad"};
}

- (void)submitPin:(NSString *)pin {
    _pin = [pin copy]; _pinError = nil;
    _stage = CtlStageConnecting; [self notify];
    [self poll];
}

// Risposta comune: aggiorna stato, controller, scenario; gestisce PIN errato e "monitor in uso"
- (BOOL)absorb:(NSInteger)status body:(NSDictionary *)b {
    if (status == 0) return NO;
    if (status == 401 || status == 429) {
        _authorized = NO; _stage = CtlStageNeedPin;
        _pinError = status == 401 ? @"PIN non valido" : @"Troppi tentativi: riprovare fra mezzo minuto";
        if (status == 401) { _pin = nil; [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPinKey]; }
        return NO;
    }
    if ([b[@"controller"] isKindOfClass:[NSDictionary class]]) _controller = b[@"controller"];
    if ([b[@"scenario"] isKindOfClass:[NSDictionary class]]) _scenario = b[@"scenario"];
    if ([b[@"scenarios"] isKindOfClass:[NSArray class]]) _scenarios = b[@"scenarios"];
    if ([b[@"state"] isKindOfClass:[NSDictionary class]]) _state = b[@"state"];
    if ([b[@"log_next"] isKindOfClass:[NSNumber class]]) {            // il registro è cresciuto (o è stato svuotato): si rilegge
        NSInteger n = [b[@"log_next"] integerValue];
        _logAvailable = YES;
        NSInteger sid = [b[@"log_session"] integerValue];
        if (sid != _logSession) { _logSession = sid; _logEntries = nil; _logNext = 0; [self loadLog]; }      // sessione nuova: si riparte da lì
        else if (n != _logNext && status == 200) [self loadLog];
    }
    if (status == 200 && !_authorized) {
        _authorized = YES; _stage = CtlStageReady; _pinError = nil;
        [[NSUserDefaults standardUserDefaults] setObject:_pin forKey:kPinKey];
        SFLog(@"autorizzato dal monitor \"%@\"", _link.connectedName);
        [self refreshScenarios];
        [self checkUpdate];
        _logEntries = nil; _logNext = 0;
    }
    return status == 200;
}

- (void)tick { if (_link.state == SFLinkConnected && _pin.length && (_authorized || _stage == CtlStageConnecting)) [self poll]; }

- (void)poll {
    if (_polling) return;
    _polling = YES; NSInteger seq = _cmdSeq;
    [_link request:@"GET" path:@"/api/v1/state" headers:[self headers] body:nil completion:^(NSInteger status, NSDictionary *b) {
        self->_polling = NO;
        // una sessione Multipeer può morire in silenzio: dopo due letture senza risposta si chiude e ci si ricollega
        if (status == 0) { if (++self->_silent >= 2) { self->_silent = 0; [self->_link resetAfterSilence]; } }
        else self->_silent = 0;
        if (seq != self->_cmdSeq && status == 200) return;      // nel frattempo è partito un comando: lettura superata
        [self absorb:status body:b];
        [self notify];
    }];
}

static NSString *Explain(NSInteger status, NSDictionary *b) {
    if (status == 0) return @"Il monitor non risponde";
    if (status == 423) return [NSString stringWithFormat:@"Comando non eseguito: il monitor è comandato da %@", b[@"controller"][@"name"] ?: @"un altro controller"];
    NSString *e = [b[@"error"] isKindOfClass:[NSString class]] ? b[@"error"] : nil;
    return e.length ? [@"Non eseguito: " stringByAppendingString:e] : @"Comando non eseguito";
}

- (void)post:(NSString *)path body:(NSDictionary *)body done:(void (^)(BOOL, NSString *, NSDictionary *))done {
    _cmdSeq++;
    [_link request:@"POST" path:path headers:[self headers] body:body completion:^(NSInteger status, NSDictionary *b) {
        BOOL ok = [self absorb:status body:b];
        self->_lastMessage = ok ? nil : Explain(status, b);
        if (!ok) SFLog(@"%@ %@ -> %ld %@", path, body[@"command"] ?: body[@"action"] ?: @"", (long)status, b[@"error"] ?: @"");
        if (done) done(ok, self->_lastMessage, b);
        [self notify];
    }];
}

- (void)command:(NSString *)name value:(id)value { [self command:name value:value done:nil]; }
- (void)command:(NSString *)name value:(id)value done:(void (^)(BOOL, NSString *))done {
    NSMutableDictionary *b = [@{@"command": name} mutableCopy];
    if (value) b[@"value"] = value;
    [self post:@"/api/v1/command" body:b done:^(BOOL ok, NSString *e, NSDictionary *r) { if (done) done(ok, e); }];
}
- (void)startNibp { [self post:@"/api/v1/nibp/start" body:@{} done:nil]; }
- (void)control:(NSString *)action { [self post:@"/api/v1/control" body:@{@"action": action} done:nil]; }
- (void)takeControl { [self control:@"take"]; }

#pragma mark - Aggiornamento dal monitor

static NSString *MyPackage(void) { return [NSBundle mainBundle].bundleIdentifier ?: @""; }     // it.simulafranz.controller / .pocket
static NSString *MyShort(void) { return [MyPackage() componentsSeparatedByString:@"."].lastObject ?: @""; }
static NSString *HelperPath(void) { return [NSString stringWithFormat:@"/usr/libexec/similfranz-%@-aggiorna", MyShort()]; }
static NSString *DebPath(void) { return [NSString stringWithFormat:@"/var/mobile/Library/Caches/similfranz-aggiornamento-%@.deb", MyShort()]; }

- (void)checkUpdate {
    if (![SFUpdate installerAvailable:HelperPath()]) return;           // versione senza aiutante: si aggiorna dal computer
    [_link request:@"GET" path:@"/api/v1/update" headers:[self headers] body:nil completion:^(NSInteger status, NSDictionary *b) {
        if (status != 200 || ![b[@"packages"] isKindOfClass:[NSDictionary class]]) return;
        NSString *v = b[@"packages"][MyPackage()], *mine = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
        if ([v isKindOfClass:[NSString class]] && [SFUpdate compareVersion:v to:mine] == NSOrderedDescending) {
            self->_updateVersion = [v copy]; self->_updateProgress = -1;
            SFLog(@"aggiornamento disponibile sul monitor: %@ (installata %@)", v, mine);
            [self notify];
        }
    }];
}

- (void)installUpdate:(void (^)(NSString *))done {
    if (!_updateVersion) { if (done) done(@"nessun aggiornamento disponibile"); return; }
    NSMutableData *buf = [NSMutableData data];
    _updateProgress = 0; [self notify];
    __block void (^next)(void);
    __weak CtlModel *me = self;
    void (^fail)(NSString *) = ^(NSString *e) { CtlModel *s = me; if (s) { s->_updateProgress = -1; [s notify]; } next = nil; if (done) done(e); };
    next = ^{
        CtlModel *s = me; if (!s) return;
        NSString *path = [NSString stringWithFormat:@"/api/v1/update/chunk?pkg=%@&offset=%lu", MyPackage(), (unsigned long)buf.length];
        [s->_link request:@"GET" path:path headers:[s headers] body:nil completion:^(NSInteger status, NSDictionary *b) {
            CtlModel *t = me; if (!t) return;
            NSData *d = status == 200 && [b[@"data"] isKindOfClass:[NSString class]] ? [[NSData alloc] initWithBase64EncodedString:b[@"data"] options:0] : nil;
            long long size = [b[@"size"] longLongValue];
            if (!d || size <= 0 || size > 8 * 1024 * 1024) { fail(status == 0 ? @"il monitor non risponde: riprova" : @"pacchetto non disponibile sul monitor"); return; }
            [buf appendData:d];
            t->_updateProgress = (double)buf.length / size; [t notify];
            if ((long long)buf.length < size && d.length) { next(); return; }
            NSString *err = nil;
            NSString *v = [SFUpdate installDeb:buf package:MyPackage() debPath:DebPath() helper:HelperPath() error:&err];
            SFLog(@"aggiornamento %@: %@", v ? @"avviato" : @"NON riuscito", v ?: err);
            if (!v) { fail(err); return; }
            next = nil; if (done) done(nil);      // l'aiutante chiude e riapre l'app fra pochi secondi
        }];
    };
    next();
}

- (void)refreshScenarios {
    [_link request:@"GET" path:@"/api/v1/scenarios" headers:[self headers] body:nil completion:^(NSInteger status, NSDictionary *b) {
        if (status == 200) { [self absorb:status body:b]; [self notify]; }
        else if (status == 404) { self->_scenarios = nil; }      // monitor vecchio, senza scenari
    }];
}
#pragma mark - Registro

- (void)absorbLog:(NSDictionary *)b reset:(BOOL)reset {
    if (reset || !_logEntries) _logEntries = [NSMutableArray array];
    NSArray *entries = [b[@"log"] isKindOfClass:[NSArray class]] ? b[@"log"] : @[];
    NSInteger firstNew = entries.count ? [entries.firstObject[@"i"] integerValue] : NSIntegerMax;
    // registro svuotato sul monitor: gli indici ripartono da voci che abbiamo già "oltre" -> si tiene solo il nuovo
    while (_logEntries.count && [_logEntries.lastObject[@"i"] integerValue] >= firstNew) [_logEntries removeLastObject];
    [_logEntries addObjectsFromArray:entries];
    _logNext = [b[@"next"] integerValue];
    if ([b[@"summary"] isKindOfClass:[NSDictionary class]]) _logSummary = b[@"summary"];
    if ([b[@"sessions"] isKindOfClass:[NSArray class]]) _logSessions = b[@"sessions"];
}
- (void)loadSession:(NSInteger)sid done:(void (^)(NSArray<NSDictionary *> *, NSDictionary *))done {
    NSMutableArray *all = [NSMutableArray array];
    __block void (^step)(NSInteger); __weak CtlModel *me = self;
    step = ^(NSInteger since) {
        [me.link request:@"GET" path:[NSString stringWithFormat:@"/api/v1/log?session=%ld&since=%ld", (long)sid, (long)since] headers:[me headers] body:nil completion:^(NSInteger status, NSDictionary *b) {
            if (status != 200) { if (done) done(all, nil); step = nil; return; }
            [all addObjectsFromArray:[b[@"log"] isKindOfClass:[NSArray class]] ? b[@"log"] : @[]];
            if ([b[@"more"] boolValue] && step) { step([b[@"next"] integerValue]); return; }
            if (done) done(all, b[@"summary"]); step = nil;
        }];
    };
    step(0);
}
- (void)newSession:(NSString *)title {
    NSMutableDictionary *body = [@{@"action": @"new_session"} mutableCopy]; if (title.length) body[@"title"] = title;
    [_link request:@"POST" path:@"/api/v1/log" headers:[self headers] body:body completion:^(NSInteger status, NSDictionary *b) {
        if (status == 200) { self->_logSession = [b[@"current_session"] integerValue]; [self absorbLog:b reset:YES]; }
        else self->_lastMessage = Explain(status, b);
        [self notify];
    }];
}
- (void)loadLog {
    if (_logLoading) return;
    _logLoading = YES;
    NSInteger since = _logEntries ? _logNext : 0;
    [_link request:@"GET" path:[NSString stringWithFormat:@"/api/v1/log?since=%ld", (long)since] headers:[self headers] body:nil completion:^(NSInteger status, NSDictionary *b) {
        self->_logLoading = NO;
        if (status == 404) { self->_logAvailable = NO; return; }
        if (status != 200) return;
        // registro svuotato o sessione cambiata sul monitor mentre si leggeva: si rilegge da capo
        BOOL cleared = [b[@"summary"][@"entries"] integerValue] < (NSInteger)self->_logEntries.count || [b[@"current_session"] integerValue] != self->_logSession;
        if ([b[@"current_session"] integerValue]) self->_logSession = [b[@"current_session"] integerValue];
        if (cleared && since > 0) { self->_logEntries = nil; self->_logNext = 0; [self loadLog]; return; }
        [self absorbLog:b reset:since == 0];
        if ([b[@"more"] boolValue]) [self loadLog];
        [self notify];
    }];
}
- (void)logAdd:(NSString *)kind text:(NSString *)text tag:(NSString *)tag {
    NSMutableDictionary *body = [@{@"action": @"add", @"kind": kind, @"text": text} mutableCopy];
    if (tag) body[@"tag"] = tag;
    [_link request:@"POST" path:[NSString stringWithFormat:@"/api/v1/log?since=%ld", (long)_logNext] headers:[self headers] body:body completion:^(NSInteger status, NSDictionary *b) {
        if (status == 200) { [self absorbLog:b reset:NO]; self->_lastMessage = nil; }
        else self->_lastMessage = status == 0 ? @"Il monitor non risponde: voce non registrata" : @"Voce non registrata";
        [self notify];
    }];
}
- (void)logClear:(void (^)(BOOL, NSString *))done {
    [_link request:@"POST" path:@"/api/v1/log" headers:[self headers] body:@{@"action": @"clear"} completion:^(NSInteger status, NSDictionary *b) {
        if (status == 200) [self absorbLog:b reset:YES];
        if (done) done(status == 200, status == 200 ? nil : Explain(status, b));
        [self notify];
    }];
}

- (void)scenarioAction:(NSDictionary *)body done:(void (^)(BOOL, NSString *, NSDictionary *))done {
    [self post:@"/api/v1/scenarios" body:body done:done];
}
@end
