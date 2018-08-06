//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#define COUNTRY_CODE_PREFIX @"+"

/**
 *
 * PhoneNumber is used to deal with the nitty details of parsing/canonicalizing phone numbers.
 * Everything that expects a valid phone number should take a PhoneNumber, not a string, to avoid stringly typing.
 *
 */
@interface PhoneNumber : NSObject

+ (PhoneNumber *)phoneNumberFromE164:(NSString *)text;

+ (PhoneNumber *)tryParsePhoneNumberFromUserSpecifiedText:(NSString *)text;
+ (PhoneNumber *)tryParsePhoneNumberFromE164:(NSString *)text;

// This will try to parse the input text as a phone number using
// the default region and the country code for this client's phone
// number.
//
// Order matters; better results will appear first.
+ (NSArray<PhoneNumber *> *)tryParsePhoneNumbersFromsUserSpecifiedText:(NSString *)text
                                                     clientPhoneNumber:(NSString *)clientPhoneNumber;

+ (NSString *)removeFormattingCharacters:(NSString *)inputString;
+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input;
+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input
                                              withSpecifiedCountryCodeString:(NSString *)countryCodeString;
+ (NSString *)bestEffortLocalizedPhoneNumberWithE164:(NSString *)phoneNumber;

+ (NSString *)regionCodeFromCountryCodeString:(NSString *)countryCodeString;

- (NSURL *)toSystemDialerURL;
- (NSString *)toE164;
- (NSNumber *)getCountryCode;
@property (nonatomic, readonly, nullable) NSString *nationalNumber;
- (BOOL)isValid;

- (NSComparisonResult)compare:(PhoneNumber *)other;

+ (NSString *)defaultCountryCode;

@end
