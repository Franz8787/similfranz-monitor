// similFranz Pocket — abbinamento al monitor: elenco dei monitor vicini -> tocco -> PIN sul tastierino.
// Il monitor e il PIN restano memorizzati: alle accensioni successive il collegamento riparte da solo.
#import <UIKit/UIKit.h>
@class CtlModel;

@interface PkPairingView : UIView
- (instancetype)initWithFrame:(CGRect)frame model:(CtlModel *)model;
- (void)refresh;
@end
