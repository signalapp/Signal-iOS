//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class PBCodedOutputStream;

@interface OWSChunkedOutputStream : NSObject

@property (nonatomic, readonly) PBCodedOutputStream *delegateStream;

+ (instancetype)streamWithOutputStream:(NSOutputStream *)output;
- (void)flush;

@end

NS_ASSUME_NONNULL_END
