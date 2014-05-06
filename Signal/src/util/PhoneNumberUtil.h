#import <Foundation/Foundation.h>
#import "PhoneNumber.h"

@interface PhoneNumberUtil : NSObject
+ (NSString *)callingCodeFromCountryCode:(NSString *)code;
+ (NSString *)countryNameFromCountryCode:(NSString *)code;
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;
+ (NSString*) normalizePhoneNumber:(NSString *) number;
@end
