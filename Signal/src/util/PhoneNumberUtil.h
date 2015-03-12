#import <Foundation/Foundation.h>
#import "PhoneNumber.h"
#import "NBPhoneNumberUtil.h"

@interface PhoneNumberUtil : NSObject

MacrosSingletonInterface

@property (nonatomic, retain) NBPhoneNumberUtil *nbPhoneNumberUtil;

+ (NSString *)callingCodeFromCountryCode:(NSString *)code;
+ (NSString *)countryNameFromCountryCode:(NSString *)code;
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;
+ (NSString*) normalizePhoneNumber:(NSString *) number;
+(NSArray *)validCountryCallingPrefixes:(NSString *)string;

+(NSUInteger) translateCursorPosition:(NSUInteger)offset
                                 from:(NSString*)source
                                   to:(NSString*)target
                    stickingRightward:(bool)preferHigh;

@end
