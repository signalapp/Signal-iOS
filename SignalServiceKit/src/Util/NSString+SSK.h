//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSString (SSK)

- (NSString *)ows_stripped;

- (NSString *)filterStringForDisplay;

- (NSString *)filterFilename;

- (BOOL)isValidE164;

+ (NSString *)formatDurationSeconds:(uint32_t)durationSeconds useShortFormat:(BOOL)useShortFormat;

@end

NS_ASSUME_NONNULL_END
