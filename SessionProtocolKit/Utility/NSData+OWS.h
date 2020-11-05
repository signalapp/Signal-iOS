//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (OWS)

+ (NSData *)join:(NSArray<NSData *> *)datas;

- (NSData *)dataByAppendingData:(NSData *)data;

#pragma mark - Hex

- (NSString *)hexadecimalString;

+ (nullable NSData *)dataFromHexString:(NSString *)hexString;

#pragma mark - Base64

+ (nullable NSData *)dataFromBase64StringNoPadding:(NSString *)aString;
+ (nullable NSData *)dataFromBase64String:(NSString *)aString;

- (NSString *)base64EncodedString;

#pragma mark - 

/**
 * Compares data in constant time so as to help avoid potential timing attacks.
 */
- (BOOL)ows_constantTimeIsEqualToData:(NSData *)other;

@end

NS_ASSUME_NONNULL_END
