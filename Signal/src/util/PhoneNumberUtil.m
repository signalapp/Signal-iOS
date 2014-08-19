#import "PhoneNumberUtil.h"
#import "ContactsManager.h"
#import "FunctionalUtil.h"
#import "NBPhoneNumberUtil.h"

@implementation PhoneNumberUtil


+ (NSString *)countryNameFromCountryCode:(NSString *)code {
    NSDictionary *countryCodeComponent = @{NSLocaleCountryCode: code};
    NSString *identifier = [NSLocale localeIdentifierFromComponents:countryCodeComponent];
    NSString *country = [[NSLocale currentLocale] displayNameForKey:NSLocaleIdentifier
                                                              value:identifier];
    return country;
}

+ (NSString *)callingCodeFromCountryCode:(NSString *)code {
    NSNumber *callingCode = [NBPhoneNumberUtil.sharedInstance getCountryCodeForRegion:code];
    return [NSString stringWithFormat:@"%@%@", COUNTRY_CODE_PREFIX, callingCode];
}

+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm {
    
    NSArray *countryCodes = NSLocale.ISOCountryCodes;
    
    if (searchTerm) {
        countryCodes = [countryCodes filter:^int(NSString *code) {
            NSString *countryName = [self countryNameFromCountryCode:code];
            return [ContactsManager name:countryName matchesQuery:searchTerm];
        }];
    }
    return countryCodes;
}

+ (NSString*) normalizePhoneNumber:(NSString *) number {
    return [NBPhoneNumberUtil.sharedInstance normalizePhoneNumber:number];
}

@end
