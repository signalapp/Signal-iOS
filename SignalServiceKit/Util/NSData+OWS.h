//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface NSData (OWS)

+ (NSData *)join:(NSArray<NSData *> *)datas;

- (NSData *)dataByAppendingData:(NSData *)data;

#pragma mark - Hex

- (NSString *)hexadecimalString;

+ (nullable NSData *)dataFromHexString:(NSString *)hexString;

#pragma mark - Base64

- (NSString *)base64EncodedString;

#pragma mark -

/**
 * Compares data in constant time so as to help avoid potential timing attacks.
 */
- (BOOL)ows_constantTimeIsEqualToData:(NSData *)other;

@end

NS_ASSUME_NONNULL_END
