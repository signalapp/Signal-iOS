//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSFormat : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, class, readonly) NSNumberFormatter *defaultNumberFormatter;

+ (NSString *)formatFileSize:(unsigned long)fileSize;

+ (NSString *)formatDurationSeconds:(long)timeSeconds;

@end

NS_ASSUME_NONNULL_END
