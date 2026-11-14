static UIView *FindId(UIView *root, NSString *ident) {
    if ([root.accessibilityIdentifier isEqualToString:ident] && !root.hidden) return root;
    for (UIView *v in root.subviews) { if (v.hidden) continue; UIView *f = FindId(v, ident); if (f) return f; }
    return nil;
}
static void ListIds(UIView *root, NSMutableArray *out) {
    if (root.hidden) return;
    if (root.accessibilityIdentifier.length) [out addObject:root.accessibilityIdentifier];
    for (UIView *v in root.subviews) ListIds(v, out);
}

// Controllo dei testi a schermo: troncati (puntini), parole spezzate a metà, righe con una o due lettere sole.
static void AuditText(UIView *root, NSString *owner, NSMutableArray<NSString *> *out, NSInteger *count) {
    if (root.hidden || root.alpha < 0.05) return;
    if (root.accessibilityIdentifier.length) owner = root.accessibilityIdentifier;
    if ([root isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)root; NSString *t = l.text;
        if (t.length && l.bounds.size.width > 1 && l.tag != 4242) {      // 4242 = testo con più caratteri diversi (marchio): verificato a vista
            (*count)++;
            UIFont *f = l.font;
            if (l.adjustsFontSizeToFitWidth) f = [f fontWithSize:f.pointSize * (l.minimumScaleFactor > 0 ? l.minimumScaleFactor : 0.5)];   // può rimpicciolirsi fin qui
            NSTextStorage *ts = [[NSTextStorage alloc] initWithString:t attributes:@{NSFontAttributeName: f}];
            NSLayoutManager *lm = [NSLayoutManager new]; [ts addLayoutManager:lm];
            NSTextContainer *tc = [[NSTextContainer alloc] initWithSize:CGSizeMake(l.bounds.size.width + 0.5, CGFLOAT_MAX)]; tc.lineFragmentPadding = 0; [lm addTextContainer:tc];
            NSMutableArray<NSValue *> *lines = [NSMutableArray array];
            [lm enumerateLineFragmentsForGlyphRange:NSMakeRange(0, lm.numberOfGlyphs) usingBlock:^(CGRect r, CGRect used, NSTextContainer *c, NSRange gr, BOOL *stop) {
                [lines addObject:[NSValue valueWithRange:[lm characterRangeForGlyphRange:gr actualGlyphRange:NULL]]];
            }];
            CGFloat height = [lm usedRectForTextContainer:tc].size.height;
            NSString *problem = nil;
            NSInteger allowed = l.numberOfLines;
            if ((allowed > 0 && (NSInteger)lines.count > allowed) || height > l.bounds.size.height + 3) problem = @"TRONCATO";
            NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
            for (NSUInteger i = 0; !problem && i < lines.count; i++) {
                NSRange r = lines[i].rangeValue;
                NSString *line = [[t substringWithRange:r] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (lines.count > 1 && line.length > 0 && line.length <= 2 && [letters characterIsMember:[line characterAtIndex:0]]) problem = @"RIGA DI UNA-DUE LETTERE";
                if (i + 1 < lines.count && r.length && NSMaxRange(r) < t.length) {
                    unichar a = [t characterAtIndex:NSMaxRange(r) - 1], b = [t characterAtIndex:NSMaxRange(r)];
                    if ([letters characterIsMember:a] && [letters characterIsMember:b]) problem = @"PAROLA SPEZZATA";
                }
            }
            if (problem) [out addObject:[NSString stringWithFormat:@"%@ [%@] «%@» (%.0fx%.0f, %.1f pt)", problem, owner ?: @"?", [t stringByReplacingOccurrencesOfString:@"\n" withString:@" / "], l.bounds.size.width, l.bounds.size.height, l.font.pointSize]];
        }
    }
    for (UIView *v in root.subviews) AuditText(v, owner, out, count);
}
