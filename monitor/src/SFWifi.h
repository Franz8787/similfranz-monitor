// similFranz Monitor — Wi-Fi gestito dall'app (elenco reti, collegamento, password) senza passare da Impostazioni.
// Usa le funzioni di sistema di MobileWiFi.framework (caricate a runtime): servono l'iPad jailbroken, l'app in
// /Applications e l'entitlement com.apple.wifi.manager-access. Se qualcosa manca, available = NO e resta il
// tasto che apre Impostazioni > Wi-Fi.
// (Stesso modulo dell'app similFranz_CTG, dove è stato verificato su iOS 9.3.5.)
#import <Foundation/Foundation.h>

@interface SFWifiNetwork : NSObject
@property (nonatomic, copy) NSString *ssid;
@property (nonatomic) NSInteger rssi, channel;        // dBm, canale (>14 = 5 GHz)
@property (nonatomic) BOOL secured, known, current;   // con password / già salvata sull'iPad / collegata ora
@property (nonatomic, readonly) NSInteger bars;               // 1..3
@end

@interface SFWifi : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL scanning, joining;
@property (nonatomic, readonly, copy) NSString *joiningSSID, *lastError;
@property (nonatomic, readonly, copy) NSArray<SFWifiNetwork *> *networks;    // ultimo elenco (la più forte per ogni nome)
@property (nonatomic, copy) void (^onChange)(void);                            // elenco o stato cambiati (main thread)
- (NSString *)currentSSID;
- (BOOL)powerOn;                                                               // Wi-Fi dell'iPad acceso?
- (void)setPower:(BOOL)on;
- (void)scan;
- (void)join:(SFWifiNetwork *)net password:(NSString *)password completion:(void (^)(BOOL ok, NSString *error))done;
@end
