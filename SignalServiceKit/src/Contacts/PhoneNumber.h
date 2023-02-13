//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

#define COUNTRY_CODE_PREFIX @"+"

/**
 *
 * PhoneNumber is used to deal with the nitty details of parsing/canonicalizing phone numbers.
 * Everything that expects a valid phone number should take a PhoneNumber, not a string, to avoid stringly typing.
 *
 */
@interface PhoneNumber : NSObject

+ (nullable PhoneNumber *)phoneNumberFromE164:(NSString *)text;

+ (nullable PhoneNumber *)tryParsePhoneNumberFromUserSpecifiedText:(NSString *)text;

/// `text` may omit the calling code or duplicate the value in `callingCode`.
+ (nullable PhoneNumber *)tryParsePhoneNumberFromUserSpecifiedText:(NSString *)text callingCode:(NSString *)callingCode;
+ (nullable PhoneNumber *)tryParsePhoneNumberFromE164:(NSString *)text;
+ (nullable PhoneNumber *)phoneNumberFromUserSpecifiedText:(NSString *)text;

// This will try to parse the input text as a phone number using
// the default region and the country code for this client's phone
// number.
//
// Order matters; better results will appear first.
+ (NSArray<PhoneNumber *> *)tryParsePhoneNumbersFromUserSpecifiedText:(NSString *)text
                                                     clientPhoneNumber:(NSString *)clientPhoneNumber;

+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input;
+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input
                                              withSpecifiedCountryCodeString:(NSString *)countryCodeString;
+ (NSString *)bestEffortLocalizedPhoneNumberWithE164:(NSString *)phoneNumber;

- (NSURL *)toSystemDialerURL;
- (NSString *)toE164;
- (nullable NSNumber *)getCountryCode;
@property (nonatomic, readonly, nullable) NSString *nationalNumber;
- (BOOL)isValid;

- (NSComparisonResult)compare:(PhoneNumber *)other;

+ (NSString *)defaultCountryCode;

@end

NS_ASSUME_NONNULL_END
