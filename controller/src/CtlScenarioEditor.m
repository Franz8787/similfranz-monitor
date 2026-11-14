#import "CtlScenarioEditor.h"
#import "CtlUI.h"

extern NSString *CtlRhythmName(NSString *r);
extern NSString *CtlDescribeBlock(NSString *rhythm, NSDictionary *params, NSDictionary *extra);

static NSArray<NSArray *> *EdParams(void) {   // chiave, titolo, min, max, passo, decimali, valore iniziale
    return @[@[@"heart_rate_bpm", @"FC  bpm", @0, @250, @1, @0, @80], @[@"systolic_mmhg", @"Sistolica  mmHg", @40, @260, @1, @0, @120],
             @[@"diastolic_mmhg", @"Diastolica  mmHg", @20, @160, @1, @0, @80], @[@"spo2_percent", @"SpO₂  %", @0, @100, @1, @0, @97],
             @[@"respiratory_rate_rpm", @"FR  atti/min", @0, @50, @1, @0, @14], @[@"etco2_mmhg", @"EtCO₂  mmHg", @0, @100, @1, @0, @38],
             @[@"temperature_c", @"Temperatura  °C", @30, @43, @0.1, @1, @36.8], @[@"crt_s", @"Refill  s", @0.5, @8, @0.5, @1, @2]];
}
static NSArray<NSNumber *> *EdDurations(void) { return @[@0, @10, @30, @60, @120, @300]; }
static const NSUInteger kMaxPhases = 24;

@interface CtlScenarioEditor () <UITextFieldDelegate, UITextViewDelegate>
@end

@implementation CtlScenarioEditor {
    NSString *_sid; NSDictionary *_current;
    NSMutableArray<NSMutableDictionary *> *_phases; NSInteger _selIdx;
    UITextField *_name, *_phName, *_phNote; UITextView *_notes; UILabel *_notesHint;
    UILabel *_error, *_count;
    UIScrollView *_list, *_form;
    UISegmentedControl *_dur;
    NSMutableDictionary<NSString *, UISwitch *> *_sw; NSMutableDictionary<NSString *, UISlider *> *_sl; NSMutableDictionary<NSString *, UILabel *> *_val;
    NSMutableDictionary<NSString *, CtlButton *> *_rh;
    CtlButton *_del; NSTimeInterval _delArmed;
    NSString *_initName, *_initNotes;
}

- (instancetype)initWithScenario:(NSDictionary *)sc currentBlock:(NSDictionary *)current {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _sid = [sc[@"id"] copy]; _current = [current copy] ?: @{};
        _phases = [NSMutableArray array];
        for (NSDictionary *p in sc[@"phases"]) [_phases addObject:[self mutablePhase:p]];
        if (!_phases.count) [_phases addObject:[self blankPhase]];
        _sw = [NSMutableDictionary dictionary]; _sl = [NSMutableDictionary dictionary]; _val = [NSMutableDictionary dictionary]; _rh = [NSMutableDictionary dictionary];
        _initName = [sc[@"name"] copy]; _initNotes = [sc[@"notes"] copy];
    }
    return self;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (NSMutableDictionary *)mutablePhase:(NSDictionary *)p {
    NSMutableDictionary *m = [p mutableCopy];
    m[@"params"] = [p[@"params"] isKindOfClass:[NSDictionary class]] ? [p[@"params"] mutableCopy] : [NSMutableDictionary dictionary];
    return m;
}
- (NSMutableDictionary *)blankPhase {
    return [@{@"name": @"", @"note": @"", @"duration_s": @0, @"rhythm": @"sinus", @"params": [NSMutableDictionary dictionary]} mutableCopy];
}

- (UITextField *)field:(CGRect)f placeholder:(NSString *)ph in:(UIView *)v ident:(NSString *)ident {
    UITextField *t = [[UITextField alloc] initWithFrame:f];
    t.backgroundColor = CTL_CARD2; t.textColor = CTL_INK; t.font = [UIFont systemFontOfSize:17]; t.layer.cornerRadius = 9;
    t.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)]; t.leftViewMode = UITextFieldViewModeAlways;
    t.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: CTL_INK3}];
    t.clearButtonMode = UITextFieldViewModeWhileEditing; t.returnKeyType = UIReturnKeyDone; t.delegate = self;
    t.keyboardAppearance = UIKeyboardAppearanceDark; t.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    t.accessibilityIdentifier = ident;
    [t addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
    [v addSubview:t];
    return t;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = CTL_BG;
    CGFloat W = 1024;
    CtlButton *cancel = [CtlButton buttonWithTitle:@"Annulla" style:CtlButtonQuiet color:nil frame:CGRectMake(16, 12, 110, 40) target:self action:@selector(cancel)];
    cancel.accessibilityIdentifier = @"ed.cancel"; [self.view addSubview:cancel];
    UILabel *t = CtlLabel(CGRectMake(140, 12, W - 280 - 260, 40), _sid ? @"Modifica lo scenario" : @"Nuovo scenario", 22, YES, CTL_INK); [self.view addSubview:t];
    CtlButton *save = [CtlButton buttonWithTitle:@"Salva sul monitor" style:CtlButtonFilled color:CTL_TINT frame:CGRectMake(W - 16 - 190, 12, 190, 40) target:self action:@selector(save)];
    save.accessibilityIdentifier = @"ed.save"; [self.view addSubview:save];
    if (_sid) {
        _del = [CtlButton buttonWithTitle:@"Elimina scenario" style:CtlButtonTinted color:CTL_RED frame:CGRectMake(W - 16 - 190 - 12 - 200, 12, 200, 40) target:self action:@selector(deleteScenario)];
        _del.titleLabel.font = [UIFont systemFontOfSize:14]; _del.accessibilityIdentifier = @"ed.delete"; [self.view addSubview:_del];
    }
    _name = [self field:CGRectMake(16, 64, 400, 44) placeholder:@"Nome dello scenario" in:self.view ident:@"ed.name"];
    _name.text = _initName; _name.font = [UIFont boldSystemFontOfSize:17];
    _notes = [[UITextView alloc] initWithFrame:CGRectMake(428, 60, W - 444, 52)];           // due righe: paziente, contesto, obiettivi
    _notes.backgroundColor = CTL_CARD2; _notes.textColor = CTL_INK; _notes.font = [UIFont systemFontOfSize:14]; _notes.layer.cornerRadius = 9;
    _notes.textContainerInset = UIEdgeInsetsMake(8, 8, 6, 8); _notes.keyboardAppearance = UIKeyboardAppearanceDark; _notes.delegate = self;
    _notes.accessibilityIdentifier = @"ed.notes"; _notes.text = _initNotes;
    [self.view addSubview:_notes];
    _notesHint = CtlLabel(CGRectMake(442, 60, 400, 34), @"Paziente, contesto, obiettivi (facoltativo)", 14, NO, CTL_INK3); _notesHint.userInteractionEnabled = NO;
    _notesHint.hidden = _initNotes.length > 0; [self.view addSubview:_notesHint];
    _error = CtlLabel(CGRectMake(16, 112, W - 32, 24), @"", 14, YES, CTL_RED); [self.view addSubview:_error];

    UIView *lc = CtlCard(CGRectMake(16, 140, 280, 612)); lc.clipsToBounds = YES; [self.view addSubview:lc];
    [lc addSubview:CtlLabel(CGRectMake(14, 10, 160, 18), @"FASI", 11, YES, CTL_INK2)];
    _count = CtlLabel(CGRectMake(150, 10, 116, 18), @"", 11, NO, CTL_INK3); _count.textAlignment = NSTextAlignmentRight; [lc addSubview:_count];
    _list = [[CtlScrollView alloc] initWithFrame:CGRectMake(0, 32, 280, 612 - 32 - 150)]; _list.indicatorStyle = UIScrollViewIndicatorStyleWhite; [lc addSubview:_list];
    CGFloat fy = 612 - 146;
    NSArray *tools = @[@[@"Su", @"ed.up", NSStringFromSelector(@selector(moveUp))], @[@"Giù", @"ed.down", NSStringFromSelector(@selector(moveDown))],
                       @[@"Duplica", @"ed.dup", NSStringFromSelector(@selector(duplicate))], @[@"Elimina", @"ed.delphase", NSStringFromSelector(@selector(deletePhase))]];
    CGFloat tw = (280 - 20 - 3 * 6) / 4.0; NSUInteger i = 0;
    for (NSArray *tl in tools) {
        CtlButton *b = [CtlButton buttonWithTitle:tl[0] style:i == 3 ? CtlButtonTinted : CtlButtonQuiet color:CTL_RED frame:CGRectMake(10 + i * (tw + 6), fy, tw, 38) target:self action:NSSelectorFromString(tl[2])];
        b.titleLabel.font = [UIFont systemFontOfSize:13]; b.accessibilityIdentifier = tl[1]; [lc addSubview:b]; i++;
    }
    CtlButton *add = [CtlButton buttonWithTitle:@"+ Aggiungi una fase" style:CtlButtonTinted color:CTL_TINT frame:CGRectMake(10, fy + 46, 260, 42) target:self action:@selector(addPhase)];
    add.titleLabel.font = [UIFont boldSystemFontOfSize:14]; add.accessibilityIdentifier = @"ed.add"; [lc addSubview:add];
    CtlButton *snap = [CtlButton buttonWithTitle:@"+ Fase dai valori attuali del paziente" style:CtlButtonTinted color:CTL_GREEN frame:CGRectMake(10, fy + 94, 260, 42) target:self action:@selector(addSnapshot)];
    snap.titleLabel.font = [UIFont boldSystemFontOfSize:13]; snap.accessibilityIdentifier = @"ed.snap"; [lc addSubview:snap];

    UIView *fc = CtlCard(CGRectMake(308, 140, W - 324, 612)); fc.clipsToBounds = YES; [self.view addSubview:fc];
    _form = [[CtlScrollView alloc] initWithFrame:fc.bounds]; _form.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; [fc addSubview:_form];
    [self buildForm];
    [self reloadList]; [self loadPhase];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)buildForm {
    CGFloat W = _form.bounds.size.width, x = 18, w = W - 36, y = 14;
    [_form addSubview:CtlLabel(CGRectMake(x, y, 300, 16), @"NOME DELLA FASE", 11, YES, CTL_INK2)];
    [_form addSubview:CtlLabel(CGRectMake(x + 300, y, w - 300, 16), @"TEMPO DI TRANSIZIONE (quanto ci mette ad arrivare ai valori)", 11, YES, CTL_INK2)];
    y += 20;
    _phName = [self field:CGRectMake(x, y, 284, 40) placeholder:@"es. Peggiora" in:_form ident:@"ed.phname"];
    _dur = [[UISegmentedControl alloc] initWithItems:@[@"Subito", @"10 s", @"30 s", @"1 min", @"2 min", @"5 min"]];
    _dur.frame = CGRectMake(x + 300, y + 4, w - 300, 32); _dur.tintColor = CTL_TINT; _dur.accessibilityIdentifier = @"ed.dur";
    [_dur addTarget:self action:@selector(durChanged) forControlEvents:UIControlEventValueChanged];
    [_form addSubview:_dur];
    y += 52;
    [_form addSubview:CtlLabel(CGRectMake(x, y, w, 16), @"RITMO", 11, YES, CTL_INK2)]; y += 20;
    NSArray *rh = @[@"", @"sinus", @"sinus_tachycardia", @"sinus_bradycardia", @"afib", @"vt_pulse", @"vt", @"vf", @"asystole", @"pea"];
    CGFloat bw = (w - 4 * 6) / 5.0; NSUInteger i = 0;
    for (NSString *r in rh) {
        CtlButton *b = [CtlButton buttonWithTitle:r.length ? CtlRhythmName(r) : @"Non cambia" style:CtlButtonQuiet color:nil frame:CGRectMake(x + (i % 5) * (bw + 6), y + (i / 5) * 48, bw, 42) target:self action:@selector(rhythmTapped:)];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12.5]; b.accessibilityIdentifier = [@"ed.rh." stringByAppendingString:r.length ? r : @"none"];
        [_form addSubview:b]; _rh[r] = b; i++;
    }
    y += 2 * 48 + 8;
    [_form addSubview:CtlLabel(CGRectMake(x, y, w, 16), @"PARAMETRI — acceso = cambia in questa fase, spento = resta com'è", 11, YES, CTL_INK2)]; y += 20;
    for (NSArray *d in EdParams()) {
        NSString *k = d[0];
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(x, y + 6, 51, 31)]; sw.onTintColor = CTL_TINT;
        sw.accessibilityIdentifier = [@"ed.sw." stringByAppendingString:k];
        [sw addTarget:self action:@selector(paramSwitch:) forControlEvents:UIControlEventValueChanged];
        [_form addSubview:sw]; _sw[k] = sw;
        [_form addSubview:CtlLabel(CGRectMake(x + 64, y, 150, 43), d[1], 15, NO, CTL_INK)];
        UILabel *v = CtlLabel(CGRectMake(x + 214, y, 70, 43), @"", 22, YES, CTL_INK); v.font = CtlDigits(22, YES); v.textAlignment = NSTextAlignmentRight; [_form addSubview:v]; _val[k] = v;
        CtlButton *minus = [CtlButton buttonWithTitle:@"−" style:CtlButtonQuiet color:nil frame:CGRectMake(x + 298, y + 2, 44, 39) target:self action:@selector(stepTapped:)];
        CtlButton *plus = [CtlButton buttonWithTitle:@"+" style:CtlButtonQuiet color:nil frame:CGRectMake(x + w - 44, y + 2, 44, 39) target:self action:@selector(stepTapped:)];
        minus.titleLabel.font = plus.titleLabel.font = [UIFont systemFontOfSize:24];
        minus.accessibilityIdentifier = [@"ed.minus." stringByAppendingString:k]; plus.accessibilityIdentifier = [@"ed.plus." stringByAppendingString:k];
        [_form addSubview:minus]; [_form addSubview:plus];
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(x + 352, y + 4, w - 352 - 54, 35)];
        sl.minimumValue = [d[2] floatValue]; sl.maximumValue = [d[3] floatValue]; sl.minimumTrackTintColor = CTL_TINT; sl.maximumTrackTintColor = CTL_CARD2;
        sl.accessibilityIdentifier = [@"ed.sl." stringByAppendingString:k];
        [sl addTarget:self action:@selector(paramSlid:) forControlEvents:UIControlEventValueChanged];
        [_form addSubview:sl]; _sl[k] = sl;
        y += 45;
    }
    y += 8;
    [_form addSubview:CtlLabel(CGRectMake(x, y, w, 16), @"NOTA PER L'ISTRUTTORE (quando passare alla fase successiva)", 11, YES, CTL_INK2)]; y += 20;
    _phNote = [self field:CGRectMake(x, y, w, 40) placeholder:@"es. Avanzare quando hanno somministrato l'ossigeno" in:_form ident:@"ed.phnote"];
    y += 54;
    _form.contentSize = CGSizeMake(W, y);
}

#pragma mark - Dati <-> interfaccia

- (NSMutableDictionary *)phase { return _phases[MAX(0, MIN(_selIdx, (NSInteger)_phases.count - 1))]; }
- (NSArray *)defFor:(NSString *)k { for (NSArray *d in EdParams()) if ([d[0] isEqualToString:k]) return d; return nil; }
- (BOOL)isExtra:(NSString *)k { return [k isEqualToString:@"temperature_c"] || [k isEqualToString:@"crt_s"]; }
- (NSNumber *)valueOf:(NSString *)k in:(NSDictionary *)p { return [self isExtra:k] ? p[k] : p[@"params"][k]; }
- (void)set:(NSNumber *)v key:(NSString *)k {
    NSMutableDictionary *p = [self phase];
    if ([self isExtra:k]) { if (v) p[k] = v; else [p removeObjectForKey:k]; }
    else { if (v) p[@"params"][k] = v; else [p[@"params"] removeObjectForKey:k]; }
}
static NSString *Fmt(NSNumber *v, NSInteger dec) {
    return dec > 0 ? [[NSString stringWithFormat:@"%.*f", (int)dec, v.doubleValue] stringByReplacingOccurrencesOfString:@"." withString:@","] : [NSString stringWithFormat:@"%ld", (long)lround(v.doubleValue)];
}

- (void)loadPhase {
    NSMutableDictionary *p = [self phase];
    _phName.text = p[@"name"]; _phNote.text = p[@"note"];
    NSUInteger di = [EdDurations() indexOfObject:@([p[@"duration_s"] integerValue])];
    _dur.selectedSegmentIndex = di == NSNotFound ? UISegmentedControlNoSegment : (NSInteger)di;
    NSString *cur = p[@"rhythm"] ?: @"";
    for (NSString *r in _rh) [_rh[r] setStyle:[r isEqualToString:cur] ? CtlButtonFilled : CtlButtonQuiet color:CTL_TINT];
    for (NSArray *d in EdParams()) {
        NSString *k = d[0]; NSNumber *v = [self valueOf:k in:p];
        _sw[k].on = v != nil; _sl[k].enabled = v != nil; _sl[k].alpha = v ? 1 : 0.35;
        if (v) _sl[k].value = v.floatValue;
        _val[k].text = v ? Fmt(v, [d[5] integerValue]) : @"—"; _val[k].textColor = v ? CTL_INK : CTL_INK3;
    }
}

- (void)reloadList {
    for (UIView *v in [_list.subviews copy]) [v removeFromSuperview];
    CGFloat y = 4; NSInteger i = 0;
    for (NSDictionary *p in _phases) {
        BOOL on = i == _selIdx;
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(6, y, 268, 74)];
        row.backgroundColor = on ? CTL_CARD2 : [UIColor clearColor]; row.layer.cornerRadius = 9; row.tag = i;
        row.layer.borderWidth = on ? 2 : 0; row.layer.borderColor = CTL_TINT.CGColor;
        row.accessibilityIdentifier = [NSString stringWithFormat:@"ed.row.%ld", (long)i];
        [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        NSString *nm = [p[@"name"] length] ? p[@"name"] : [NSString stringWithFormat:@"Fase %ld", (long)i + 1];
        UILabel *t = CtlLabel(CGRectMake(12, 6, 244, 22), [NSString stringWithFormat:@"%ld.  %@", (long)i + 1, nm], 15, YES, CTL_INK); t.userInteractionEnabled = NO; [row addSubview:t];
        UILabel *s = CtlLabel(CGRectMake(12, 27, 244, 42), CtlDescribeBlock(p[@"rhythm"], p[@"params"], p), 11, NO, CTL_INK2); s.numberOfLines = 3; s.userInteractionEnabled = NO; [row addSubview:s];
        [_list addSubview:row];
        y += 78; i++;
    }
    _list.contentSize = CGSizeMake(280, y + 4);
    _count.text = [NSString stringWithFormat:@"%lu di %lu al massimo", (unsigned long)_phases.count, (unsigned long)kMaxPhases];
}

#pragma mark - Azioni

- (void)rowTapped:(UIControl *)r { [self.view endEditing:YES]; _selIdx = r.tag; [self reloadList]; [self loadPhase]; }
- (void)textChanged:(UITextField *)t {
    if (t == _phName) { [self phase][@"name"] = t.text ?: @""; [self reloadList]; }
    else if (t == _phNote) [self phase][@"note"] = t.text ?: @"";
    _error.text = @"";
}
- (void)textViewDidChange:(UITextView *)tv { _notesHint.hidden = tv.text.length > 0; }
- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)r replacementText:(NSString *)s {
    if ([s isEqualToString:@"\n"]) { [tv resignFirstResponder]; return NO; }
    return tv.text.length - r.length + s.length <= 600;
}
- (BOOL)textFieldShouldReturn:(UITextField *)t { [t resignFirstResponder]; return YES; }
- (BOOL)textField:(UITextField *)t shouldChangeCharactersInRange:(NSRange)r replacementString:(NSString *)s {
    NSUInteger max = t == _name ? 60 : (t == _phName ? 40 : 200);
    return t.text.length - r.length + s.length <= max;
}
- (void)durChanged { [self phase][@"duration_s"] = EdDurations()[_dur.selectedSegmentIndex]; }
- (void)rhythmTapped:(CtlButton *)b {
    NSString *r = [b.accessibilityIdentifier substringFromIndex:6];
    if ([r isEqualToString:@"none"]) [[self phase] removeObjectForKey:@"rhythm"]; else [self phase][@"rhythm"] = r;
    [self loadPhase]; [self reloadList];
}
- (void)paramSwitch:(UISwitch *)sw {
    NSString *k = [sw.accessibilityIdentifier substringFromIndex:6];
    if (sw.on) {
        NSNumber *cur = [self isExtra:k] ? _current[k] : _current[@"params"][k];     // si parte dal valore attuale del paziente
        [self set:[cur isKindOfClass:[NSNumber class]] ? cur : [self defFor:k][6] key:k];
    } else [self set:nil key:k];
    [self loadPhase]; [self reloadList];
}
- (NSNumber *)snap:(double)v key:(NSString *)k {
    NSArray *d = [self defFor:k]; double st = [d[4] doubleValue];
    v = round(v / st) * st; v = MAX([d[2] doubleValue], MIN([d[3] doubleValue], v));
    return [d[5] integerValue] > 0 ? @(round(v * 10) / 10) : @((NSInteger)lround(v));
}
- (void)paramSlid:(UISlider *)sl {
    NSString *k = [sl.accessibilityIdentifier substringFromIndex:6];
    NSNumber *v = [self snap:sl.value key:k];
    [self set:v key:k];
    _val[k].text = Fmt(v, [[self defFor:k][5] integerValue]);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadList) object:nil];
    [self performSelector:@selector(reloadList) withObject:nil afterDelay:0.25];
}
- (void)stepTapped:(CtlButton *)b {
    BOOL plus = [b.accessibilityIdentifier hasPrefix:@"ed.plus."];
    NSString *k = [b.accessibilityIdentifier substringFromIndex:plus ? 8 : 9];
    NSNumber *v = [self valueOf:k in:[self phase]];
    if (!v) { _sw[k].on = YES; [self paramSwitch:_sw[k]]; return; }
    [self set:[self snap:v.doubleValue + (plus ? 1 : -1) * [[self defFor:k][4] doubleValue] key:k] key:k];
    [self loadPhase]; [self reloadList];
}

- (BOOL)room { if (_phases.count >= kMaxPhases) { _error.text = [NSString stringWithFormat:@"Uno scenario può avere al massimo %lu fasi.", (unsigned long)kMaxPhases]; return NO; } return YES; }
- (void)insert:(NSMutableDictionary *)p { [self.view endEditing:YES]; [_phases insertObject:p atIndex:MIN(_selIdx + 1, (NSInteger)_phases.count)]; _selIdx = MIN(_selIdx + 1, (NSInteger)_phases.count - 1); [self reloadList]; [self loadPhase]; }
- (void)addPhase { if ([self room]) { NSMutableDictionary *p = [self blankPhase]; [p removeObjectForKey:@"rhythm"]; [self insert:p]; } }
- (void)addSnapshot {
    if (![self room]) return;
    NSMutableDictionary *p = [self mutablePhase:_current];
    p[@"name"] = @""; p[@"note"] = @""; p[@"duration_s"] = @30;
    [self insert:p];
}
- (void)duplicate { if ([self room]) { NSMutableDictionary *p = [self mutablePhase:[self phase]]; if ([p[@"name"] length]) p[@"name"] = [[p[@"name"] stringByAppendingString:@" (copia)"] substringToIndex:MIN((NSUInteger)40, [p[@"name"] length] + 8)]; [self insert:p]; } }
- (void)deletePhase {
    if (_phases.count <= 1) { _error.text = @"Lo scenario deve avere almeno una fase."; return; }
    [_phases removeObjectAtIndex:_selIdx]; _selIdx = MIN(_selIdx, (NSInteger)_phases.count - 1); [self reloadList]; [self loadPhase];
}
- (void)moveUp { if (_selIdx > 0) { [_phases exchangeObjectAtIndex:_selIdx withObjectAtIndex:_selIdx - 1]; _selIdx--; [self reloadList]; } }
- (void)moveDown { if (_selIdx + 1 < (NSInteger)_phases.count) { [_phases exchangeObjectAtIndex:_selIdx withObjectAtIndex:_selIdx + 1]; _selIdx++; [self reloadList]; } }

- (void)cancel { [self.view endEditing:YES]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)showError:(NSString *)e { _error.text = e ?: @""; }

- (void)save {
    [self.view endEditing:YES];
    NSString *name = [_name.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!name.length) { _error.text = @"Manca il nome dello scenario."; [_name becomeFirstResponder]; return; }
    NSMutableArray *out = [NSMutableArray array]; NSInteger i = 0;
    for (NSDictionary *p in _phases) {
        i++;
        NSDictionary *pr = p[@"params"] ?: @{};
        if (!pr.count && !p[@"rhythm"] && !p[@"temperature_c"] && !p[@"crt_s"]) { _selIdx = i - 1; [self reloadList]; [self loadPhase]; _error.text = [NSString stringWithFormat:@"La fase %ld è vuota: scegli un ritmo o accendi almeno un parametro.", (long)i]; return; }
        NSNumber *s = pr[@"systolic_mmhg"], *d = pr[@"diastolic_mmhg"];
        if (s && d && d.integerValue >= s.integerValue) { _selIdx = i - 1; [self reloadList]; [self loadPhase]; _error.text = [NSString stringWithFormat:@"Fase %ld: la diastolica deve essere più bassa della sistolica.", (long)i]; return; }
        NSMutableDictionary *q = [@{@"name": p[@"name"] ?: @"", @"note": p[@"note"] ?: @"", @"duration_s": p[@"duration_s"] ?: @0, @"params": pr} mutableCopy];
        for (NSString *k in @[@"rhythm", @"temperature_c", @"crt_s"]) if (p[k]) q[k] = p[k];
        [out addObject:q];
    }
    NSMutableDictionary *sc = [@{@"name": name, @"notes": _notes.text ?: @"", @"phases": out} mutableCopy];
    if (_sid) sc[@"id"] = _sid;
    _error.text = @"";
    if (self.onSave) self.onSave(sc);
}

- (void)deleteScenario {
    if (CACurrentMediaTime() < _delArmed) { if (self.onDelete) self.onDelete(_sid); return; }
    _delArmed = CACurrentMediaTime() + 4;
    [_del setTitle:@"Tocca di nuovo: elimina" forState:UIControlStateNormal]; [_del setStyle:CtlButtonFilled color:CTL_RED];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_del setTitle:@"Elimina scenario" forState:UIControlStateNormal]; [self->_del setStyle:CtlButtonTinted color:CTL_RED];
    });
}

// la tastiera non deve coprire il campo che si sta scrivendo (la nota è in fondo al modulo)
- (void)keyboard:(NSNotification *)n {
    BOOL show = [n.name isEqualToString:UIKeyboardWillShowNotification];
    CGRect kb = [self.view convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat overlap = show ? MAX(0, CGRectGetMaxY([_form.superview convertRect:_form.frame toView:self.view]) - kb.origin.y) : 0;
    _form.contentInset = _form.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, overlap, 0);
    if (show && _phNote.isFirstResponder) [_form scrollRectToVisible:CGRectInset(_phNote.frame, 0, -12) animated:YES];
}
@end
