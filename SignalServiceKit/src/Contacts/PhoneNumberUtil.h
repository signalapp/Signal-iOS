//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/PhoneNumber.h>
#import <libPhoneNumber_iOS/NBPhoneNumberUtil.h>

NS_ASSUME_NONNULL_BEGIN

@class PhoneNumberUtilWrapper;
@class UnfairLock;

@interface PhoneNumberUtil : NSObject

// These properties should only be accessed by Swift.
@property (nonatomic, readonly) UnfairLock *unfairLock;
@property (nonatomic, readonly) PhoneNumberUtilWrapper *phoneNumberUtilWrapper;

+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString;

+ (nullable NSString *)countryNameFromCountryCode:(NSString *)countryCode;
+ (NSArray *)countryCodesForSearchTerm:(nullable NSString *)searchTerm;

// Returns the most likely country code for a calling code based on population.
- (NSString *)probableCountryCodeForCallingCode:(NSString *)callingCode;

+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh;

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode;

- (nullable NBPhoneNumber *)parse:(NSString *)numberToParse defaultRegion:(NSString *)defaultRegion error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
