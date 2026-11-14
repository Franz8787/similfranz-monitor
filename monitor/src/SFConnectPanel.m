#import "SFConnectPanel.h"
#import "SFWifi.h"
#import "SFLog.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <objc/message.h>

#define CP_WHITE  [UIColor colorWithWhite:0.95 alpha:1]
#define CP_GREY   [UIColor colorWithWhite:0.62 alpha:1]
#define CP_DIM    [UIColor colorWithWhite:0.42 alpha:1]
#define CP_CARD   [UIColor colorWithWhite:0.13 alpha:1]
#define CP_CYAN   [UIColor colorWithRed:0.24 green:0.86 blue:1.00 alpha:1]
#define CP_GREEN  [UIColor colorWithRed:0.24 green:1.00 blue:0.43 alpha:1]
#define CP_AMBER  [UIColor colorWithRed:1.00 green:0.75 blue:0.10 alpha:1]
#define CP_RED    [UIColor colorWithRed:1.00 green:0.35 blue:0.30 alpha:1]

static const CGFloat kPW = 940, kPH = 664;
static const NSInteger kMaxRows = 8;

@implementation SFConnectPanel {
    UIView *_main, *_wifi;
    UILabel *_version, *_ctl;
    UILabel *_net, *_url, *_webText;
    UILabel *_directName, *_directStatus;
    UILabel *_pin, *_diag;
    // pagina Reti Wi-Fi
    UILabel *_wifiStatus; UIView *_wifiList; NSArray<SFWifiNetwork *> *_rows;
    NSString *_statusText; NSInteger _statusKind;      // 0 info, 1 in corso, 2 riuscito, 3 errore
}

#pragma mark - Costruzione

- (UILabel *)label:(CGRect)f in:(UIView *)v size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)c {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = c; l.numberOfLines = 0; l.backgroundColor = [UIColor clearColor];
    [v addSubview:l];
    return l;
}

- (UIButton *)button:(NSString *)title frame:(CGRect)f in:(UIView *)v color:(UIColor *)c action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:c forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.layer.borderColor = c.CGColor; b.layer.borderWidth = 1.5; b.layer.cornerRadius = 6;
    b.accessibilityIdentifier = title;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:b];
    return b;
}

- (UIView *)card:(CGRect)f in:(UIView *)v {
    UIView *c = [[UIView alloc] initWithFrame:f];
    c.backgroundColor = CP_CARD;
    c.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1].CGColor; c.layer.borderWidth = 1; c.layer.cornerRadius = 8;
    [v addSubview:c];
    return c;
}

- (instancetype)initWithFrame:(CGRect)screen {
    CGRect f = CGRectMake(floor((screen.size.width - kPW) / 2), floor((screen.size.height - kPH) / 2), kPW, kPH);
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];          // opaco: nessuna trasparenza sopra le onde
        self.layer.borderColor = CP_GREY.CGColor; self.layer.borderWidth = 1; self.layer.cornerRadius = 10;
        _lastInteraction = CACurrentMediaTime();
        [self buildMain];
        [self buildWifi];
        _wifi.hidden = YES;
    }
    return self;
}

- (void)buildMain {
    _main = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_main];
    [self label:CGRectMake(20, 12, 520, 34) in:_main size:25 bold:YES color:CP_WHITE].text = @"Collegamento del controller";
    _version = [self label:CGRectMake(kPW - 420, 18, 400, 22) in:_main size:13 bold:NO color:CP_GREY];
    _version.textAlignment = NSTextAlignmentRight;

    // chi comanda adesso
    UIView *strip = [self card:CGRectMake(20, 56, kPW - 40, 42) in:_main];
    _ctl = [self label:CGRectMake(14, 0, strip.bounds.size.width - 28, 42) in:strip size:17 bold:YES color:CP_GREY];
    _ctl.numberOfLines = 1; _ctl.adjustsFontSizeToFitWidth = YES; _ctl.minimumScaleFactor = 0.7;

    CGFloat cy = 110, ch = 384, cw = (kPW - 60) / 2;
    // --- 1 · regia web, solo dal computer sulla stessa rete (niente QR: telefoni e tablet non la aprono) ---
    UIView *a = [self card:CGRectMake(20, cy, cw, ch) in:_main];
    [self label:CGRectMake(16, 10, cw - 32, 26) in:a size:20 bold:YES color:CP_CYAN].text = @"1 · Regia web, dal computer";
    [self label:CGRectMake(16, 38, cw - 32, 20) in:a size:14 bold:NO color:CP_GREY].text = @"Il computer deve essere sulla stessa rete Wi-Fi di questo iPad.";
    [self label:CGRectMake(16, 68, 50, 24) in:a size:16 bold:NO color:CP_GREY].text = @"Rete:";
    _net = [self label:CGRectMake(64, 68, cw - 80, 24) in:a size:18 bold:YES color:CP_WHITE];
    _net.numberOfLines = 1; _net.adjustsFontSizeToFitWidth = YES; _net.minimumScaleFactor = 0.6;
    [self label:CGRectMake(16, 112, cw - 32, 20) in:a size:13 bold:YES color:CP_GREY].text = @"SUL COMPUTER, NEL BROWSER";
    _webText = [self label:CGRectMake(16, 132, cw - 32, 44) in:a size:15 bold:NO color:CP_WHITE];
    _url = [self label:CGRectMake(16, 180, cw - 32, 44) in:a size:30 bold:YES color:CP_CYAN];
    _url.numberOfLines = 1; _url.adjustsFontSizeToFitWidth = YES; _url.minimumScaleFactor = 0.5;
    [self label:CGRectMake(16, 228, cw - 32, 20) in:a size:15 bold:NO color:CP_GREY].text = @"e poi il PIN qui sotto.";
    [self label:CGRectMake(16, 282, cw - 32, 92) in:a size:14 bold:NO color:CP_GREY].text =
        @"La regia web si usa solo dal computer: da telefono e tablet non si apre. "
         "In mano usa le app del riquadro 2: Controller su iPad, Pocket su iPod touch.";

    // --- 2 · diretto, senza rete ---
    UIView *b = [self card:CGRectMake(40 + cw, cy, cw, ch) in:_main];
    [self label:CGRectMake(16, 10, cw - 32, 26) in:b size:20 bold:YES color:CP_CYAN].text = @"2 · App regia, diretto";
    [self label:CGRectMake(16, 38, cw - 32, 20) in:b size:14 bold:NO color:CP_GREY].text = @"Controller su iPad e Pocket su iPod touch.";
    [self label:CGRectMake(16, 68, cw - 32, 110) in:b size:15 bold:NO color:CP_WHITE].text =
        @"Non serve nessuna rete: basta che i dispositivi siano vicini e abbiano Wi-Fi e Bluetooth accesi "
         "(anche senza essere collegati a una rete).\n\nNell'app scegliere il monitor con questo nome:";
    _directName = [self label:CGRectMake(16, 186, cw - 32, 40) in:b size:24 bold:YES color:CP_WHITE];
    _directName.numberOfLines = 1; _directName.adjustsFontSizeToFitWidth = YES; _directName.minimumScaleFactor = 0.5;
    [self label:CGRectMake(16, 250, cw - 32, 20) in:b size:13 bold:YES color:CP_GREY].text = @"STATO";
    _directStatus = [self label:CGRectMake(16, 270, cw - 32, 104) in:b size:17 bold:YES color:CP_GREY];
    _directStatus.lineBreakMode = NSLineBreakByWordWrapping;

    // --- PIN, uguale per tutti i canali ---
    UIView *p = [self card:CGRectMake(20, 506, kPW - 40, 80) in:_main];
    [self label:CGRectMake(16, 0, 60, 80) in:p size:20 bold:YES color:CP_GREY].text = @"PIN";
    _pin = [self label:CGRectMake(76, 0, 330, 80) in:p size:54 bold:YES color:CP_WHITE];
    _pin.font = [UIFont fontWithName:@"Menlo-Bold" size:54] ?: [UIFont boldSystemFontOfSize:54];
    _pin.numberOfLines = 1; _pin.adjustsFontSizeToFitWidth = YES; _pin.minimumScaleFactor = 0.4;
    [self label:CGRectMake(420, 0, kPW - 40 - 436, 80) in:p size:14 bold:NO color:CP_GREY].text =
        @"È lo stesso per la web app e per l'app controller, con o senza rete.\n"
         "Comanda un solo controller alla volta: un secondo controller può prendere il comando, e il primo viene avvisato.";

    _diag = [self label:CGRectMake(20, 598, 420, 54) in:_main size:12 bold:NO color:CP_DIM];
    [self button:@"Reti Wi-Fi…" frame:CGRectMake(kPW - 20 - 3 * 150 - 20, 604, 150, 46) in:_main color:CP_CYAN action:@selector(showWifi)];
    [self button:@"Volumi…" frame:CGRectMake(kPW - 20 - 2 * 150 - 10, 604, 150, 46) in:_main color:CP_CYAN action:@selector(volumes)];
    [self button:@"Chiudi" frame:CGRectMake(kPW - 20 - 150, 604, 150, 46) in:_main color:CP_GREY action:@selector(close)];
}

- (void)buildWifi {
    _wifi = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_wifi];
    [self label:CGRectMake(20, 12, 520, 34) in:_wifi size:25 bold:YES color:CP_WHITE].text = @"Reti Wi-Fi";
    UILabel *hint = [self label:CGRectMake(kPW - 520, 18, 500, 22) in:_wifi size:13 bold:NO color:CP_GREY];
    hint.textAlignment = NSTextAlignmentRight;
    hint.text = @"Toccare una rete per collegare l'iPad alla stessa rete del controller.";
    UIView *box = [self card:CGRectMake(20, 56, kPW - 40, 52) in:_wifi];
    _wifiStatus = [self label:CGRectMake(14, 0, box.bounds.size.width - 28, 52) in:box size:16 bold:YES color:CP_GREY];
    _wifiStatus.numberOfLines = 2; _wifiStatus.adjustsFontSizeToFitWidth = YES; _wifiStatus.minimumScaleFactor = 0.7;
    _wifiList = [[UIView alloc] initWithFrame:CGRectMake(20, 120, kPW - 40, kMaxRows * 58)];
    [_wifi addSubview:_wifiList];
    [self button:@"Aggiorna elenco" frame:CGRectMake(20, 604, 190, 46) in:_wifi color:CP_CYAN action:@selector(rescan)];
    [self button:@"Impostaz. iPad" frame:CGRectMake(220, 604, 190, 46) in:_wifi color:CP_GREY action:@selector(openSettings)];
    [self button:@"Indietro" frame:CGRectMake(kPW - 20 - 150, 604, 150, 46) in:_wifi color:CP_GREY action:@selector(showMain)];
}

#pragma mark - Tocchi

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v) _lastInteraction = CACurrentMediaTime();
    return v;
}

- (BOOL)busy { return !_wifi.hidden || [SFWifi shared].joining; }
- (void)close { [self showMain]; if (self.onClose) self.onClose(); }
- (void)volumes { if (self.onVolumes) self.onVolumes(); }

#pragma mark - Pagina principale

- (void)refresh {
    NSDictionary *d = self.info ? self.info() : @{};
    NSString *ip = d[@"ip"], *pin = d[@"pin"] ?: @"?";
    NSInteger port = [d[@"port"] integerValue] ?: 8080;
    _version.text = [NSString stringWithFormat:@"similFranz Monitor %@  ·  %@", d[@"version"] ?: @"", d[@"deviceId"] ?: @""];

    NSDictionary *c = d[@"controller"];
    if (c) {
        _ctl.text = [NSString stringWithFormat:@"Controller attivo:  %@  ·  %@", c[@"name"],
                     [c[@"transport"] isEqualToString:@"direct"] ? @"collegamento diretto" : @"rete Wi-Fi"];
        _ctl.textColor = CP_GREEN;
    } else {
        _ctl.text = @"Controller attivo:  nessuno  —  il primo che si collega con il PIN prende il comando";
        _ctl.textColor = CP_GREY;
    }

    NSString *ssid = [[SFWifi shared] currentSSID];
    if (ip) { _net.text = ssid.length ? ssid : @"collegata"; _net.textColor = CP_WHITE; }
    else { _net.text = @"nessuna — toccare «Reti Wi-Fi…»"; _net.textColor = CP_AMBER; }
    NSString *url = ip ? [NSString stringWithFormat:@"http://%@:%ld", ip, (long)port] : nil;
    _webText.text = ip ? @"Apri il browser del computer e scrivi questo indirizzo:"
                       : @"Prima collega questo iPad a una rete Wi-Fi («Reti Wi-Fi…»), la stessa del computer.";
    _url.text = url ?: @"";

    _directName.text = d[@"directName"] ?: @"";
    NSArray *peers = d[@"peers"];
    if (peers.count) {
        _directStatus.text = [@"Collegato:  " stringByAppendingString:[peers componentsJoinedByString:@", "]];
        _directStatus.textColor = CP_GREEN;
    } else if ([d[@"directOn"] boolValue]) {
        _directStatus.text = @"Pronto: in attesa dell'app controller"; _directStatus.textColor = CP_GREY;
    } else {
        _directStatus.text = [NSString stringWithFormat:@"Non disponibile%@", d[@"directError"] ? [@": " stringByAppendingString:d[@"directError"]] : @""];
        _directStatus.textColor = CP_AMBER;
    }

    // PIN con le cifre distanziate (leggibile da lontano)
    NSMutableString *sp = [NSMutableString string];
    for (NSUInteger i = 0; i < pin.length; i++) [sp appendFormat:@"%@%C", (i && i % 3 == 0) ? @" " : @"", [pin characterAtIndex:i]];
    _pin.text = sp;
    _diag.text = [NSString stringWithFormat:@"Server: %@\nAudio: %@\nSIMULAZIONE — NON PER USO CLINICO", d[@"serverStatus"] ?: @"?", d[@"audio"] ?: @"?"];
    if (!_wifi.hidden) [self refreshWifiStatus];
}

#pragma mark - Pagina Reti Wi-Fi

- (void)showMain { _wifi.hidden = YES; _main.hidden = NO; [SFWifi shared].onChange = nil; [self refresh]; }

- (void)showWifi {
    SFWifi *w = [SFWifi shared];
    _main.hidden = YES; _wifi.hidden = NO;
    _statusText = nil; _statusKind = 0;
    __weak SFConnectPanel *me = self;
    w.onChange = ^{ [me rebuildRows]; [me refreshWifiStatus]; };
    [self rebuildRows]; [self refreshWifiStatus];
    if (w.available) [w scan];
}

- (void)rescan { _statusText = nil; _statusKind = 0; [[SFWifi shared] scan]; [self refreshWifiStatus]; }

- (void)setStatus:(NSString *)t kind:(NSInteger)k { _statusText = [t copy]; _statusKind = k; [self refreshWifiStatus]; }

- (void)refreshWifiStatus {
    SFWifi *w = [SFWifi shared];
    NSString *t = _statusText; NSInteger k = _statusKind;
    if (!w.available) { t = @"Elenco delle reti non disponibile su questo iPad: usare «Impostaz. iPad»."; k = 3; }
    else if (w.joining) { t = [NSString stringWithFormat:@"Collegamento a «%@» in corso…", w.joiningSSID]; k = 1; }
    else if (!t && w.scanning) { t = @"Ricerca delle reti in corso…"; k = 1; }
    else if (!t && w.lastError) { t = w.lastError; k = 3; }
    else if (!t) {
        NSString *cur = [w currentSSID];
        t = cur.length ? [NSString stringWithFormat:@"L'iPad è collegato a «%@».", cur] : @"L'iPad non è collegato a nessuna rete.";
    }
    _wifiStatus.text = t;
    _wifiStatus.textColor = k == 1 ? CP_AMBER : (k == 2 ? CP_GREEN : (k == 3 ? CP_RED : CP_GREY));
}

- (void)rebuildRows {
    for (UIView *v in [_wifiList.subviews copy]) [v removeFromSuperview];
    NSArray<SFWifiNetwork *> *nets = [SFWifi shared].networks;
    if (nets.count > kMaxRows) nets = [nets subarrayWithRange:NSMakeRange(0, kMaxRows)];
    _rows = nets;
    CGFloat w = _wifiList.bounds.size.width;
    if (!nets.count) {
        UILabel *e = [self label:CGRectMake(0, 20, w, 60) in:_wifiList size:16 bold:NO color:CP_GREY];
        e.textAlignment = NSTextAlignmentCenter;
        e.text = [SFWifi shared].scanning ? @"" : @"Nessuna rete trovata. Accendere l'hub o l'hotspot e toccare «Aggiorna elenco».";
        return;
    }
    [nets enumerateObjectsUsingBlock:^(SFWifiNetwork *n, NSUInteger i, BOOL *stop) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(0, i * 58, w, 50); b.tag = (NSInteger)i;
        b.backgroundColor = n.current ? [UIColor colorWithRed:0.08 green:0.22 blue:0.12 alpha:1] : CP_CARD;
        b.layer.borderColor = (n.current ? CP_GREEN : [UIColor colorWithWhite:0.28 alpha:1]).CGColor; b.layer.borderWidth = 1; b.layer.cornerRadius = 6;
        b.accessibilityIdentifier = [@"RETE:" stringByAppendingString:n.ssid];
        [b addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILabel *name = [self label:CGRectMake(16, 0, w - 380, 50) in:b size:19 bold:YES color:CP_WHITE];
        name.text = n.ssid; name.numberOfLines = 1; name.lineBreakMode = NSLineBreakByTruncatingMiddle; name.userInteractionEnabled = NO;
        // tacche del segnale disegnate (niente simboli emoji)
        for (NSInteger k = 0; k < 3; k++) {
            UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(w - 350 + k * 10, 32 - k * 7, 7, 8 + k * 7)];
            bar.backgroundColor = k < n.bars ? CP_WHITE : [UIColor colorWithWhite:0.3 alpha:1]; bar.userInteractionEnabled = NO;
            [b addSubview:bar];
        }
        UILabel *det = [self label:CGRectMake(w - 300, 0, 284, 50) in:b size:15 bold:NO color:n.current ? CP_GREEN : CP_GREY];
        det.textAlignment = NSTextAlignmentRight; det.numberOfLines = 1; det.userInteractionEnabled = NO;
        det.text = [NSString stringWithFormat:@"%@  ·  %@", n.channel > 14 ? @"5 GHz" : @"2,4 GHz",
                    n.current ? @"collegata" : (n.known ? @"salvata" : (n.secured ? @"con password" : @"aperta"))];
        [self->_wifiList addSubview:b];
    }];
}

- (void)rowTapped:(UIButton *)b {
    if (b.tag < 0 || b.tag >= (NSInteger)_rows.count) return;
    SFWifiNetwork *n = _rows[b.tag];
    if (n.current) { [self setStatus:[NSString stringWithFormat:@"L'iPad è già collegato a «%@».", n.ssid] kind:2]; return; }
    if (n.known || !n.secured) { [self join:n password:nil]; return; }
    [self askPassword:n];
}

- (void)join:(SFWifiNetwork *)n password:(NSString *)pw {
    _statusText = nil; _statusKind = 0;
    __weak SFConnectPanel *me = self;
    [[SFWifi shared] join:n password:pw completion:^(BOOL ok, NSString *error) {
        if (ok) {
            [me setStatus:[NSString stringWithFormat:@"Collegato a «%@». La rete resta salvata: alla prossima accensione l'iPad si ricollega da solo.", n.ssid] kind:2];
            // l'esito resta visibile un paio di secondi, poi si torna alla pagina con QR e indirizzo
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SFConnectPanel *p = me; if (p && !p->_wifi.hidden && p->_statusKind == 2) [p showMain];
            });
        } else {
            [me setStatus:[NSString stringWithFormat:@"«%@»: %@", n.ssid, error ?: @"collegamento non riuscito"] kind:3];
        }
    }];
    [self refreshWifiStatus];
}

- (void)togglePwVisible:(UIButton *)eye {
    UITextField *tf = (UITextField *)eye.superview;
    while (tf && ![tf isKindOfClass:[UITextField class]]) tf = (UITextField *)tf.superview;
    if (!tf) return;
    tf.secureTextEntry = !tf.secureTextEntry;
    [eye setTitle:tf.secureTextEntry ? @"mostra" : @"nascondi" forState:UIControlStateNormal];
}

- (void)askPassword:(SFWifiNetwork *)n {
    UIViewController *root = self.window.rootViewController;
    if (!root) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:n.ssid message:@"Password della rete Wi-Fi" preferredStyle:UIAlertControllerStyleAlert];
    __weak SFConnectPanel *me = self;
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.secureTextEntry = YES; tf.placeholder = @"password";
        tf.autocorrectionType = UITextAutocorrectionTypeNo; tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
        eye.frame = CGRectMake(0, 0, 72, 24); eye.titleLabel.font = [UIFont systemFontOfSize:13];
        [eye setTitle:@"mostra" forState:UIControlStateNormal];
        [eye addTarget:me action:@selector(togglePwVisible:) forControlEvents:UIControlEventTouchUpInside];
        tf.rightView = eye; tf.rightViewMode = UITextFieldViewModeAlways;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Collega" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *pw = wa.textFields.firstObject.text;
        if (pw.length) [me join:n password:pw]; else [me setStatus:@"Password non inserita." kind:3];
    }]];
    [root presentViewController:a animated:YES completion:nil];
}

- (void)debugJoin:(NSString *)ssid password:(NSString *)pw {
    for (SFWifiNetwork *n in [SFWifi shared].networks) if ([n.ssid isEqualToString:ssid]) {
        if (pw.length || n.known || !n.secured) [self join:n password:pw]; else [self askPassword:n];
        return;
    }
    [self setStatus:[NSString stringWithFormat:@"«%@» non è nell'elenco.", ssid] kind:3];
}

// Impostazioni > Wi-Fi dell'iPad (riserva). Va chiamata in differita: aprirla mentre l'app sta gestendo
// un openURL blocca SpringBoard (visto sull'app CTG).
- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *u = [NSURL URLWithString:@"prefs:root=WIFI"];
        BOOL ok = NO;
        Class wsc = NSClassFromString(@"LSApplicationWorkspace");
        SEL dw = NSSelectorFromString(@"defaultWorkspace"), op = NSSelectorFromString(@"openSensitiveURL:withOptions:");
        if (wsc && [wsc respondsToSelector:dw]) {
            id ws = ((id (*)(id, SEL))objc_msgSend)(wsc, dw);
            if ([ws respondsToSelector:op]) ok = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(ws, op, u, nil);
        }
        if (!ok) ok = [[UIApplication sharedApplication] openURL:u];
        SFLog(@"impostazioni Wi-Fi: %@", ok ? @"aperte" : @"NON aperte");
    });
}

@end
