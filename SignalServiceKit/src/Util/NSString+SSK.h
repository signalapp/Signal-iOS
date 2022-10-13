//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@protocol SSKMaybeString<NSObject>
@property (nonatomic, nullable, readonly) NSString *stringOrNil;
@end

@interface NSString (SSK)<SSKMaybeString>

@property (nonatomic, nullable, readonly) NSString *dominantLanguageWithLegacyLinguisticTagger;

- (NSString *)filterAsE164;

- (NSString *)substringBeforeRange:(NSRange)range;

- (NSString *)substringAfterRange:(NSRange)range;

@end

#pragma mark -

@interface NSMutableAttributedString (SSK)

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes forSubstring:(NSString *)substring;

@end

@interface NSNull(NSStringSSK)<SSKMaybeString>
@end

NS_ASSUME_NONNULL_END
