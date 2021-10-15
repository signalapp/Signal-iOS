//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSString (SSK)

@property (nonatomic, nullable, readonly) NSString *dominantLanguageWithLegacyLinguisticTagger;

- (NSString *)filterAsE164;

- (NSString *)substringBeforeRange:(NSRange)range;

- (NSString *)substringAfterRange:(NSRange)range;

@end

#pragma mark -

@interface NSMutableAttributedString (SSK)

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes forSubstring:(NSString *)substring;

@end

NS_ASSUME_NONNULL_END
