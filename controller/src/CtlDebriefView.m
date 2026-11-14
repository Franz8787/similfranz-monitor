#import "CtlDebriefView.h"
#import "CtlModel.h"
#import "CtlUI.h"
#import <QuartzCore/QuartzCore.h>

NSString *CtlLogKindName(NSString *k) {
    return @{@"phase": @"SCENARIO", @"patient": @"PAZIENTE", @"monitor": @"MONITOR", @"electric": @"ELETTRICA", @"timer": @"TIMER", @"action": @"AZIONE",
             @"drug": @"FARMACO", @"plus": @"PUNTO DI FORZA", @"minus": @"DA DISCUTERE", @"note": @"NOTA"}[k ?: @""] ?: @"NOTA";
}
UIColor *CtlLogKindColor(NSString *k) {
    return @{@"phase": CTL_TINT, @"patient": CTL_INK2, @"monitor": CTL_SPO2, @"electric": CTL_ORANGE, @"timer": CTL_INK3, @"action": CTL_GREEN,
             @"drug": CTL_TEMP, @"plus": CTL_GREEN, @"minus": CTL_RED, @"note": CTL_YELLOW}[k ?: @""] ?: CTL_INK2;
}
static NSString *MMSS(NSInteger s) { return [NSString stringWithFormat:@"%02ld:%02ld", (long)(s / 60), (long)(s % 60)]; }
static NSString *Span(id v) {          // durata leggibile: "12 s", "1 min 05 s"
    if (![v isKindOfClass:[NSNumber class]]) return @"—";
    NSInteger s = [v integerValue];
    return s < 60 ? [NSString stringWithFormat:@"%ld s", (long)s] : [NSString stringWithFormat:@"%ld min %02ld s", (long)s / 60, (long)s % 60];
}

@interface CtlDebriefCell : UITableViewCell
@property (nonatomic, strong) UILabel *time, *kind, *body;
@end
@implementation CtlDebriefCell
- (instancetype)initWithStyle:(UITableViewCellStyle)st reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:st reuseIdentifier:rid])) {
        self.backgroundColor = [UIColor clearColor]; self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.separatorInset = UIEdgeInsetsZero; self.layoutMargins = UIEdgeInsetsZero; self.preservesSuperviewLayoutMargins = NO;
        _time = CtlLabel(CGRectMake(16, 0, 64, 44), @"", 17, YES, CTL_INK); _time.font = CtlDigits(17, YES); [self.contentView addSubview:_time];
        _kind = CtlLabel(CGRectMake(88, 12, 128, 20), @"", 10.5, YES, CTL_INK); _kind.textAlignment = NSTextAlignmentCenter; _kind.layer.cornerRadius = 5; _kind.layer.borderWidth = 1; [self.contentView addSubview:_kind];
        _body = CtlLabel(CGRectMake(230, 0, 740, 44), @"", 16, NO, CTL_INK); _body.numberOfLines = 2; [self.contentView addSubview:_body];
    }
    return self;
}
@end

@interface CtlDebriefView () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation CtlDebriefView {
    CtlModel *_m; UITableView *_table; UIView *_tiles; UISegmentedControl *_filter; UILabel *_empty, *_err;
    NSArray<NSDictionary *> *_rows; CtlButton *_clear, *_sessBtn; NSTimeInterval _clearArmed; NSUInteger _shown;
    NSString *_sig; NSInteger _viewSession; NSArray<NSDictionary *> *_pastEntries; NSDictionary *_pastSummary;      // 0 = sessione corrente (dal vivo)
}
- (instancetype)initWithModel:(CtlModel *)model { if ((self = [super initWithNibName:nil bundle:nil])) _m = model; return self; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = CTL_BG;
    CGFloat W = 1024;
    CtlButton *close = [CtlButton buttonWithTitle:@"Chiudi" style:CtlButtonQuiet color:nil frame:CGRectMake(16, 12, 110, 40) target:self action:@selector(close)];
    close.accessibilityIdentifier = @"deb.close"; [self.view addSubview:close];
    [self.view addSubview:CtlLabel(CGRectMake(142, 12, 230, 40), @"Piano di debriefing", 24, YES, CTL_INK)];
    // quale simulazione si sta guardando: quella in corso oppure una precedente
    _sessBtn = [CtlButton buttonWithTitle:@"Sessione" style:CtlButtonTinted color:CTL_TINT frame:CGRectMake(384, 12, 396, 40) target:self action:@selector(pickSession)];
    _sessBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14]; _sessBtn.maxLines = 1; _sessBtn.accessibilityIdentifier = @"deb.session"; [self.view addSubview:_sessBtn];
    _err = CtlLabel(CGRectMake(142, 44, 640, 18), @"", 12, YES, CTL_RED); [self.view addSubview:_err];
    _clear = [CtlButton buttonWithTitle:@"Svuota il registro" style:CtlButtonTinted color:CTL_RED frame:CGRectMake(W - 16 - 210, 12, 210, 40) target:self action:@selector(clearLog)];
    _clear.titleLabel.font = [UIFont systemFontOfSize:14]; _clear.maxLines = 1; _clear.accessibilityIdentifier = @"deb.clear"; [_clear setIcon:@"trash" above:NO]; [self.view addSubview:_clear];
    _tiles = [[UIView alloc] initWithFrame:CGRectMake(16, 64, W - 32, 196)]; [self.view addSubview:_tiles];
    _filter = [[UISegmentedControl alloc] initWithItems:@[@"Punti chiave", @"Partecipanti", @"Terapia elettrica", @"Farmaci", @"Istruttore", @"Debriefing", @"Tutto"]];
    _filter.frame = CGRectMake(16, 270, W - 32, 34); _filter.tintColor = CTL_TINT; _filter.selectedSegmentIndex = 0; _filter.accessibilityIdentifier = @"deb.filter";
    [_filter addTarget:self action:@selector(reloadRows) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_filter];
    UIView *card = CtlCard(CGRectMake(16, 314, W - 32, 768 - 314 - 16)); card.clipsToBounds = YES; [self.view addSubview:card];
    _table = [[UITableView alloc] initWithFrame:card.bounds style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor]; _table.separatorColor = CTL_LINE; _table.rowHeight = 46; _table.dataSource = self; _table.delegate = self;
    _table.separatorInset = UIEdgeInsetsZero; _table.layoutMargins = UIEdgeInsetsZero; _table.cellLayoutMarginsFollowReadableWidth = NO;
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite; _table.accessibilityIdentifier = @"deb.table";
    [_table registerClass:[CtlDebriefCell class] forCellReuseIdentifier:@"c"];
    [card addSubview:_table];
    _empty = CtlLabel(CGRectInset(card.bounds, 40, 40), @"", 16, NO, CTL_INK3); _empty.numberOfLines = 0; _empty.textAlignment = NSTextAlignmentCenter; [card addSubview:_empty];
    [self reload];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

static NSString *SessLine(NSDictionary *m) {
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.dateFormat = @"d MMM HH:mm"; f.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"]; });
    NSString *t = m[@"title"] ?: @""; if (t.length > 26) t = [[t substringToIndex:25] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"%@ · %@ · %@", [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[m[@"w"] doubleValue]]], t, MMSS([m[@"duration_s"] integerValue])];
}
- (void)pickSession {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sessioni registrate" message:@"Una sessione per ogni simulazione: si apre da sola quando avvii uno scenario o azzeri lo scenario." preferredStyle:UIAlertControllerStyleActionSheet];
    __weak CtlDebriefView *me = self;
    for (NSDictionary *m in [_m.logSessions reverseObjectEnumerator]) {
        if (![m[@"entries"] integerValue] && ![m[@"current"] boolValue]) continue;
        NSInteger sid = [m[@"id"] integerValue]; BOOL cur = [m[@"current"] boolValue];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@%@", cur ? @"In corso · " : @"", SessLine(m)] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [me show:cur ? 0 : sid]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Chiudi questa sessione e aprine una nuova" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { CtlDebriefView *s = me; if (s) { [s->_m newSession:nil]; [s show:0]; } }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = _sessBtn; a.popoverPresentationController.sourceRect = _sessBtn.bounds;
    [self presentViewController:a animated:YES completion:nil];
}
- (void)show:(NSInteger)sid {
    _sig = nil; _viewSession = sid; _pastEntries = nil; _pastSummary = nil; _shown = 0;
    if (sid) { __weak CtlDebriefView *me = self; [_m loadSession:sid done:^(NSArray<NSDictionary *> *e, NSDictionary *sum) { CtlDebriefView *s = me; if (!s || s->_viewSession != sid) return; s->_pastEntries = e; s->_pastSummary = sum; [s reload]; }]; }
    [self reload];
}

- (void)clearLog {
    if (CACurrentMediaTime() < _clearArmed) {
        _clearArmed = 0;
        __weak CtlDebriefView *me = self;
        [_m logClear:^(BOOL ok, NSString *e) { CtlDebriefView *s = me; if (!s) return; s->_err.text = ok ? @"" : e; [s resetClear]; s->_sig = nil; [s reload]; }];
        return;
    }
    _clearArmed = CACurrentMediaTime() + 4;
    [_clear setTitle:@"Tocca di nuovo: svuota" forState:UIControlStateNormal]; [_clear setStyle:CtlButtonFilled color:CTL_RED];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (CACurrentMediaTime() >= self->_clearArmed) [self resetClear]; });
}
- (void)resetClear { [_clear setTitle:@"Svuota il registro" forState:UIControlStateNormal]; [_clear setStyle:CtlButtonTinted color:CTL_RED]; }

- (void)tile:(NSString *)caption value:(NSString *)value detail:(NSString *)detail color:(UIColor *)color frame:(CGRect)f {
    UIView *t = CtlCard(f);
    UILabel *c = CtlLabel(CGRectMake(12, 8, f.size.width - 24, 14), caption, 10.5, YES, CTL_INK2); c.adjustsFontSizeToFitWidth = YES; c.minimumScaleFactor = 0.75; [t addSubview:c];
    UILabel *v = CtlLabel(CGRectMake(12, 24, f.size.width - 24, 38), value, 28, YES, color); v.font = CtlDigits(28, YES); v.adjustsFontSizeToFitWidth = YES; v.minimumScaleFactor = 0.5; [t addSubview:v];
    UILabel *d = CtlLabel(CGRectMake(12, 62, f.size.width - 24, f.size.height - 68), detail, 12, NO, CTL_INK2); d.numberOfLines = 0; [t addSubview:d];
    [d sizeToFit]; d.frame = CGRectMake(12, 62, f.size.width - 24, MIN(d.frame.size.height, f.size.height - 68));
    [_tiles addSubview:t];
}

- (void)reload {
    if (!self.isViewLoaded) return;
    // si ricostruisce solo se è cambiato qualcosa (la regia chiama reload a ogni lettura dello stato)
    NSString *sig = [NSString stringWithFormat:@"%ld|%@|%lu|%lu|%d", (long)_viewSession, _m.log.lastObject[@"i"], (unsigned long)_m.log.count,
                     (unsigned long)_m.logSessions.count, _pastSummary != nil];
    if ([sig isEqualToString:_sig]) return;
    _sig = sig;
    for (UIView *v in [_tiles.subviews copy]) [v removeFromSuperview];
    NSDictionary *s = (_viewSession ? _pastSummary : _m.logSummary) ?: @{};
    NSString *st = @"Sessione in corso";
    for (NSDictionary *m in _m.logSessions) if (_viewSession ? [m[@"id"] integerValue] == _viewSession : [m[@"current"] boolValue]) st = [NSString stringWithFormat:@"%@%@", _viewSession ? @"" : @"In corso · ", SessLine(m)];
    if (![[_sessBtn titleForState:UIControlStateNormal] isEqualToString:st]) [_sessBtn setTitle:st forState:UIControlStateNormal];
    CGFloat W = _tiles.bounds.size.width, g = 8, w = (W - 5 * g) / 6, h1 = 94;
    BOOL arrest = s[@"arrest_at_s"] != nil;
    NSArray *shocks = [s[@"shocks"] isKindOfClass:[NSArray class]] ? s[@"shocks"] : @[], *drugs = [s[@"drugs"] isKindOfClass:[NSArray class]] ? s[@"drugs"] : @[];
    // prima riga: tempi delle azioni critiche (contati dall'arresto)
    NSArray *row1 = @[ @[@"DURATA", MMSS([s[@"duration_s"] integerValue]), [NSString stringWithFormat:@"%@ voci nel registro", s[@"entries"] ?: @0], CTL_INK],
        @[@"ARRESTO CARDIACO", arrest ? MMSS([s[@"arrest_at_s"] integerValue]) : @"—", arrest ? @"minuto di scenario" : @"non registrato", arrest ? CTL_RED : CTL_INK3],
        @[@"RICONOSCIMENTO", Span(s[@"to_recognition_s"]), arrest ? @"dall'arresto" : @"", CTL_GREEN],
        @[@"PRIME COMPRESSIONI", Span(s[@"to_cpr_s"]), arrest ? @"dall'arresto" : @"", CTL_GREEN],
        @[@"PRIMA SCARICA", Span(s[@"to_first_shock_s"]), arrest ? @"dall'arresto" : @"", CTL_ORANGE],
        @[@"ROSC", Span(s[@"to_rosc_s"]), arrest ? @"dall'arresto" : @"", CTL_HR] ];
    for (NSUInteger i = 0; i < row1.count; i++) [self tile:row1[i][0] value:row1[i][1] detail:row1[i][2] color:row1[i][3] frame:CGRectMake(i * (w + g), 0, w, h1)];
    // seconda riga: scariche, farmaci, punti segnati
    NSMutableArray *sh = [NSMutableArray array]; for (NSDictionary *x in shocks) [sh addObject:[NSString stringWithFormat:@"%@ J a %@", x[@"energy_j"], MMSS([x[@"t"] integerValue])]];
    NSMutableArray *dr = [NSMutableArray array]; for (NSDictionary *x in drugs) [dr addObject:[NSString stringWithFormat:@"%@  %@", MMSS([x[@"t"] integerValue]), x[@"text"]]];
    CGFloat y2 = h1 + g, h2 = _tiles.bounds.size.height - y2, w3 = (W - 2 * g) / 3;
    [self tile:@"SCARICHE EROGATE" value:[NSString stringWithFormat:@"%lu", (unsigned long)shocks.count] detail:sh.count ? [sh componentsJoinedByString:@"   ·   "] : @"nessuna" color:CTL_ORANGE frame:CGRectMake(0, y2, w3, h2)];
    [self tile:@"FARMACI" value:[NSString stringWithFormat:@"%lu", (unsigned long)drugs.count] detail:dr.count ? [dr componentsJoinedByString:@"   ·   "] : @"nessuno" color:CTL_TEMP frame:CGRectMake(w3 + g, y2, w3, h2)];
    [self tile:@"SEGNATI DALL'ISTRUTTORE" value:[NSString stringWithFormat:@"%@ · %@", s[@"plus"] ?: @0, s[@"minus"] ?: @0]
        detail:[NSString stringWithFormat:@"%@ punti di forza, %@ da discutere (filtro «Debriefing»)", s[@"plus"] ?: @0, s[@"minus"] ?: @0] color:CTL_INK frame:CGRectMake(2 * (w3 + g), y2, w3, h2)];
    [self reloadRows];
}

- (void)reloadRows {
    // "Punti chiave" (vista di partenza): ciò che serve per discutere — fasi, arresto e ROSC, azioni osservate, scariche,
    // farmaci, punti segnati. Il resto (ogni parametro ritoccato, sonde, timer) resta sotto "Tutto" e negli altri filtri.
    NSArray *sets = @[@[@"KEY"], @[@"monitor", @"electric", @"action"], @[@"electric"], @[@"drug"], @[@"patient", @"phase", @"timer"], @[@"plus", @"minus", @"note"], @[]];
    NSArray *want = sets[MAX(0, _filter.selectedSegmentIndex)];
    BOOL key = [want.firstObject isEqual:@"KEY"];
    NSArray *keyKinds = @[@"phase", @"action", @"drug", @"plus", @"minus", @"note"], *keyTags = @[@"arrest", @"rosc", @"shock", @"monitor_on"];
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *d in (_viewSession ? (_pastEntries ?: @[]) : _m.log)) {
        BOOL ok = key ? ([keyKinds containsObject:d[@"k"]] || [keyTags containsObject:d[@"tag"] ?: @""]) : (!want.count || [want containsObject:d[@"k"]]);
        if (ok) [a addObject:d];
    }
    BOOL atEnd = _table.contentOffset.y >= _table.contentSize.height - _table.bounds.size.height - 60 || _rows.count == 0;
    _rows = a; [_table reloadData];
    _empty.text = a.count ? @"" : (_m.logAvailable ? @"Nessuna voce in questa vista." : @"Questo monitor non ha il registro: va aggiornato similFranz Monitor.");
    if (a.count && atEnd && a.count != _shown) [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)a.count - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    _shown = a.count;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)_rows.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    CtlDebriefCell *c = [t dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    NSDictionary *d = _rows[ip.row]; UIColor *col = CtlLogKindColor(d[@"k"]);
    c.time.text = MMSS([d[@"t"] integerValue]);
    c.kind.text = CtlLogKindName(d[@"k"]); c.kind.textColor = col; c.kind.layer.borderColor = col.CGColor;
    NSString *by = d[@"by"]; BOOL who = by.length && ![by isEqualToString:@"istruttore"];
    c.body.text = who ? [NSString stringWithFormat:@"%@   — %@", d[@"text"], by] : d[@"text"];
    BOOL strong = [d[@"k"] isEqual:@"plus"] || [d[@"k"] isEqual:@"minus"] || [d[@"tag"] isEqual:@"shock"] || [d[@"tag"] isEqual:@"arrest"] || [d[@"tag"] isEqual:@"rosc"];
    c.body.font = strong ? [UIFont boldSystemFontOfSize:16] : [UIFont systemFontOfSize:16];
    c.body.textColor = [d[@"k"] isEqual:@"timer"] ? CTL_INK3 : CTL_INK;
    return c;
}
@end
