//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NSString * (^OWSLogBlock)(void);

/**
 * A minimal DDLog wrapper for swift.
 */
@interface OWSLogger : NSObject

+ (void)verbose:(OWSLogBlock)logBlock;
+ (void)debug:(OWSLogBlock)logBlock;
+ (void)info:(OWSLogBlock)logBlock;
+ (void)warn:(OWSLogBlock)logBlock;
+ (void)error:(OWSLogBlock)logBlock;
+ (void)flush;

@end

NS_ASSUME_NONNULL_END
