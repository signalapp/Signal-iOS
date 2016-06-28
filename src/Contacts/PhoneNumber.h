#import <Foundation/Foundation.h>
#import <libPhoneNumber-iOS/NBPhoneNumberUtil.h>

#define COUNTRY_CODE_PREFIX @"+"

/**
 *
 * PhoneNumber is used to deal with the nitty details of parsing/canonicalizing phone numbers.
 * Everything that expects a valid phone number should take a PhoneNumber, not a string, to avoid stringly typing.
 *
 */
@interface PhoneNumber : NSObject {
   @private
    NBPhoneNumber *phoneNumber;
   @private
    NSString *e164;
}

+ (PhoneNumber *)phoneNumberFromText:(NSString *)text andRegion:(NSString *)regionCode;
+ (PhoneNumber *)phoneNumberFromUserSpecifiedText:(NSString *)text;
+ (PhoneNumber *)phoneNumberFromE164:(NSString *)text;

+ (PhoneNumber *)tryParsePhoneNumberFromText:(NSString *)text fromRegion:(NSString *)regionCode;
+ (PhoneNumber *)tryParsePhoneNumberFromUserSpecifiedText:(NSString *)text;
+ (PhoneNumber *)tryParsePhoneNumberFromE164:(NSString *)text;

+ (NSString *)removeFormattingCharacters:(NSString *)inputString;
+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input;
+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input
                                              withSpecifiedCountryCodeString:(NSString *)countryCodeString;

+ (NSString *)regionCodeFromCountryCodeString:(NSString *)countryCodeString;

- (NSURL *)toSystemDialerURL;
- (NSString *)toE164;
- (NSString *)localizedDescriptionForUser;
- (NSNumber *)getCountryCode;
- (BOOL)isValid;
- (BOOL)resolvesInternationallyTo:(PhoneNumber *)otherPhoneNumber;

@end
