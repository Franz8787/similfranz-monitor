// similFranz Pocket — schermata di avvio verticale, stessa famiglia del Monitor e del Controller:
// sfondo scuro con reticolo, ECG che si disegna, titolo, barra che avanza con le fasi VERE di caricamento.
// makeStatic = primo fotogramma senza traccia né barra (serve a rigenerare assets/LaunchImage-568h@2x.png).
#import <UIKit/UIKit.h>

@interface PkSplashView : UIView
- (instancetype)initWithFrame:(CGRect)frame version:(NSString *)version;
- (void)makeStatic;
// stages: @[ @[etichetta, blocco (void (^)(void)) o NSNull, (facoltativo) blocco BOOL "pronto?", attesa massima in s], ... ]
- (void)runStages:(NSArray<NSArray *> *)stages minStage:(NSTimeInterval)minStage completion:(void (^)(void))done;
@end
