#import <WatchCommonWatch/TGBridgeMediaAttachment.h>

@interface TGBridgeContactMediaAttachment : TGBridgeMediaAttachment

@property (nonatomic, assign) int64_t uid;
@property (nonatomic, strong) NSString *firstName;
@property (nonatomic, strong) NSString *lastName;
@property (nonatomic, strong) NSString *phoneNumber;
@property (nonatomic, strong) NSString *prettyPhoneNumber;

- (NSString *)displayName;

@end
