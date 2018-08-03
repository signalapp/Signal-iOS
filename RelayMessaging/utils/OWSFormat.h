//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSFormat : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (NSString *)formatInt:(int)value;

+ (NSString *)formatFileSize:(unsigned long)fileSize;

+ (NSString *)formatDurationSeconds:(long)timeSeconds;

@end

NS_ASSUME_NONNULL_END
