// similFranz — aggiornamento delle app senza computer (stesso file in Monitor, Controller e Pocket).
// Un pacchetto .deb arriva all'app (dal computer via regia web, oppure dal monitor via collegamento diretto),
// viene CONTROLLATO (archivio .deb valido, nome del pacchetto atteso, architettura iphoneos-arm) e consegnato
// all'aiutante di installazione dell'app (setuid root, installato dal pacchetto stesso), che lo installa con dpkg
// e riapre l'app. Foundation + zlib: testabile su macOS.
#import <Foundation/Foundation.h>

@interface SFUpdate : NSObject
// Campi del file "control" (Package, Version, Architecture, …) se il pacchetto è uno di `packages`; altrimenti nil + errore leggibile.
+ (NSDictionary<NSString *, NSString *> *)inspectDeb:(NSData *)deb allowed:(NSArray<NSString *> *)packages error:(NSString **)error;
// L'aiutante esiste ed è setuid root
+ (BOOL)installerAvailable:(NSString *)helperPath;
// Salva il pacchetto in debPath (percorso fisso letto dall'aiutante) e avvia l'aiutante. Ritorna la versione o nil + errore.
+ (NSString *)installDeb:(NSData *)deb package:(NSString *)package debPath:(NSString *)debPath helper:(NSString *)helperPath error:(NSString **)error;
// "0.3.10" > "0.3.9": confronto numerico per componenti
+ (NSComparisonResult)compareVersion:(NSString *)a to:(NSString *)b;
@end
