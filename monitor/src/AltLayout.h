// similFranz Monitor — interfaccia comune dei layout dei dispositivi (alternativi al layout ICU).
#import <UIKit/UIKit.h>
@class SimulationState, SLSnapshot, WaveformEngine, SoundEngine;

@protocol SFAltLayout <NSObject>
- (instancetype)initWithFrame:(CGRect)frame state:(SimulationState *)state engine:(WaveformEngine *)engine sound:(SoundEngine *)sound;
@property (nonatomic, copy) void (^onLayoutMenu)(void);
@property (nonatomic, copy) void (^onInfo)(void);
@property (nonatomic, copy) void (^onVolumes)(void);      // menu › Volumi (pannello comune)
- (void)updateWithSnapshot:(SLSnapshot *)s;
- (void)tick:(NSTimeInterval)now snapshot:(SLSnapshot *)s;
- (void)resetTracesAt:(NSTimeInterval)t;
- (void)setAlarmText:(NSString *)text level:(NSInteger)level severity:(NSDictionary *)severity muted:(BOOL)muted remaining:(NSInteger)rem;
- (BOOL)poweredOff;          // dispositivo spento: niente allarmi, bip o spie
- (void)setDevicePowered:(BOOL)on;   // allinea il layout allo stato di accensione condiviso (idempotente)
- (void)runSelfTestWithShot:(void (^)(NSString *name))shot done:(void (^)(NSInteger fails))done;
@end

// Targhetta "SimulaFranz_Monitor" comune ai layout dei dispositivi: nome in evidenza + versione + "Layout",
// un tocco apre il menu dei layout (funziona anche a dispositivo spento).
static inline UIButton *SFLayoutButton(CGRect f, id target, SEL sel) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.94];
    b.layer.cornerRadius = 8; b.layer.borderWidth = 1; b.layer.borderColor = [UIColor colorWithWhite:0.48 alpha:1].CGColor;
    b.contentEdgeInsets = UIEdgeInsetsMake(2, 3, 2, 3);
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init]; ps.alignment = NSTextAlignmentCenter;
    CGFloat fs = 12;                                  // il nome deve stare su una riga sola
    while (fs > 8 && [@"similFranz Monitor" sizeWithAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:fs]}].width > f.size.width - 10) fs -= 0.5;
    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:@"similFranz Monitor\n"
        attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:fs], NSForegroundColorAttributeName: [UIColor colorWithWhite:0.95 alpha:1], NSParagraphStyleAttributeName: ps}];
    [t appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"v%@  \u00B7  Layout \u25BE\uFE0E", ver]
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:10], NSForegroundColorAttributeName: [UIColor colorWithRed:0.55 green:0.80 blue:1.0 alpha:1], NSParagraphStyleAttributeName: ps}]];
    b.titleLabel.numberOfLines = 2; b.titleLabel.textAlignment = NSTextAlignmentCenter;
    [b setAttributedTitle:t forState:UIControlStateNormal];
    b.accessibilityIdentifier = @"LAYOUT";
    [b addTarget:target action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Versione pubblica: solo i layout originali di similFranz, che usano i testi generici del modello così come sono.
static inline NSInteger SFLayoutIndex(NSString *layout) { return -1; }
static inline NSString *SFAedScreenText(NSString *layout, NSString *msg) { return msg; }
static inline NSString *SFAlarmText(NSString *layout, NSString *msg) { return msg; }
static inline NSString *SFAedVoiceText(NSString *layout, NSString *v) { return v; }
