//  Created by Michael Kirk on 10/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

/**
 * A minimal DDLog wrapper for swift.
 */
NS_SWIFT_NAME(Logger)
@interface OWSLogger : NSObject

+ (void)verbose:(NSString *)logString;
+ (void)debug:(NSString *)logString;
+ (void)info:(NSString *)logString;
+ (void)warn:(NSString *)logString;
+ (void)error:(NSString *)logString;

@end

NS_ASSUME_NONNULL_END
