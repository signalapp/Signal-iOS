#import <Foundation/Foundation.h>
#import "NBPhoneNumberUtil.h"
#import "PhoneNumber.h"

@interface PhoneNumberUtil : NSObject

@property (nonatomic, retain) NBPhoneNumberUtil *nbPhoneNumberUtil;

+ (NSString *)callingCodeFromCountryCode:(NSString *)code;
+ (NSString *)countryNameFromCountryCode:(NSString *)code;
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;
+ (NSString *)normalizePhoneNumber:(NSString *)number;
+ (NSArray *)validCountryCallingPrefixes:(NSString *)string;

+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh;

+ (instancetype)sharedUtil;

@end
