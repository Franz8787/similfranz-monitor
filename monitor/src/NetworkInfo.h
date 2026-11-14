// SimulaFranz_Monitor — rilevamento dell'IP IPv4 Wi-Fi corrente (nessun valore fisso).
#import <Foundation/Foundation.h>

@interface NetworkInfo : NSObject
// IPv4 dell'interfaccia Wi-Fi (en0), nil se non connessa.
+ (NSString *)wifiIPv4Address;
@end
