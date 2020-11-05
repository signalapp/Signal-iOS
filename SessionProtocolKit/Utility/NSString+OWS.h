//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OWS)

- (NSString *)ows_stripped;

- (NSString *)digitsOnly;

@property (nonatomic, readonly) BOOL hasAnyASCII;
@property (nonatomic, readonly) BOOL isOnlyASCII;

- (NSString *)filterStringForDisplay;

- (NSString *)filterFilename;

- (BOOL)isValidE164;

+ (NSString *)formatDurationSeconds:(uint32_t)durationSeconds useShortFormat:(BOOL)useShortFormat;

@end

NS_ASSUME_NONNULL_END
