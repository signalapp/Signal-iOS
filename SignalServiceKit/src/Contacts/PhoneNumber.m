//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "PhoneNumber.h"
#import "NSString+SSK.h"
#import "PhoneNumberUtil.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <libPhoneNumber_iOS/NBAsYouTypeFormatter.h>
#import <libPhoneNumber_iOS/NBMetadataHelper.h>
#import <libPhoneNumber_iOS/NBPhoneMetaData.h>
#import <libPhoneNumber_iOS/NBPhoneNumber.h>
#import <libPhoneNumber_iOS/NBPhoneNumberUtil.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const RPDefaultsKeyPhoneNumberString    = @"RPDefaultsKeyPhoneNumberString";
static NSString *const RPDefaultsKeyPhoneNumberCanonical = @"RPDefaultsKeyPhoneNumberCanonical";

@interface PhoneNumber ()
@property (nonatomic, readonly) NSString *e164;
@end

#pragma mark -

@implementation PhoneNumber

- (instancetype)initWithNbPhoneNumber:(NBPhoneNumber *)nbPhoneNumber e164:(NSString *)e164
{
    self = [super init];
    if (self) {
        OWSAssertDebug(nbPhoneNumber);
        OWSAssertDebug(e164.length > 0);

        _nbPhoneNumber = nbPhoneNumber;
        _e164 = e164;
    }
    return self;
}

+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input {
    return [PhoneNumber
        bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:input
                                               withSpecifiedRegionCode:[PhoneNumberUtil defaultCountryCode]];
}

+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input
                                              withSpecifiedCountryCodeString:(NSString *)countryCodeString {
    return [PhoneNumber
        bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:input
                                               withSpecifiedRegionCode:
                                                   [PhoneNumber regionCodeFromCountryCodeString:countryCodeString]];
}

+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input
                                                     withSpecifiedRegionCode:(NSString *)regionCode {

    static AnyLRUCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(
        &onceToken, ^{ cache = [[AnyLRUCache alloc] initWithMaxSize:256 nseMaxSize:0 shouldEvacuateInBackground:NO]; });

    @synchronized(cache) {
        NSString *cacheKey = [[input stringByAppendingString:@"@"] stringByAppendingString:regionCode];
        NSString *_Nullable cachedValue = (NSString *)[cache getWithKey:cacheKey];
        if (cachedValue != nil) {
            return cachedValue;
        }

        NBAsYouTypeFormatter *formatter = [[NBAsYouTypeFormatter alloc] initWithRegionCode:regionCode];
        NSString *result = input;
        for (NSUInteger i = 0; i < input.length; i++) {
            result = [formatter inputDigit:[input substringWithRange:NSMakeRange(i, 1)]];
        }
        [cache setObject:result forKey:cacheKey];
        return result;
    }
}

+ (NSString *)bestEffortLocalizedPhoneNumberWithE164:(NSString *)phoneNumber
{
    OWSAssertDebug(phoneNumber);

    if (![phoneNumber hasPrefix:COUNTRY_CODE_PREFIX]) {
        return phoneNumber;
    }

    PhoneNumber *_Nullable parsedPhoneNumber = [self.phoneNumberUtil parseE164:phoneNumber];
    if (!parsedPhoneNumber) {
        OWSLogWarn(@"could not parse phone number.");
        return phoneNumber;
    }
    NSNumber *_Nullable callingCode = [parsedPhoneNumber getCallingCode];
    if (!callingCode) {
        OWSLogWarn(@"parsed phone number has no calling code.");
        return phoneNumber;
    }
    NSString *callingCodeString = [NSString stringWithFormat:@"%d", callingCode.intValue];
    if (callingCodeString.length < 1) {
        OWSLogWarn(@"invalid country code.");
        return phoneNumber;
    }
    NSString *_Nullable formattedPhoneNumber =
        [self bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:phoneNumber
                                                     withSpecifiedRegionCode:callingCodeString];
    if (!callingCode) {
        OWSLogWarn(@"could not format phone number.");
        return phoneNumber;
    }
    return formattedPhoneNumber;
}

+ (nullable NSString *)regionCodeFromCountryCodeString:(NSString *)countryCodeString {
    NSNumber *countryCallingCode = @([[countryCodeString substringFromIndex:1] integerValue]);
    return [self.phoneNumberUtil getRegionCodeForCountryCode:countryCallingCode];
}

#pragma mark -

- (NSString *)toE164 {
    return self.e164;
}

- (nullable NSNumber *)getCallingCode
{
    return self.nbPhoneNumber.countryCode;
}

- (BOOL)isValid
{
    return [self.phoneNumberUtil isValidNumber:self.nbPhoneNumber];
}

- (NSString *)description {
    return self.e164;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:self.nbPhoneNumber forKey:RPDefaultsKeyPhoneNumberString];
    [encoder encodeObject:self.e164 forKey:RPDefaultsKeyPhoneNumberCanonical];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self) {
        _nbPhoneNumber = [decoder decodeObjectForKey:RPDefaultsKeyPhoneNumberString];
        _e164 = [decoder decodeObjectForKey:RPDefaultsKeyPhoneNumberCanonical];
    }
    return self;
}

- (NSComparisonResult)compare:(PhoneNumber *)other
{
    return [self.toE164 compare:other.toE164];
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:[self class]]) {
        return NO;
    }
    PhoneNumber *otherPhoneNumber = (PhoneNumber *)other;

    return [self.e164 isEqual:otherPhoneNumber.e164];
}

@end

NS_ASSUME_NONNULL_END
