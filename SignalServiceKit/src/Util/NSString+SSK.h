//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface NSString (SSK)

- (NSString *)filterAsE164;

- (NSString *)substringBeforeRange:(NSRange)range;

- (NSString *)substringAfterRange:(NSRange)range;

@end

#pragma mark -

@interface NSMutableAttributedString (SSK)

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attributes forSubstring:(NSString *)substring;

@end

NS_ASSUME_NONNULL_END
