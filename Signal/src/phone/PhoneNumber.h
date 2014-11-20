#import <Foundation/Foundation.h>
#import "NBPhoneNumberUtil.h"

#define COUNTRY_CODE_PREFIX @"+"

/**
 *
 * PhoneNumber is used to deal with the nitty details of parsing/canonicalizing phone numbers.
 * Everything that expects a valid phone number should take a PhoneNumber, not a string, to avoid stringly typing.
 *
 */
@interface PhoneNumber : NSObject

- (instancetype)initFromE164:(NSString*)text;

+ (instancetype)tryParsePhoneNumberFromText:(NSString*)text fromRegion:(NSString*)regionCode;
+ (instancetype)tryParsePhoneNumberFromUserSpecifiedText:(NSString*)text;
+ (instancetype)tryParsePhoneNumberFromE164:(NSString*)text;


+ (NSString*)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input;
+ (NSString*)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input
                                             withSpecifiedCountryCodeString:(NSString*)countryCodeString;

+ (NSString*)regionCodeFromCountryCodeString:(NSString*)countryCodeString;

- (NSURL*)toSystemDialerURL;
- (NSString*)toE164;
- (NSString*)localizedDescriptionForUser;
- (NSNumber*)getCountryCode;
- (BOOL)isValid;
- (BOOL)resolvesInternationallyTo:(PhoneNumber*)otherPhoneNumber;

@end
