#import "PkPairingView.h"
#import "CtlModel.h"
#import "CtlUI.h"

@implementation PkPairingView {
    CtlModel *_m;
    UIView *_card, *_body; UILabel *_title, *_sub;
    NSString *_sig; NSMutableString *_digits; UILabel *_dots, *_err;
}

- (instancetype)initWithFrame:(CGRect)f model:(CtlModel *)model {
    if ((self = [super initWithFrame:f])) {
        _m = model; _digits = [NSMutableString string];
        self.backgroundColor = CTL_BG;
        UILabel *brand = CtlLabel(CGRectMake(0, 26, f.size.width, 40), @"", 26, YES, CTL_INK); brand.textAlignment = NSTextAlignmentCenter;
        NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:@"similFranz" attributes:@{NSFontAttributeName: [UIFont fontWithName:@"AvenirNext-DemiBold" size:28] ?: [UIFont boldSystemFontOfSize:28], NSForegroundColorAttributeName: CTL_INK}];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:@" Pocket" attributes:@{NSFontAttributeName: [UIFont fontWithName:@"AvenirNext-UltraLight" size:28] ?: [UIFont systemFontOfSize:28], NSForegroundColorAttributeName: CTL_TINT}]];
        brand.attributedText = t; brand.tag = 4242; [self addSubview:brand];
        _card = CtlCard(CGRectMake(8, 78, f.size.width - 16, f.size.height - 112)); [self addSubview:_card];
        _title = CtlLabel(CGRectMake(16, 14, f.size.width - 48, 26), @"", 19, YES, CTL_INK); _title.adjustsFontSizeToFitWidth = YES; _title.minimumScaleFactor = 0.7; [_card addSubview:_title];
        _sub = CtlLabel(CGRectMake(16, 42, f.size.width - 48, 48), @"", 12, NO, CTL_INK2); _sub.numberOfLines = 3; [_card addSubview:_sub];
        _body = [[UIView alloc] initWithFrame:CGRectMake(16, 96, f.size.width - 48, f.size.height - 112 - 108)]; [_card addSubview:_body];
        UILabel *foot = CtlLabel(CGRectMake(0, f.size.height - 26, f.size.width, 16), @"SIMULAZIONE SANITARIA  ·  NON PER USO CLINICO", 10, NO, CTL_INK3);
        foot.textAlignment = NSTextAlignmentCenter; [self addSubview:foot];
    }
    return self;
}

- (void)clear { for (UIView *v in [_body.subviews copy]) [v removeFromSuperview]; _dots = nil; _err = nil; }

- (void)refresh {
    CtlStage st = _m.stage;
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%ld|%@|", (long)st, _m.monitorName];
    for (SFLinkMonitor *m in _m.link.monitors) [sig appendFormat:@"%@,", m.name];
    if (st == CtlStageNeedPin) { [self renderPin]; }
    if ([sig isEqualToString:_sig]) return;
    _sig = sig;
    [self clear];
    CGFloat BW = _body.bounds.size.width;
    PkPairingView *me = self;      // vista permanente: nessun problema di ciclo
    if (st == CtlStageSearching) {
        NSArray<SFLinkMonitor *> *mons = _m.link.monitors;
        _title.text = mons.count ? @"Scegli il monitor" : @"Cerco i monitor vicini…";
        _sub.text = @"Collegamento diretto, anche senza rete: basta che Wi-Fi e Bluetooth siano accesi su iPod e monitor.";
        CGFloat y = 0;
        for (SFLinkMonitor *mon in mons) {
            CtlButton *b = [CtlButton buttonWithTitle:@"" style:CtlButtonQuiet color:nil frame:CGRectMake(0, y, BW, 62) target:nil action:NULL];
            b.accessibilityIdentifier = [@"pair." stringByAppendingString:mon.name];
            UILabel *n = CtlLabel(CGRectMake(12, 9, BW - 24, 22), mon.name, 16, YES, CTL_INK); n.userInteractionEnabled = NO; [b addSubview:n];
            UILabel *d = CtlLabel(CGRectMake(12, 33, BW - 90, 18), [NSString stringWithFormat:@"%@ · v%@", mon.deviceId, mon.version], 11, NO, CTL_INK2); d.userInteractionEnabled = NO; [b addSubview:d];
            UILabel *go = CtlLabel(CGRectMake(BW - 86, 0, 76, 62), @"Collega ›", 14, YES, CTL_TINT); go.textAlignment = NSTextAlignmentRight; go.userInteractionEnabled = NO; [b addSubview:go];
            b.onTap = ^{ [me->_m connect:mon]; };
            [_body addSubview:b]; y += 70;
        }
        if (!mons.count) {
            UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            sp.center = CGPointMake(BW / 2, 40); [sp startAnimating]; [_body addSubview:sp];
            UILabel *h = CtlLabel(CGRectMake(4, 84, BW - 8, 180), @"1.  Sull'iPad monitor apri similFranz Monitor.\n\n2.  Tieni l'iPod vicino (stessa stanza).\n\n3.  Il monitor compare qui da solo in pochi secondi.", 14, NO, CTL_INK);
            h.numberOfLines = 0; [_body addSubview:h];
        }
        if (_m.link.lastError.length) { UILabel *e = CtlLabel(CGRectMake(0, _body.bounds.size.height - 40, BW, 40), _m.link.lastError, 12, NO, CTL_ORANGE); e.numberOfLines = 2; [_body addSubview:e]; }
    } else if (st == CtlStageConnecting) {
        _title.text = [NSString stringWithFormat:@"Collegamento a %@…", _m.monitorName ?: @"monitor"];
        _sub.text = @"Qualche secondo: iPod e monitor si stanno accordando.";
        UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        sp.center = CGPointMake(BW / 2, 80); [sp startAnimating]; [_body addSubview:sp];
        CtlButton *c = [CtlButton buttonWithTitle:@"Annulla" style:CtlButtonQuiet color:nil frame:CGRectMake((BW - 180) / 2, _body.bounds.size.height - 56, 180, 44) target:nil action:NULL];
        c.accessibilityIdentifier = @"pair.cancel"; c.onTap = ^{ [me->_m forgetMonitor]; };
        [_body addSubview:c];
    } else if (st == CtlStageNeedPin) {
        _title.text = [NSString stringWithFormat:@"PIN di %@", _m.monitorName ?: @"monitor"];
        _sub.text = @"Il PIN è sul monitor: tasto (i), pannello «Collegamento del controller».";
        [_digits setString:@""];
        _dots = CtlLabel(CGRectMake(0, 0, BW, 40), @"", 26, YES, CTL_INK); _dots.font = CtlDigits(24, YES); _dots.textAlignment = NSTextAlignmentCenter; [_body addSubview:_dots];
        _err = CtlLabel(CGRectMake(0, 40, BW, 18), @"", 12, YES, CTL_RED); _err.textAlignment = NSTextAlignmentCenter; [_body addSubview:_err];
        NSArray *keys = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"⌫", @"0", @"OK"];
        CGFloat kw = 76, kh = 50, x0 = (BW - 3 * kw - 2 * 10) / 2;
        for (NSUInteger i = 0; i < keys.count; i++) {
            NSString *k = keys[i]; BOOL ok = [k isEqualToString:@"OK"];
            CtlButton *b = [CtlButton buttonWithTitle:k style:ok ? CtlButtonFilled : CtlButtonQuiet color:CTL_TINT frame:CGRectMake(x0 + (i % 3) * (kw + 10), 64 + (i / 3) * (kh + 8), kw, kh) target:nil action:NULL];
            b.titleLabel.font = ok ? [UIFont boldSystemFontOfSize:17] : CtlDigits(22, NO);
            b.accessibilityIdentifier = [@"key." stringByAppendingString:ok ? @"ok" : ([k isEqualToString:@"⌫"] ? @"del" : k)];
            b.onTap = ^{ [me key:k]; };
            [_body addSubview:b];
        }
        CtlButton *other = [CtlButton buttonWithTitle:@"Scegli un altro monitor" style:CtlButtonTinted color:CTL_TINT frame:CGRectMake((BW - 220) / 2, 64 + 4 * 58 + 8, 220, 38) target:nil action:NULL];
        other.titleLabel.font = [UIFont systemFontOfSize:13]; other.accessibilityIdentifier = @"pair.other"; other.onTap = ^{ [me->_m forgetMonitor]; };
        [_body addSubview:other];
        [self renderPin];
    }
}

- (void)renderPin {
    if (!_dots) return;
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < MAX((NSUInteger)6, _digits.length); i++) [s appendString:i < _digits.length ? @"●  " : @"○  "];
    _dots.text = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _err.text = _digits.length ? @"" : (_m.pinError ?: @"");
}

- (void)key:(NSString *)k {
    if ([k isEqualToString:@"⌫"]) { if (_digits.length) [_digits deleteCharactersInRange:NSMakeRange(_digits.length - 1, 1)]; }
    else if ([k isEqualToString:@"OK"]) { if (_digits.length >= 4) { NSString *p = [_digits copy]; [_digits setString:@""]; [_m submitPin:p]; return; } }
    else if (_digits.length < 12) [_digits appendString:k];
    [self renderPin];
    if (_digits.length == 6) {      // i PIN generati dal monitor hanno 6 cifre: parte da solo
        NSString *p = [_digits copy]; [_digits setString:@""];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_m submitPin:p]; });
    }
}
@end
