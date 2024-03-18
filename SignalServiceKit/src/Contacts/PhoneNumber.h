//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define COUNTRY_CODE_PREFIX @"+"

@class NBPhoneNumber;

/**
 * PhoneNumber is used to deal with the nitty details of parsing/canonicalizing phone numbers.
 */
@interface PhoneNumber : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)decoder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNbPhoneNumber:(NBPhoneNumber *)nbPhoneNumber e164:(NSString *)e164 NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NBPhoneNumber *nbPhoneNumber;

+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input;
+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input
                                              withSpecifiedCountryCodeString:(NSString *)countryCodeString;
+ (NSString *)bestEffortLocalizedPhoneNumberWithE164:(NSString *)phoneNumber;

- (NSString *)toE164;
- (nullable NSNumber *)getCountryCode;
- (BOOL)isValid;

- (NSComparisonResult)compare:(PhoneNumber *)other;

@end

NS_ASSUME_NONNULL_END
