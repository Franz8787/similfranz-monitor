// SimulaFranz_Monitor — prestazioni dei layout dei dispositivi sull'iPad mini (A5).
// A ogni fotogramma delle onde il sistema ricompone TUTTI gli strati visibili: decine di pannelli, scritte fisse,
// sfumature e ombre del frontale costano molto (backboardd fino al 60%). La decorazione che non cambia mai viene
// "fotografata" una volta sola in un'unica immagine; restano strati separati solo tasti, schermo e parti animate.
#import <UIKit/UIKit.h>

static inline BOOL SFHasControl(UIView *v) {
    if ([v isKindOfClass:[UIControl class]]) return YES;
    for (UIView *s in v.subviews) if (SFHasControl(s)) return YES;
    return NO;
}

// keep: viste figlie dirette di root che cambiano aspetto (spie, lancette, finestre con etichette che cambiano)
static inline void SFFlattenStatic(UIView *root, NSArray<UIView *> *keep) {
    if (!root.window || root.bounds.size.width < 10) return;
    NSMutableArray<UIView *> *flat = [NSMutableArray array], *other = [NSMutableArray array];
    for (UIView *v in root.subviews) {
        BOOL dynamic = v.hidden || [keep containsObject:v] || SFHasControl(v) || ![NSStringFromClass([v class]) hasPrefix:@"UI"]
                       || [v isKindOfClass:[UIImageView class]] || v.subviews.count > 8;
        [(dynamic ? other : flat) addObject:v];
    }
    if (flat.count < 4) return;
    NSMutableArray *wasHidden = [NSMutableArray array];
    for (UIView *v in other) { [wasHidden addObject:@(v.hidden)]; v.hidden = YES; }
    UIGraphicsBeginImageContextWithOptions(root.bounds.size, YES, 0);
    [root drawViewHierarchyInRect:root.bounds afterScreenUpdates:YES];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    for (NSUInteger i = 0; i < other.count; i++) other[i].hidden = [wasHidden[i] boolValue];
    if (!img) return;
    for (UIView *v in flat) [v removeFromSuperview];
    for (CALayer *l in [root.layer.sublayers copy]) if (![l.delegate isKindOfClass:[UIView class]]) [l removeFromSuperlayer];   // sfumature della scocca
    UIImageView *iv = [[UIImageView alloc] initWithFrame:root.bounds];
    iv.image = img; iv.opaque = YES; iv.userInteractionEnabled = NO;
    [root insertSubview:iv atIndex:0];
}
