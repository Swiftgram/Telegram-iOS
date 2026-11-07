#import <SSignalKit/SSignalKit.h>

@interface TGBridgeBotSignals : NSObject

+ (SSignal *)botInfoForUserId:(int64_t)userId;
+ (SSignal *)botReplyMarkupForPeerId:(int64_t)peerId;

@end
