#import <Foundation/Foundation.h>
#import "PhoneNumber.h"

@interface PhoneNumberUtil : NSObject
+ (NSString *)callingCodeFromCountryCode:(NSString *)code;
+ (NSString *)countryNameFromCountryCode:(NSString *)code;
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;
+ (NSString*) normalizePhoneNumber:(NSString *) number;

+(NSUInteger) translateCursorPosition:(NSUInteger)offset
                                 from:(NSString*)source
                                   to:(NSString*)target
                    stickingRightward:(bool)preferHigh;

@end
