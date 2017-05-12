//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NBPhoneNumberUtil.h"
#import "PhoneNumber.h"

@interface PhoneNumberUtil : NSObject

@property (nonatomic, retain) NBPhoneNumberUtil *nbPhoneNumberUtil;

+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString;

+ (NSString *)callingCodeFromCountryCode:(NSString *)countryCode;
+ (NSString *)countryNameFromCountryCode:(NSString *)countryCode;
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;
- (NSArray *)countryCodesFromCallingCode:(NSString *)callingCode;

+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh;

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode;

+ (instancetype)sharedUtil;

- (NBPhoneNumber *)parse:(NSString *)numberToParse defaultRegion:(NSString *)defaultRegion error:(NSError **)error;
- (NSString *)format:(NBPhoneNumber *)phoneNumber
        numberFormat:(NBEPhoneNumberFormat)numberFormat
               error:(NSError **)error;

@end
