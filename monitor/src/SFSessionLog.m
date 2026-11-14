#import "SFSessionLog.h"
#import "SimulationState.h"

static const NSUInteger kMaxEntries = 3000, kMaxSessions = 20;

@implementation SFSessionLog {
    NSString *_path; SimulationState *_state;
    NSMutableArray<NSDictionary *> *_e; NSInteger _next;
    NSDictionary *_prev; NSInteger _lastDefibSeq; BOOL _dirty; NSTimeInterval _savedAt;
    NSMutableArray<NSMutableDictionary *> *_sessions; NSInteger _session; NSTimeInterval _ventLoggedAt;      // {id, title, w}
}

+ (NSArray<NSString *> *)kinds { return @[@"phase", @"patient", @"monitor", @"electric", @"timer", @"action", @"drug", @"plus", @"minus", @"note"]; }

- (instancetype)initWithPath:(NSString *)path state:(SimulationState *)state {
    if ((self = [super init])) {
        _path = [path copy]; _state = state; _e = [NSMutableArray array];
        _sessions = [NSMutableArray array];
        NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        NSArray *entries = [j isKindOfClass:[NSDictionary class]] ? j[@"entries"] : ([j isKindOfClass:[NSArray class]] ? j : nil);   // vecchio formato: solo le voci
        for (id x in entries) if ([x isKindOfClass:[NSDictionary class]] && [x[@"text"] isKindOfClass:[NSString class]]) [_e addObject:[x mutableCopy]];
        if ([j isKindOfClass:[NSDictionary class]]) for (id x in j[@"sessions"]) if ([x isKindOfClass:[NSDictionary class]]) [_sessions addObject:[x mutableCopy]];
        _next = _e.count ? [_e.lastObject[@"i"] integerValue] + 1 : 0;
        if (!_sessions.count) [_sessions addObject:[@{@"id": @1, @"title": @"Sessione libera", @"w": @((long long)[NSDate date].timeIntervalSince1970)} mutableCopy]];
        _session = [_sessions.lastObject[@"id"] integerValue];
        if ([self countIn:_session]) [self add:@"timer" text:@"similFranz Monitor riavviato (il registro è stato conservato)" tag:nil by:nil];
    }
    return self;
}

- (NSUInteger)countIn:(NSInteger)sid { NSUInteger n = 0; for (NSDictionary *d in _e) if ([d[@"s"] integerValue] == sid) n++; return n; }
- (NSInteger)currentSession { @synchronized (self) { return _session; } }

- (NSInteger)newSession:(NSString *)title {
    @synchronized (self) {
        NSString *t = [title isKindOfClass:[NSString class]] && title.length ? (title.length > 60 ? [title substringToIndex:60] : title) : @"Sessione libera";
        NSMutableDictionary *cur = _sessions.lastObject;
        if ([self countIn:_session] == 0) { cur[@"title"] = t; cur[@"w"] = @((long long)[NSDate date].timeIntervalSince1970); _dirty = YES; return _session; }
        _session++;
        [_sessions addObject:[@{@"id": @(_session), @"title": t, @"w": @((long long)[NSDate date].timeIntervalSince1970)} mutableCopy]];
        while (_sessions.count > kMaxSessions) {            // si tengono le ultime: la più vecchia esce con le sue voci
            NSInteger old = [_sessions.firstObject[@"id"] integerValue]; [_sessions removeObjectAtIndex:0];
            [_e filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) { return [d[@"s"] integerValue] != old; }]];
        }
        _dirty = YES;
        return _session;
    }
}

- (NSArray<NSDictionary *> *)sessions {
    @synchronized (self) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *m in _sessions) {
            NSInteger sid = [m[@"id"] integerValue], n = 0, dur = 0;
            for (NSDictionary *d in _e) if ([d[@"s"] integerValue] == sid) { n++; dur = MAX(dur, [d[@"t"] integerValue]); }
            [out addObject:@{@"id": m[@"id"], @"title": m[@"title"] ?: @"", @"w": m[@"w"] ?: @0, @"entries": @(n), @"duration_s": @(dur), @"current": @((BOOL)(sid == _session))}];
        }
        return out;
    }
}

// Salvataggio: si fotografa il registro sotto il lucchetto (altri thread possono aggiungere voci nello stesso momento)
// e lo si scrive su disco in background, così il thread principale non si ferma. Da chiamare SENZA il lucchetto.
- (void)saveIfNeeded:(BOOL)force {
    NSData *d = nil; NSString *path = nil;
    @synchronized (self) {
        if (!_path || !_dirty) return;
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (!force && now - _savedAt < 5) return;
        d = [NSJSONSerialization dataWithJSONObject:@{@"sessions": [[NSArray alloc] initWithArray:_sessions copyItems:YES], @"entries": [[NSArray alloc] initWithArray:_e copyItems:YES]} options:0 error:NULL];
        _dirty = NO; _savedAt = now; path = _path;
    }
    void (^w)(void) = ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        [d writeToFile:path atomically:YES];
    };
    if (force) w(); else dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), w);
}

- (NSDictionary *)add:(NSString *)kind text:(NSString *)text tag:(NSString *)tag by:(NSString *)by {
    if (![text isKindOfClass:[NSString class]]) return nil;
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) return nil;
    if (t.length > 240) t = [t substringToIndex:240];
    if (![[SFSessionLog kinds] containsObject:kind]) kind = @"note";
    @synchronized (self) {
        NSMutableDictionary *d = [@{@"i": @(_next++), @"s": @(_session), @"t": @((NSInteger)_state.snapshot.scenarioTime), @"w": @((long long)[NSDate date].timeIntervalSince1970),
                                    @"k": kind, @"text": t} mutableCopy];
        if ([tag isKindOfClass:[NSString class]] && tag.length && tag.length <= 24) d[@"tag"] = tag;
        if ([by isKindOfClass:[NSString class]] && by.length) d[@"by"] = by.length > 40 ? [by substringToIndex:40] : by;
        [_e addObject:d];
        while (_e.count > kMaxEntries) [_e removeObjectAtIndex:0];
        _dirty = YES;
        return d;
    }
}

- (void)flush { [self saveIfNeeded:YES]; }
- (void)clear {
    @synchronized (self) {
        [_e removeAllObjects]; [_sessions removeAllObjects]; _session++;
        [_sessions addObject:[@{@"id": @(_session), @"title": @"Sessione libera", @"w": @((long long)[NSDate date].timeIntervalSince1970)} mutableCopy]];
        _dirty = YES;
    }
    [self saveIfNeeded:YES];
}
- (NSInteger)nextIndex { @synchronized (self) { return _next; } }
- (NSArray<NSDictionary *> *)entriesSince:(NSInteger)index { return [self entriesSince:index session:0]; }
// sid 0 = tutte le sessioni
- (NSArray<NSDictionary *> *)entriesSince:(NSInteger)index session:(NSInteger)sid {
    @synchronized (self) {
        NSMutableArray *a = [NSMutableArray array];
        for (NSDictionary *d in _e) if ([d[@"i"] integerValue] >= index && (sid == 0 || [d[@"s"] integerValue] == sid)) [a addObject:[d copy]];      // copie: la voce originale può ancora cambiare (etichetta della scarica)
        return a;
    }
}

#pragma mark - Voci automatiche

static NSString *RName(NSString *r) {
    return @{@"sinus": @"sinusale", @"sinus_tachycardia": @"tachicardia sinusale", @"sinus_bradycardia": @"bradicardia sinusale",
             @"afib": @"fibrillazione atriale", @"vt_pulse": @"TV con polso", @"vt": @"TV senza polso", @"vf": @"fibrillazione ventricolare",
             @"asystole": @"asistolia", @"pea": @"PEA"}[r ?: @""] ?: (r ?: @"?");
}
static NSString *SName(NSString *s) {
    return @{@"ecg": @"Elettrodi ECG", @"spo2": @"Sonda SpO₂", @"nibp": @"Bracciale NIBP", @"art": @"Linea arteriosa", @"etco2": @"Capnografia",
             @"temp": @"Sonda temperatura", @"pads": @"Piastre", @"oxi": @"Sensore del saturimetro"}[s] ?: s;
}

- (void)observe {
    NSDictionary *s = [_state stateDictionary];
    NSDictionary *p; @synchronized (self) { p = _prev; _prev = s; }
    if (!p) { NSArray *ev = s[@"defib"][@"events"]; _lastDefibSeq = [ev isKindOfClass:[NSArray class]] ? [[ev.lastObject objectForKey:@"seq"] integerValue] : 0; return; }
#define B(d, k) [d[k] boolValue]
    if (B(s, @"monitor_on") != B(p, @"monitor_on")) [self add:@"monitor" text:B(s, @"monitor_on") ? @"Monitor acceso dai partecipanti" : @"Monitor spento" tag:B(s, @"monitor_on") ? @"monitor_on" : nil by:nil];
    NSDictionary *sn = s[@"sensors"], *pn = p[@"sensors"];
    for (NSString *k in sn) if ([sn[k] boolValue] != [pn[k] boolValue] && ![k isEqualToString:@"pads"])     // le piastre arrivano dagli eventi del defibrillatore
        [self add:@"monitor" text:[NSString stringWithFormat:@"%@: %@", SName(k), [sn[k] boolValue] ? @"applicata" : @"tolta"] tag:nil by:nil];
    // defibrillatore: tutti gli eventi nuovi (carica, scariche, DAE, pacing, sync…), con chi li ha fatti
    NSDictionary *df = s[@"defib"], *pdf = p[@"defib"];
    NSArray *ev = [df[@"events"] isKindOfClass:[NSArray class]] ? df[@"events"] : @[];
    // eventi nuovi = numero progressivo più alto dell'ultimo visto (due eventi uguali nello stesso secondo restano due)
    NSMutableArray<NSMutableDictionary *> *added = [NSMutableArray array];
    for (NSDictionary *x in ev) {
        if ([x[@"seq"] integerValue] <= _lastDefibSeq) continue;
        NSMutableDictionary *d = (NSMutableDictionary *)[self add:@"electric" text:x[@"text"] tag:nil by:[x[@"instructor"] boolValue] ? @"istruttore" : @"partecipanti"];
        if (d) [added addObject:d];
    }
    if (ev.count) _lastDefibSeq = MAX(_lastDefibSeq, [[ev.lastObject objectForKey:@"seq"] integerValue]);
    (void)pdf;      // il cambio di modalità è già fra gli eventi del defibrillatore ("Modalità: manuale")
    NSInteger sc = [df[@"shock_count"] integerValue], psc = [pdf[@"shock_count"] integerValue];
    if (sc > psc) {                      // scarica erogata: la voce porta l'energia e il numero progressivo (per il riepilogo)
        NSMutableDictionary *hit = nil;
        for (NSMutableDictionary *d in added) { NSString *l = [d[@"text"] lowercaseString]; if (!hit && ([l hasPrefix:@"shock"] || [l hasPrefix:@"scarica"] || [l containsString:@"erogat"])) hit = d; }
        if (!hit) for (NSMutableDictionary *d in added) { NSString *l = [d[@"text"] lowercaseString]; if (!hit && ([l containsString:@"scaric"] || [l containsString:@"shock"])) hit = d; }
        if (!hit) hit = (NSMutableDictionary *)[self add:@"electric" text:[NSString stringWithFormat:@"Scarica n. %ld erogata: %@ J", (long)sc, df[@"energy_j"]] tag:nil by:@"partecipanti"];
        @synchronized (self) { hit[@"tag"] = @"shock"; hit[@"energy_j"] = df[@"energy_j"] ?: @0; hit[@"n"] = @(sc); _dirty = YES; }
    }
    if (![s[@"rhythm"] isEqual:p[@"rhythm"]]) [self add:@"patient" text:[@"Ritmo: " stringByAppendingString:RName(s[@"rhythm"])] tag:nil by:nil];
    if (B(s, @"pulse_present") != B(p, @"pulse_present"))
        [self add:@"patient" text:B(s, @"pulse_present") ? @"Il paziente ha di nuovo il polso (ROSC)" : @"Paziente senza polso: arresto cardiaco" tag:B(s, @"pulse_present") ? @"rosc" : @"arrest" by:nil];
    if (B(s, @"cpr_active") != B(p, @"cpr_active")) [self add:@"action" text:B(s, @"cpr_active") ? @"RCP in corso: inizio delle compressioni" : @"RCP: compressioni interrotte" tag:B(s, @"cpr_active") ? @"cpr_start" : @"cpr_stop" by:nil];
    if (B(s, @"simulation_running") != B(p, @"simulation_running")) [self add:@"timer" text:B(s, @"simulation_running") ? @"Scenario ripreso" : @"Scenario in pausa" tag:nil by:nil];
    if ([s[@"nibp_status"] isEqual:@"complete"] && ![p[@"nibp_status"] isEqual:@"complete"])
        [self add:@"monitor" text:[NSString stringWithFormat:@"NIBP misurata: %@/%@", s[@"nibp_last_systolic_mmhg"], s[@"nibp_last_diastolic_mmhg"]] tag:nil by:nil];
    else if ([s[@"nibp_status"] isEqual:@"measuring"] && ![p[@"nibp_status"] isEqual:@"measuring"]) [self add:@"monitor" text:@"Misura NIBP avviata" tag:nil by:nil];
    else if ([s[@"nibp_status"] isEqual:@"error"] && ![p[@"nibp_status"] isEqual:@"error"]) [self add:@"monitor" text:@"Misura NIBP non riuscita" tag:nil by:nil];
    if (B(s, @"alarms_muted") && !B(p, @"alarms_muted")) [self add:@"monitor" text:@"Allarmi silenziati" tag:nil by:nil];
    if (![s[@"layout"] isEqual:p[@"layout"]]) [self add:@"monitor" text:@"Layout del monitor cambiato" tag:nil by:nil];
#undef B
    [self saveIfNeeded:NO];
}

- (void)noteCommand:(NSDictionary *)c by:(NSString *)by {
    NSString *n = c[@"command"]; id v = c[@"value"];
    if (![n isKindOfClass:[NSString class]]) return;
    NSDictionary *names = @{@"heart_rate_bpm": @"FC", @"spo2_percent": @"SpO₂", @"systolic_mmhg": @"PAs", @"diastolic_mmhg": @"PAd", @"respiratory_rate_rpm": @"FR", @"etco2_mmhg": @"EtCO₂"};
    NSString *text = nil, *kind = @"patient";
    if ([n isEqualToString:@"transition"] && [v isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *a = [NSMutableArray array];
        NSDictionary *pr = [v[@"params"] isKindOfClass:[NSDictionary class]] ? v[@"params"] : @{};
        for (NSString *k in @[@"heart_rate_bpm", @"systolic_mmhg", @"diastolic_mmhg", @"spo2_percent", @"respiratory_rate_rpm", @"etco2_mmhg"]) if (pr[k]) [a addObject:[NSString stringWithFormat:@"%@ %@", names[k], pr[k]]];
        NSInteger d = [v[@"duration_s"] integerValue];
        if (a.count) text = [NSString stringWithFormat:@"Parametri: %@ (%@)", [a componentsJoinedByString:@", "], d > 0 ? [NSString stringWithFormat:@"in %ld s", (long)d] : @"subito"];
    }
    else if ([n isEqualToString:@"set_heart_rate"]) text = [NSString stringWithFormat:@"Parametri: FC %@", v];
    else if ([n isEqualToString:@"set_spo2"]) text = [NSString stringWithFormat:@"Parametri: SpO₂ %@", v];
    else if ([n isEqualToString:@"set_resp_rate"]) text = [NSString stringWithFormat:@"Parametri: FR %@", v];
    else if ([n isEqualToString:@"set_etco2"]) text = [NSString stringWithFormat:@"Parametri: EtCO₂ %@", v];
    else if (([n isEqualToString:@"set_bp"] || [n isEqualToString:@"set_nibp"]) && [v isKindOfClass:[NSDictionary class]]) text = [NSString stringWithFormat:@"Parametri: PA %@/%@", v[@"systolic"], v[@"diastolic"]];
    else if ([n isEqualToString:@"set_temperature"]) text = [NSString stringWithFormat:@"Parametri: temperatura %@ °C", v];
    else if ([n isEqualToString:@"ventilate"]) {        // le insufflazioni si raggruppano: una voce ogni ciclo, non ogni tocco
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (now - _ventLoggedAt < 20) return;
        _ventLoggedAt = now; text = @"Ventilazioni (CO₂ a monitor)"; kind = @"action";
    }
    else if ([n isEqualToString:@"assess_crt"]) { text = @"Refill valutato su richiesta (fatto misurare dall'istruttore)"; kind = @"action"; }
    else if ([n isEqualToString:@"set_crt"]) text = [NSString stringWithFormat:@"Parametri: refill %@ s", v];
    else if ([n isEqualToString:@"reset_clock"]) { text = @"Timer di scenario azzerato"; kind = @"timer"; }
    else if ([n isEqualToString:@"reset_scenario"]) { [self newSession:nil]; @synchronized (self) { _prev = nil; } return; }      // azzeramento = sessione nuova; i cambi provocati dall'azzeramento stesso (ritmo, polso) non sono voci
    else if ([n isEqualToString:@"defib_outcome"]) { text = [NSString stringWithFormat:@"Esito della scarica deciso dall'istruttore: %@", [v isEqual:@"stay"] ? @"nessun cambiamento" : RName(v)]; kind = @"electric"; }
    if (text) [self add:kind text:text tag:nil by:by];
}

#pragma mark - Riepilogo per il debriefing

- (NSDictionary *)summary { return [self summaryForSession:[self currentSession]]; }
- (NSDictionary *)summaryForSession:(NSInteger)sid {
    @synchronized (self) {
        NSMutableArray<NSDictionary *> *_e = [NSMutableArray array];          // solo le voci della sessione chiesta
        for (NSDictionary *d in self->_e) if ([d[@"s"] integerValue] == sid) [_e addObject:d];
        NSMutableDictionary *first = [NSMutableDictionary dictionary];     // tag -> tempo della prima voce dopo l'ultimo azzeramento
        NSMutableArray *shocks = [NSMutableArray array], *drugs = [NSMutableArray array];
        NSInteger plus = 0, minus = 0, last = 0;
        for (NSDictionary *d in _e) {
            NSString *tag = d[@"tag"];
            if (tag && !first[tag]) first[tag] = d[@"t"];
            if ([tag isEqual:@"shock"]) [shocks addObject:@{@"t": d[@"t"], @"energy_j": d[@"energy_j"] ?: @0}];
            if ([d[@"k"] isEqual:@"drug"]) [drugs addObject:@{@"t": d[@"t"], @"text": d[@"text"]}];
            if ([d[@"k"] isEqual:@"plus"]) plus++;
            if ([d[@"k"] isEqual:@"minus"]) minus++;
            last = MAX(last, [d[@"t"] integerValue]);        // durata = tempo di scenario più alto raggiunto
        }
        NSMutableDictionary *out = [@{@"entries": @(_e.count), @"duration_s": @(last), @"shocks": shocks, @"drugs": drugs, @"plus": @(plus), @"minus": @(minus)} mutableCopy];
        NSNumber *arrest = first[@"arrest"];
        if (arrest) {
            out[@"arrest_at_s"] = arrest;
            // tempi delle azioni critiche contati dall'arresto
            for (NSArray *m in @[@[@"ac", @"to_recognition_s"], @[@"help", @"to_help_s"], @[@"cpr_start", @"to_cpr_s"], @[@"shock", @"to_first_shock_s"], @[@"rosc", @"to_rosc_s"]]) {
                NSNumber *t = nil;
                for (NSDictionary *d in _e) if ([d[@"tag"] isEqual:m[0]] && [d[@"t"] integerValue] >= arrest.integerValue) { t = d[@"t"]; break; }
                if (t) out[m[1]] = @(t.integerValue - arrest.integerValue);
            }
        }
        return out;
    }
}

- (NSString *)plainText { return [self plainTextForSession:0]; }
- (NSString *)plainTextForSession:(NSInteger)sid {
    @synchronized (self) {
        NSMutableArray<NSDictionary *> *_e = [NSMutableArray array];
        for (NSDictionary *d in self->_e) if (sid == 0 || [d[@"s"] integerValue] == sid) [_e addObject:d];
        NSInteger shownSession = -1;
        NSDictionary *kn = @{@"phase": @"SCENARIO", @"patient": @"PAZIENTE", @"monitor": @"MONITOR", @"electric": @"TERAPIA ELETTRICA", @"timer": @"TIMER", @"action": @"AZIONE",
                             @"drug": @"FARMACO", @"plus": @"PUNTO DI FORZA", @"minus": @"DA DISCUTERE", @"note": @"NOTA"};
        static NSDateFormatter *f; static dispatch_once_t once; dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss"; });
        NSMutableString *s = [NSMutableString stringWithString:@"similFranz — registro della sessione\n\n"];
        for (NSDictionary *d in _e) {
            NSInteger t = [d[@"t"] integerValue];
            if ([d[@"s"] integerValue] != shownSession) {
                shownSession = [d[@"s"] integerValue];
                NSString *title = @""; for (NSDictionary *m in _sessions) if ([m[@"id"] integerValue] == shownSession) title = m[@"title"];
                [s appendFormat:@"\n=== Sessione %ld · %@ ===\n", (long)shownSession, title];
            }
            [s appendFormat:@"%02ld:%02ld  %@  %-17s %@%@\n", (long)t / 60, (long)t % 60, [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[d[@"w"] doubleValue]]],
             [kn[d[@"k"]] ?: @"" UTF8String], d[@"text"], d[@"by"] ? [NSString stringWithFormat:@"  (%@)", d[@"by"]] : @""];
        }
        return s;
    }
}
@end
