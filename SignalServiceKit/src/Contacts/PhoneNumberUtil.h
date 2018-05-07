//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "PhoneNumber.h"
#import <libPhoneNumber_iOS/NBPhoneNumberUtil.h>

@interface PhoneNumberUtil : NSObject

@property (nonatomic, retain) NBPhoneNumberUtil *nbPhoneNumberUtil;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedThreadLocal;

+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString;

+ (NSString *)callingCodeFromCountryCode:(NSString *)countryCode;
+ (NSString *)countryNameFromCountryCode:(NSString *)countryCode;
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;

// Returns a list of country codes for a calling code in descending
// order of population.
- (NSArray *)countryCodesFromCallingCode:(NSString *)callingCode;
// Returns the most likely country code for a calling code based on population.
- (NSString *)probableCountryCodeForCallingCode:(NSString *)callingCode;

+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh;

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode;

- (NBPhoneNumber *)parse:(NSString *)numberToParse defaultRegion:(NSString *)defaultRegion error:(NSError **)error;
- (NSString *)format:(NBPhoneNumber *)phoneNumber
        numberFormat:(NBEPhoneNumberFormat)numberFormat
               error:(NSError **)error;

@end
