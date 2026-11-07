#import <Foundation/Foundation.h>

@class MTSignal;

@interface TGItemProviderSignals : NSObject

+ (NSArray<MTSignal *> *)itemSignalsForInputItems:(NSArray *)inputItems;
+ (NSArray<MTSignal *> *)sgItemSignalsForInputItems:(NSArray *)inputItems imageMaxDimension:(CGFloat)imageMaxDimension imageQuality:(CGFloat)imageQuality; // MARK: Swiftgram
+ (NSData *)audioWaveform:(NSURL *)url;

@end
