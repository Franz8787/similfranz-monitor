#import "APIController.h"
#import "SimulationState.h"
#import "SFControl.h"
#import "SFScenarioStore.h"
#import "SFSessionLog.h"
#import "SFUpdate.h"

@implementation APIController {
    SimulationState *_state;
    NSString *(^_pinProvider)(void);
    NSDictionary<NSString *, NSData *> *_files;
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *_failures; // ip -> timestamps
    NSMutableDictionary<NSString *, NSNumber *> *_lockedUntil;               // ip -> time
    NSTimeInterval _startTime;
}

- (instancetype)initWithState:(SimulationState *)state
                  pinProvider:(NSString *(^)(void))pinProvider
                  staticFiles:(NSDictionary<NSString *, NSData *> *)staticFiles {
    if ((self = [super init])) {
        _state = state;
        _pinProvider = [pinProvider copy];
        _files = [staticFiles copy] ?: @{};
        _failures = [NSMutableDictionary dictionary];
        _lockedUntil = [NSMutableDictionary dictionary];
        _maxFailures = 5; _failureWindow = 60; _lockoutSeconds = 30;
        _clock = ^NSTimeInterval { return [NSProcessInfo processInfo].systemUptime; };
        _startTime = _clock();
        _control = [SFControl new];
    }
    return self;
}

// l'orologio dell'API vale anche per il controllo (un solo controller alla volta)
- (void)setClock:(NSTimeInterval (^)(void))clock { _clock = [clock copy]; _control.clock = _clock; }

static SLHTTPResponse *SLError(NSInteger status, NSString *msg) {
    return [SLHTTPResponse status:status json:@{@"ok": @NO, @"error": msg}];
}

// Confronto a tempo costante (evita di rivelare il PIN tramite tempi di risposta)
static BOOL SLConstantTimeEquals(NSString *a, NSString *b) {
    NSData *da = [a dataUsingEncoding:NSUTF8StringEncoding], *db = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (da.length != db.length || da.length == 0) return NO;
    const uint8_t *pa = da.bytes, *pb = db.bytes; uint8_t diff = 0;
    for (NSUInteger i = 0; i < da.length; i++) diff |= pa[i] ^ pb[i];
    return diff == 0;
}

// Ritorna nil se autorizzato, altrimenti la risposta di errore
- (SLHTTPResponse *)checkAuth:(SLHTTPRequest *)req {
    NSString *ip = req.remoteAddress ?: @"?";
    NSTimeInterval now = self.clock();
    @synchronized (self) {
        NSNumber *until = _lockedUntil[ip];
        if (until && now < until.doubleValue) {
            SLHTTPResponse *r = SLError(429, @"too many failed attempts, retry later");
            r.extraHeaders = @{@"Retry-After": [NSString stringWithFormat:@"%.0f", ceil(until.doubleValue - now)]};
            return r;
        }
        NSString *token = req.headers[@"x-simulafranz-token"];
        NSString *pin = _pinProvider ? _pinProvider() : nil;
        if (token && pin && SLConstantTimeEquals(token, pin)) {
            [_failures removeObjectForKey:ip];
            if ([req.headers[@"x-simulafranz-device"] isEqualToString:@"oximeter"]) [_state noteOximeterSeen];   // il saturimetro è in linea
            return nil;
        }
        NSMutableArray *f = _failures[ip] ?: [NSMutableArray array];
        [f addObject:@(now)];
        [f filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSNumber *t, NSDictionary *b) {
            return now - t.doubleValue <= self.failureWindow; }]];
        _failures[ip] = f;
        if (f.count >= self.maxFailures) {
            _lockedUntil[ip] = @(now + self.lockoutSeconds);
            [_failures removeObjectForKey:ip];
        }
    }
    return SLError(401, @"missing or invalid X-SimulaFranz-Token");
}

- (SLHTTPResponse *)okWithState:(NSString *)cid {
    NSDictionary *st = [_state stateDictionary];
    return [SLHTTPResponse status:200 json:@{@"ok": @YES, @"state": st, @"revision": st[@"revision"], @"error": [NSNull null],
                                             @"controller": [_control infoFor:cid],
                                             @"scenario": _scenarios ? [_scenarios runInfo] : @{@"active": @NO},
                                             @"log_next": @(_sessionLog ? [_sessionLog nextIndex] : 0),
                                             @"log_session": @(_sessionLog ? [_sessionLog currentSession] : 0)}];
}

#pragma mark - Un solo controller alla volta

static NSString *SLClean(NSString *s, NSString *allowed, NSUInteger max) {
    if (!s.length) return nil;
    NSMutableString *o = [NSMutableString string];
    NSCharacterSet *ok = allowed ? [NSCharacterSet characterSetWithCharactersInString:allowed] : nil;
    for (NSUInteger i = 0; i < s.length && o.length < max; i++) {
        unichar c = [s characterAtIndex:i];
        if (ok ? [ok characterIsMember:c] : (c >= 0x20 && c != 0x7f)) [o appendFormat:@"%C", c];
    }
    return o.length ? o : nil;
}

// Identità del controller che fa la richiesta: @[id, nome, tipo, canale]. nil = dispositivo seguace (non è un controller).
// Canale: "direct" per il collegamento diretto fra iPad (richieste del ponte SFPeerLink), altrimenti "wifi".
// Senza l'header X-SimulaFranz-Client (vecchi client, curl) l'identità è l'indirizzo di provenienza.
- (NSArray<NSString *> *)clientOf:(SLHTTPRequest *)req {
    if (req.headers[@"x-simulafranz-device"].length) return nil;
    NSString *remote = req.remoteAddress ?: @"?";
    BOOL direct = [remote hasPrefix:@"peer:"];
    NSString *cid = SLClean(req.headers[@"x-simulafranz-client"], @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-", 64);
    NSString *name = SLClean([req.headers[@"x-simulafranz-client-name"] stringByRemovingPercentEncoding], nil, 40);
    NSString *kind = SLClean(req.headers[@"x-simulafranz-client-kind"], @"abcdefghijklmnopqrstuvwxyz0123456789_-", 16);
    if (!cid) cid = [@"addr:" stringByAppendingString:remote];
    if (!name) name = direct ? [remote substringFromIndex:5] : [@"browser " stringByAppendingString:remote];
    return @[cid, name, kind ?: (direct ? @"ipad" : @"web"), direct ? @"direct" : @"wifi"];
}

// Ritorna nil se chi chiede è il controller attivo (o un seguace), altrimenti 423 "monitor in uso".
- (SLHTTPResponse *)checkControl:(NSArray<NSString *> *)c {
    if (!c) return nil;
    if ([_control act:c[0] name:c[1] kind:c[2] transport:c[3]]) return nil;
    NSDictionary *info = [_control infoFor:c[0]];
    return [SLHTTPResponse status:423 json:@{@"ok": @NO, @"error": @"controller_busy",
        @"message": [NSString stringWithFormat:@"monitor in uso da %@", info[@"name"] ?: @"un altro controller"],
        @"controller": info}];
}

- (SLHTTPResponse *)handle:(SLHTTPRequest *)req {
    NSString *m = req.method, *p = req.path;

    // --- Console Web statica (whitelist) ---
    NSDictionary *statics = @{ @"/": @[@"index.html", @"text/html; charset=utf-8"],
                               @"/index.html": @[@"index.html", @"text/html; charset=utf-8"],
                               @"/style.css": @[@"style.css", @"text/css; charset=utf-8"],
                               @"/app.js": @[@"app.js", @"application/javascript; charset=utf-8"],
                               @"/body.svg": @[@"body.svg", @"image/svg+xml"] };
    if (statics[p]) {
        if (![m isEqualToString:@"GET"] && ![m isEqualToString:@"HEAD"]) return SLError(405, @"method not allowed");
        NSData *d = _files[statics[p][0]];
        if (!d) return SLError(404, @"console file missing from app bundle");
        return [SLHTTPResponse status:200 type:statics[p][1] data:d];
    }

    // --- API v1 ---
    if ([p isEqualToString:@"/api/v1/health"]) {
        if (![m isEqualToString:@"GET"]) return SLError(405, @"method not allowed");
        return [SLHTTPResponse status:200 json:@{
            @"ok": @YES, @"service": @"SimulaFranz_Monitor", @"device_id": _state.deviceId,
            @"device_type": @"multiparameter", @"version": ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"), @"api": @"v1",
            @"uptime_s": @((NSInteger)(self.clock() - _startTime)),
            @"auth": @"X-SimulaFranz-Token", @"transports": @[@"wifi", @"direct"],
            @"controller_active": @((BOOL)([_control owner] != nil)) }];
    }
    if ([p isEqualToString:@"/api/v1/state"]) {
        if (![m isEqualToString:@"GET"]) return SLError(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        NSArray<NSString *> *c = [self clientOf:req];
        if (c) [_control seen:c[0]];     // leggere è sempre permesso
        return [self okWithState:c[0]];
    }
    // Controllo del monitor: GET = chi comanda; POST {"action":"take"} prende il controllo, {"action":"release"} lo lascia
    if ([p isEqualToString:@"/api/v1/control"]) {
        BOOL post = [m isEqualToString:@"POST"];
        if (!post && ![m isEqualToString:@"GET"]) return SLError(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        NSArray<NSString *> *c = [self clientOf:req];
        if (post) {
            if (!c) return SLError(403, @"a follower device cannot take control");
            id json = req.body.length ? [NSJSONSerialization JSONObjectWithData:req.body options:0 error:NULL] : nil;
            NSString *action = [json isKindOfClass:[NSDictionary class]] ? json[@"action"] : nil;
            if ([action isEqual:@"take"]) [_control take:c[0] name:c[1] kind:c[2] transport:c[3]];
            else if ([action isEqual:@"release"]) [_control releaseClient:c[0]];
            else return SLError(400, @"action must be \"take\" or \"release\"");
        } else if (c) [_control seen:c[0]];
        return [SLHTTPResponse status:200 json:@{@"ok": @YES, @"controller": [_control infoFor:c[0]], @"error": [NSNull null]}];
    }
    if ([p isEqualToString:@"/api/v1/command"]) {
        if (![m isEqualToString:@"POST"]) return SLError(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        NSArray<NSString *> *c = [self clientOf:req];
        deny = [self checkControl:c]; if (deny) return deny;
        NSString *ct = [req.headers[@"content-type"] lowercaseString] ?: @"";
        if (![ct hasPrefix:@"application/json"]) return SLError(400, @"Content-Type must be application/json");
        id json = req.body.length ? [NSJSONSerialization JSONObjectWithData:req.body options:0 error:NULL] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) return SLError(400, @"body must be a valid JSON object");
        NSString *err = nil;
        if (![_state applyCommand:json error:&err]) return SLError(400, err ?: @"invalid command");
        if ([json[@"command"] isEqual:@"reset_scenario"]) [_scenarios stop];      // il reset chiude anche lo scenario a fasi
        [_sessionLog noteCommand:json by:c[1]];
        return [self okWithState:c[0]];
    }
    // Scenari a fasi: GET = elenco + conduzione in corso; POST {"action": save|delete|start|goto|next|stop, ...}
    if ([p isEqualToString:@"/api/v1/scenarios"] && _scenarios) {
        BOOL post = [m isEqualToString:@"POST"];
        if (!post && ![m isEqualToString:@"GET"]) return SLError(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        NSArray<NSString *> *c = [self clientOf:req];
        if (!post) {
            if (c) [_control seen:c[0]];
            return [SLHTTPResponse status:200 json:@{@"ok": @YES, @"scenarios": [_scenarios scenarios], @"scenario": [_scenarios runInfo], @"error": [NSNull null]}];
        }
        deny = [self checkControl:c]; if (deny) return deny;
        id json = req.body.length ? [NSJSONSerialization JSONObjectWithData:req.body options:0 error:NULL] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) return SLError(400, @"body must be a valid JSON object");
        NSString *action = [json[@"action"] isKindOfClass:[NSString class]] ? json[@"action"] : @"";
        NSString *sid = [json[@"id"] isKindOfClass:[NSString class]] ? json[@"id"] : nil;
        NSInteger phase = [json[@"phase"] respondsToSelector:@selector(integerValue)] ? [json[@"phase"] integerValue] : 0;
        NSString *err = nil; BOOL ok = YES; NSDictionary *saved = nil;
        if ([action isEqualToString:@"save"]) { saved = [_scenarios save:json[@"scenario"] error:&err]; ok = saved != nil; }
        else if ([action isEqualToString:@"delete"]) ok = [_scenarios deleteId:sid error:&err];
        else if ([action isEqualToString:@"start"]) ok = [_scenarios start:sid phase:phase error:&err];
        else if ([action isEqualToString:@"goto"]) ok = [_scenarios gotoPhase:phase error:&err];
        else if ([action isEqualToString:@"next"]) ok = [_scenarios next:&err];
        else if ([action isEqualToString:@"stop"]) [_scenarios stop];
        else return SLError(400, @"action must be save, delete, start, goto, next or stop");
        if (!ok) return SLError(400, err ?: @"scenario error");
        NSDictionary *run = [_scenarios runInfo];            // nel registro: avvio, cambio di fase, fine
        if ([action isEqualToString:@"start"]) [_sessionLog newSession:run[@"name"]];        // ogni scenario avviato = una sessione del registro
        if ([action isEqualToString:@"start"]) [_sessionLog add:@"phase" text:[NSString stringWithFormat:@"Scenario «%@» avviato · fase %ld: %@", run[@"name"], (long)[run[@"phase"] integerValue] + 1, run[@"phase_name"]] tag:@"scenario_start" by:c[1]];
        else if ([action isEqualToString:@"goto"] || [action isEqualToString:@"next"]) [_sessionLog add:@"phase" text:[NSString stringWithFormat:@"Fase %ld: %@", (long)[run[@"phase"] integerValue] + 1, run[@"phase_name"]] tag:nil by:c[1]];
        else if ([action isEqualToString:@"stop"]) [_sessionLog add:@"phase" text:@"Scenario terminato dall'istruttore" tag:nil by:c[1]];
        NSDictionary *st = [_state stateDictionary];
        NSMutableDictionary *out = [@{@"ok": @YES, @"error": [NSNull null], @"scenario": [_scenarios runInfo], @"state": st, @"revision": st[@"revision"],
                                      @"controller": [_control infoFor:c[0]]} mutableCopy];
        if (saved) out[@"saved"] = saved;
        if (saved || [action isEqualToString:@"delete"]) out[@"scenarios"] = [_scenarios scenarios];
        return [SLHTTPResponse status:200 json:out];
    }
    // Registro della sessione: GET [?since=n] = voci (da n) + riepilogo per il debriefing; GET ?format=text = testo completo;
    // POST {"action":"add","kind":...,"text":...,"tag":...} aggiunge una voce (anche da chi non comanda: un secondo
    // istruttore può annotare); POST {"action":"clear"} svuota (solo chi comanda).
    if ([p isEqualToString:@"/api/v1/log"] && _sessionLog) {
        BOOL post = [m isEqualToString:@"POST"];
        if (!post && ![m isEqualToString:@"GET"]) return SLError(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        NSArray<NSString *> *c = [self clientOf:req];
        if (post) {
            id json = req.body.length ? [NSJSONSerialization JSONObjectWithData:req.body options:0 error:NULL] : nil;
            if (![json isKindOfClass:[NSDictionary class]]) return SLError(400, @"body must be a valid JSON object");
            NSString *action = json[@"action"];
            if ([action isEqual:@"add"]) {
                if (![json[@"text"] isKindOfClass:[NSString class]] || ![[json[@"text"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) return SLError(400, @"log: text is required");
                [_sessionLog add:[json[@"kind"] isKindOfClass:[NSString class]] ? json[@"kind"] : @"note" text:json[@"text"]
                             tag:[json[@"tag"] isKindOfClass:[NSString class]] ? json[@"tag"] : nil by:c ? c[1] : nil];
            } else if ([action isEqual:@"clear"]) {
                deny = [self checkControl:c]; if (deny) return deny;
                [_sessionLog clear];
            } else if ([action isEqual:@"new_session"]) {
                deny = [self checkControl:c]; if (deny) return deny;
                [_sessionLog newSession:[json[@"title"] isKindOfClass:[NSString class]] ? json[@"title"] : nil];
            } else return SLError(400, @"action must be add, new_session or clear");
        } else if (c) [_control seen:c[0]];
        // ?session=N sceglie la sessione (predefinita: quella corrente; "all" = tutte)
        NSInteger since = 0, sid = [_sessionLog currentSession]; BOOL text = NO;
        for (NSString *kv in [req.query ?: @"" componentsSeparatedByString:@"&"]) {
            if ([kv hasPrefix:@"since="]) since = [[kv substringFromIndex:6] integerValue];
            if ([kv isEqualToString:@"format=text"]) text = YES;
            if ([kv hasPrefix:@"session="]) sid = [[kv substringFromIndex:8] isEqualToString:@"all"] ? 0 : [[kv substringFromIndex:8] integerValue];
        }
        if (text) return [SLHTTPResponse status:200 type:@"text/plain; charset=utf-8" data:[[_sessionLog plainTextForSession:sid] dataUsingEncoding:NSUTF8StringEncoding]];
        NSArray *entries = [_sessionLog entriesSince:since session:sid];
        if (entries.count > 400) entries = [entries subarrayWithRange:NSMakeRange(0, 400)];      // a blocchi: il client richiede il resto con since
        NSInteger next = entries.count ? [[entries.lastObject objectForKey:@"i"] integerValue] + 1 : [_sessionLog nextIndex];
        return [SLHTTPResponse status:200 json:@{@"ok": @YES, @"error": [NSNull null], @"log": entries, @"next": @(next),
                                                 @"more": @((BOOL)(entries.count == 400)), @"summary": [_sessionLog summaryForSession:sid ?: [_sessionLog currentSession]],
                                                 @"session": @(sid), @"current_session": @([_sessionLog currentSession]), @"sessions": [_sessionLog sessions]}];
    }
    if ([p isEqualToString:@"/api/v1/nibp/start"]) {
        if (![m isEqualToString:@"POST"]) return SLError(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        NSArray<NSString *> *c = [self clientOf:req];
        deny = [self checkControl:c]; if (deny) return deny;
        NSString *err = nil;
        if (![_state startNibpMeasurementError:&err]) return SLError(409, err);
        return [self okWithState:c[0]];
    }
    if ([p isEqualToString:@"/api/v1/update"] || [p isEqualToString:@"/api/v1/update/chunk"]) return [self handleUpdate:req];
    return SLError(404, @"not found");
}

#pragma mark - Aggiornamenti delle app

static NSString *const kPkgMonitor = @"it.simulafranz.monitor";
static NSArray<NSString *> *SFPackages(void) { return @[@"it.simulafranz.monitor", @"it.simulafranz.controller", @"it.simulafranz.pocket"]; }

// versioni dei pacchetti dei controller conservati sul monitor: {package: version}
- (NSDictionary<NSString *, NSString *> *)storedPackages {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *pkg in SFPackages()) {
        if ([pkg isEqualToString:kPkgMonitor] || !_packagesDir) continue;
        NSString *v = [NSString stringWithContentsOfFile:[_packagesDir stringByAppendingFormat:@"/%@.version", pkg] encoding:NSUTF8StringEncoding error:NULL];
        if (v.length && [[NSFileManager defaultManager] fileExistsAtPath:[_packagesDir stringByAppendingFormat:@"/%@.deb", pkg]]) d[pkg] = v;
    }
    return d;
}

- (SLHTTPResponse *)handleUpdate:(SLHTTPRequest *)req {
    SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
    if (!_packagesDir) return SLError(404, @"updates not available");
    NSString *m = req.method;
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSString *kv in [req.query ?: @"" componentsSeparatedByString:@"&"]) {
        NSRange r = [kv rangeOfString:@"="];
        if (r.location != NSNotFound) q[[kv substringToIndex:r.location]] = [[kv substringFromIndex:r.location + 1] stringByRemovingPercentEncoding] ?: @"";
    }
    if ([req.path isEqualToString:@"/api/v1/update/chunk"]) {
        // un pezzo (max 32 KB, in base64) di un pacchetto conservato: il collegamento diretto porta messaggi piccoli
        if (![m isEqualToString:@"GET"]) return SLError(405, @"method not allowed");
        NSString *pkg = q[@"pkg"];
        if (![SFPackages() containsObject:pkg ?: @""] || [pkg isEqualToString:kPkgMonitor]) return SLError(400, @"unknown package");
        NSString *path = [_packagesDir stringByAppendingFormat:@"/%@.deb", pkg];
        NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        if (!attr) return SLError(404, @"package not stored on this monitor");
        unsigned long long size = attr.fileSize, off = (unsigned long long)MAX(0, [q[@"offset"] longLongValue]);
        if (off > size) return SLError(400, @"offset beyond end");
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
        [fh seekToFileOffset:off];
        NSData *chunk = [fh readDataOfLength:(NSUInteger)MIN(32 * 1024, size - off)]; [fh closeFile];
        return [SLHTTPResponse status:200 json:@{@"ok": @YES, @"package": pkg, @"version": [self storedPackages][pkg] ?: @"",
                                                 @"size": @(size), @"offset": @(off), @"data": [chunk base64EncodedStringWithOptions:0]}];
    }
    if ([m isEqualToString:@"GET"]) {
        return [SLHTTPResponse status:200 json:@{@"ok": @YES, @"package": kPkgMonitor, @"version": _appVersion ?: @"?",
            @"repo": _updateRepo ?: @"", @"installer": @((BOOL)([SFUpdate installerAvailable:@"/usr/libexec/similfranz-monitor-aggiorna"] || _installHandler != nil)),
            @"packages": [self storedPackages]}];
    }
    if (![m isEqualToString:@"POST"]) return SLError(405, @"method not allowed");
    NSString *err = nil;
    NSDictionary *f = [SFUpdate inspectDeb:req.body allowed:SFPackages() error:&err];
    if (!f) return SLError(400, err);
    NSString *pkg = f[@"Package"], *ver = f[@"Version"];
    if ([pkg isEqualToString:kPkgMonitor]) {
        NSString *v = _installHandler ? _installHandler(req.body, &err)
            : [SFUpdate installDeb:req.body package:kPkgMonitor debPath:@"/var/mobile/Library/Caches/similfranz-aggiornamento-monitor.deb"
                            helper:@"/usr/libexec/similfranz-monitor-aggiorna" error:&err];
        if (!v) return SLError(400, err ?: @"installazione non riuscita");
        return [SLHTTPResponse status:202 json:@{@"ok": @YES, @"package": pkg, @"from": _appVersion ?: @"?", @"to": v,
                                                 @"message": @"installazione in corso: il monitor si riapre da solo fra pochi secondi"}];
    }
    // pacchetto di un controller: resta sul monitor, i controller lo prendono da qui
    [[NSFileManager defaultManager] createDirectoryAtPath:_packagesDir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [_packagesDir stringByAppendingFormat:@"/%@.deb", pkg];
    if (![req.body writeToFile:path atomically:YES] ||
        ![ver writeToFile:[_packagesDir stringByAppendingFormat:@"/%@.version", pkg] atomically:YES encoding:NSUTF8StringEncoding error:NULL])
        return SLError(500, @"impossibile salvare il pacchetto");
    return [SLHTTPResponse status:200 json:@{@"ok": @YES, @"package": pkg, @"stored": ver,
                                             @"message": @"conservato sul monitor: i controller lo vedono al prossimo collegamento"}];
}

@end
