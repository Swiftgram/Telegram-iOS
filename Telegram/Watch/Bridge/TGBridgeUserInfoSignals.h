#import <SSignalKit/SSignalKit.h>

@interface TGBridgeUserInfoSignals : NSObject

+ (SSignal *)userInfoWithUserId:(int64_t)userId;
+ (SSignal *)usersInfoWithUserIds:(NSArray *)userIds;

@end
