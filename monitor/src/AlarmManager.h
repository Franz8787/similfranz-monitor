// SimulaFranz_Monitor — valutazione allarmi (Foundation pura, testabile su macOS).
// Usa i limiti configurabili (SLSnapshot.alarmLimits) e lo stato dei sensori.
#import <Foundation/Foundation.h>
@class SLSnapshot;

typedef NS_ENUM(NSInteger, SLAlarmLevel) {
    SLAlarmNone = 0,
    SLAlarmTechnical,   // sensore scollegato / segnale scarso (ciano, priorità bassa)
    SLAlarmMedium,      // giallo
    SLAlarmHigh         // rosso
};

@interface SLAlarmResult : NSObject
@property (nonatomic, readonly) SLAlarmLevel level;
@property (nonatomic, readonly, copy) NSArray<NSString *> *messages;   // ordinati per priorità
@property (nonatomic, readonly, copy) NSSet<NSString *> *violated;     // parametri in allarme: hr, spo2, rr, etco2, nibp, art
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *severity;  // parametro -> SLAlarmLevel (medio/alto)
@end

@interface AlarmManager : NSObject
+ (SLAlarmResult *)evaluate:(SLSnapshot *)snapshot;
@end
