// similFranz Controller — schermata di avvio (stesso stile del Monitor): sfondo scuro con reticolo, tracce che scorrono (ECG, pletismografia, capnogramma), titolo,
// barra di caricamento che avanza con il caricamento VERO delle risorse (una fase per volta).
// La versione "statica" (senza traccia né barra) serve a generare l'immagine di avvio (LaunchImage):
// così il passaggio immagine di avvio -> animazione non si vede. Se cambia il disegno, rigenerarla:
//   uiopen 'simulafranz-controller://splash?static=1'  ->  shot?name=launch  ->  assets/LaunchImage-Landscape~ipad.png
#import <UIKit/UIKit.h>

@interface CtlSplashView : UIView
- (instancetype)initWithFrame:(CGRect)frame version:(NSString *)version;
- (void)makeStatic;
// stages: @[ @[etichetta, blocco di lavoro (void (^)(void)) oppure NSNull, (facoltativi) blocco BOOL "pronto?", attesa massima in s], ... ];
// ogni fase resta visibile almeno minStage secondi. Alla fine dissolve, si toglie da sola e chiama done.
- (void)runStages:(NSArray<NSArray *> *)stages minStage:(NSTimeInterval)minStage completion:(void (^)(void))done;
@end
