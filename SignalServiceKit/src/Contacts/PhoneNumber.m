//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "PhoneNumber.h"
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

@property (nonatomic, readonly) NBPhoneNumber *phoneNumber;
@property (nonatomic, readonly) NSString *e164;

@end

#pragma mark -

@implementation PhoneNumber

- (instancetype)initWithPhoneNumber:(NBPhoneNumber *)phoneNumber e164:(NSString *)e164
{
    if (self = [self init]) {
        OWSAssertDebug(phoneNumber);
        OWSAssertDebug(e164.length > 0);

        _phoneNumber = phoneNumber;
        _e164 = e164;
    }
    return self;
}

+ (nullable PhoneNumber *)phoneNumberFromText:(NSString *)text andRegion:(NSString *)regionCode {
    OWSAssertDebug(text != nil);
    OWSAssertDebug(regionCode != nil);

    PhoneNumberUtil *phoneUtil = [PhoneNumberUtil sharedThreadLocal];

    NSError *parseError   = nil;
    NBPhoneNumber *number = [phoneUtil parse:text defaultRegion:regionCode error:&parseError];

    if (parseError) {
        OWSLogVerbose(@"parseError: %@", parseError);
        return nil;
    }

    if (![phoneUtil.nbPhoneNumberUtil isPossibleNumber:number]) {
        return nil;
    }

    NSError *toE164Error;
    NSString *e164 = [phoneUtil format:number numberFormat:NBEPhoneNumberFormatE164 error:&toE164Error];
    if (toE164Error) {
        OWSLogDebug(@"Issue while formatting number: %@", [toE164Error description]);
        return nil;
    }

    return [[PhoneNumber alloc] initWithPhoneNumber:number e164:e164];
}

+ (nullable PhoneNumber *)phoneNumberFromUserSpecifiedText:(NSString *)text {
    OWSAssertDebug(text != nil);

    return [PhoneNumber phoneNumberFromText:text andRegion:[self defaultCountryCode]];
}

+ (NSString *)defaultCountryCode
{
    NSLocale *locale = [NSLocale currentLocale];

    NSString *_Nullable countryCode = nil;
#if TARGET_OS_IPHONE
    countryCode = [[PhoneNumberUtil sharedThreadLocal].nbPhoneNumberUtil countryCodeByCarrier];

    if ([countryCode isEqualToString:@"ZZ"]) {
        countryCode = [locale objectForKey:NSLocaleCountryCode];
    }
#else
    countryCode = [locale objectForKey:NSLocaleCountryCode];
#endif
    if (!countryCode) {
        if (!Platform.isSimulator) {
            OWSFailDebugUnlessRunningTests(@"Could not identify country code for locale: %@", locale);
        }
        countryCode = @"US";
    }
    return countryCode;
}

+ (nullable PhoneNumber *)phoneNumberFromE164:(NSString *)text {
    OWSAssertDebug(text != nil);
    OWSAssertDebug([text hasPrefix:COUNTRY_CODE_PREFIX]);
    PhoneNumber *number = [PhoneNumber phoneNumberFromText:text andRegion:@"ZZ"];

    OWSAssertDebug(number != nil);
    return number;
}

+ (NSString *)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString *)input {
    return [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:input
                                                               withSpecifiedRegionCode:[self defaultCountryCode]];
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

    static NSMutableDictionary<NSString *, NSString *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary new];
    });

    @synchronized(cache) {
        NSString *cacheKey = [[input stringByAppendingString:@"@"] stringByAppendingString:regionCode];
        NSString *_Nullable cachedValue = cache[cacheKey];
        if (cachedValue != nil) {
            return cachedValue;
        }

        NBAsYouTypeFormatter *formatter = [[NBAsYouTypeFormatter alloc] initWithRegionCode:regionCode];
        NSString *result = input;
        for (NSUInteger i = 0; i < input.length; i++) {
            result = [formatter inputDigit:[input substringWithRange:NSMakeRange(i, 1)]];
        }
        cache[cacheKey] = result;
        return result;
    }
}

+ (NSString *)formatIntAsEN:(int)value
{
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSNumberFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    });
    return [formatter stringFromNumber:@(value)];
}

+ (NSString *)bestEffortLocalizedPhoneNumberWithE164:(NSString *)phoneNumber
{
    OWSAssertDebug(phoneNumber);

    if (![phoneNumber hasPrefix:COUNTRY_CODE_PREFIX]) {
        return phoneNumber;
    }

    PhoneNumber *_Nullable parsedPhoneNumber = [self tryParsePhoneNumberFromE164:phoneNumber];
    if (!parsedPhoneNumber) {
        OWSLogWarn(@"could not parse phone number.");
        return phoneNumber;
    }
    NSNumber *_Nullable countryCode = [parsedPhoneNumber getCountryCode];
    if (!countryCode) {
        OWSLogWarn(@"parsed phone number has no country code.");
        return phoneNumber;
    }
    NSString *countryCodeString = [self formatIntAsEN:countryCode.intValue];
    if (countryCodeString.length < 1) {
        OWSLogWarn(@"invalid country code.");
        return phoneNumber;
    }
    NSString *_Nullable formattedPhoneNumber =
        [self bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:phoneNumber
                                                     withSpecifiedRegionCode:countryCodeString];
    if (!countryCode) {
        OWSLogWarn(@"could not format phone number.");
        return phoneNumber;
    }
    return formattedPhoneNumber;
}

+ (NSString *)regionCodeFromCountryCodeString:(NSString *)countryCodeString {
    NBPhoneNumberUtil *phoneUtil = [PhoneNumberUtil sharedThreadLocal].nbPhoneNumberUtil;
    NSString *regionCode =
        [phoneUtil getRegionCodeForCountryCode:@([[countryCodeString substringFromIndex:1] integerValue])];
    return regionCode;
}

+ (nullable PhoneNumber *)tryParsePhoneNumberFromUserSpecifiedText:(NSString *)text {
    OWSAssertDebug(text != nil);

    if ([text isEqualToString:@""]) {
        return nil;
    }
    NSString *sanitizedString = [self removeFormattingCharacters:text];

    return [self phoneNumberFromUserSpecifiedText:sanitizedString];
}

+ (nullable NSString *)nationalPrefixTransformRuleForDefaultRegion
{
    static NSString *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *defaultCountryCode = [self defaultCountryCode];
        NBMetadataHelper *helper = [[NBMetadataHelper alloc] init];
        NBPhoneMetaData *defaultRegionMetadata = [helper getMetadataForRegion:defaultCountryCode];
        result = defaultRegionMetadata.nationalPrefixTransformRule;
    });
    return result;
}

// clientPhoneNumber is the local user's phone number and should never change.
+ (nullable NSString *)nationalPrefixTransformRuleForClientPhoneNumber:(NSString *)clientPhoneNumber
{
    if (clientPhoneNumber.length < 1) {
        return nil;
    }
    static NSString *result = nil;
    static NSString *cachedClientPhoneNumber = nil;
    static dispatch_once_t onceToken;

    // clientPhoneNumber is the local user's phone number and should never change.
    static void (^updateCachedClientPhoneNumber)(void);
    updateCachedClientPhoneNumber = ^(void) {
        NSNumber *localCallingCode = [[PhoneNumber phoneNumberFromE164:clientPhoneNumber] getCountryCode];
        if (localCallingCode != nil) {
            NSString *localCallingCodePrefix = [NSString stringWithFormat:@"+%@", localCallingCode];
            NSString *localCountryCode =
                [PhoneNumberUtil.sharedThreadLocal probableCountryCodeForCallingCode:localCallingCodePrefix];
            if (localCountryCode && ![localCountryCode isEqualToString:[self defaultCountryCode]]) {
                NBMetadataHelper *helper = [[NBMetadataHelper alloc] init];
                NBPhoneMetaData *localNumberRegionMetadata = [helper getMetadataForRegion:localCountryCode];
                result = localNumberRegionMetadata.nationalPrefixTransformRule;
            } else {
                result = nil;
            }
        }
        cachedClientPhoneNumber = [clientPhoneNumber copy];
    };

#ifdef DEBUG
    // For performance, we want to cache this result, but it breaks tests since local number
    // can change.
    if (CurrentAppContext().isRunningTests) {
        updateCachedClientPhoneNumber();
    } else {
        dispatch_once(&onceToken, ^{
            updateCachedClientPhoneNumber();
        });
    }
#else
    dispatch_once(&onceToken, ^{
        updateCachedClientPhoneNumber();
    });
    OWSAssertDebug([cachedClientPhoneNumber isEqualToString:clientPhoneNumber]);
#endif

    return result;
}

+ (NSArray<PhoneNumber *> *)tryParsePhoneNumbersFromUserSpecifiedText:(NSString *)text
                                                     clientPhoneNumber:(NSString *)clientPhoneNumber
{
    NSMutableArray<PhoneNumber *> *result =
        [[self tryParsePhoneNumbersFromNormalizedText:text clientPhoneNumber:clientPhoneNumber] mutableCopy];

    // A handful of countries (Mexico, Argentina, etc.) require a "national" prefix after
    // their country calling code.
    //
    // It's a bit hacky, but we reconstruct these national prefixes from libPhoneNumber's
    // parsing logic.  It's okay if we botch this a little.  The risk is that we end up with
    // some misformatted numbers with extra non-numeric regex syntax.  These erroneously
    // parsed numbers will never be presented to the user, since they'll never survive the
    // contacts intersection.
    //
    // 1. Try to apply a "national prefix" using the phone's region.
    NSString *nationalPrefixTransformRuleForDefaultRegion = [self nationalPrefixTransformRuleForDefaultRegion];
    if ([nationalPrefixTransformRuleForDefaultRegion containsString:@"$1"]) {
        NSString *normalizedText =
            [nationalPrefixTransformRuleForDefaultRegion stringByReplacingOccurrencesOfString:@"$1" withString:text];
        if (![normalizedText containsString:@"$"]) {
            [result addObjectsFromArray:[self tryParsePhoneNumbersFromNormalizedText:normalizedText
                                                                   clientPhoneNumber:clientPhoneNumber]];
        }
    }

    // 2. Try to apply a "national prefix" using the region that corresponds to the
    //    calling code for the local phone number.
    NSString *nationalPrefixTransformRuleForClientPhoneNumber =
        [self nationalPrefixTransformRuleForClientPhoneNumber:clientPhoneNumber];
    if ([nationalPrefixTransformRuleForClientPhoneNumber containsString:@"$1"]) {
        NSString *normalizedText =
            [nationalPrefixTransformRuleForClientPhoneNumber stringByReplacingOccurrencesOfString:@"$1"
                                                                                       withString:text];
        if (![normalizedText containsString:@"$"]) {
            [result addObjectsFromArray:[self tryParsePhoneNumbersFromNormalizedText:normalizedText
                                                                   clientPhoneNumber:clientPhoneNumber]];
        }
    }

    return [result copy];
}

+ (NSArray<PhoneNumber *> *)tryParsePhoneNumbersFromNormalizedText:(NSString *)text
                                                 clientPhoneNumber:(NSString *)clientPhoneNumber
{
    OWSAssertDebug(text != nil);

    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([text isEqualToString:@""]) {
        return nil;
    }
    
    NSString *sanitizedString = [self removeFormattingCharacters:text];
    OWSAssertDebug(sanitizedString != nil);

    NSMutableArray *result = [NSMutableArray new];
    NSMutableSet *phoneNumberSet = [NSMutableSet new];
    void (^tryParsingWithCountryCode)(NSString *, NSString *) = ^(NSString *text,
                                                      NSString *countryCode) {
        PhoneNumber *phoneNumber = [PhoneNumber phoneNumberFromText:text
                                                          andRegion:countryCode];
        if (phoneNumber && [phoneNumber toE164] && ![phoneNumberSet containsObject:[phoneNumber toE164]]) {
            [result addObject:phoneNumber];
            [phoneNumberSet addObject:[phoneNumber toE164]];
        }
    };

    tryParsingWithCountryCode(sanitizedString, [self defaultCountryCode]);

    if ([sanitizedString hasPrefix:@"+"]) {
        // If the text starts with "+", don't try prepending
        // anything else.
        return result;
    }

    // Try just adding "+" and parsing it.
    tryParsingWithCountryCode([NSString stringWithFormat:@"+%@", sanitizedString], [self defaultCountryCode]);

    // Order matters; better results should appear first so prefer
    // matches with the same country code as this client's phone number.
    if (clientPhoneNumber.length == 0) {
        OWSFailDebug(@"clientPhoneNumber had unexpected length");
        return result;
    }

    // Note that NBPhoneNumber uses "country code" to refer to what we call a
    // "calling code" (i.e. 44 in +44123123).  Within SSK we use "country code"
    // (and sometimes "region code") to refer to a country's ISO 2-letter code
    // (ISO 3166-1 alpha-2).
    NSNumber *callingCodeForLocalNumber = [[PhoneNumber phoneNumberFromE164:clientPhoneNumber] getCountryCode];
    if (callingCodeForLocalNumber == nil) {
        OWSFailDebug(@"callingCodeForLocalNumber was unexpectedly nil");
        return result;
    }

    NSString *callingCodePrefix = [NSString stringWithFormat:@"+%@", callingCodeForLocalNumber];

    tryParsingWithCountryCode([callingCodePrefix stringByAppendingString:sanitizedString], [self defaultCountryCode]);

    // Try to determine what the country code is for the local phone number
    // and also try parsing the phone number using that country code if it
    // differs from the device's region code.
    //
    // For example, a French person living in Italy might have an
    // Italian phone number but use French region/language for their
    // phone. They're likely to have both Italian and French contacts.
    NSString *localCountryCode =
        [PhoneNumberUtil.sharedThreadLocal probableCountryCodeForCallingCode:callingCodePrefix];
    if (localCountryCode && ![localCountryCode isEqualToString:[self defaultCountryCode]]) {
        tryParsingWithCountryCode([callingCodePrefix stringByAppendingString:sanitizedString], localCountryCode);
    }

    NSString *_Nullable phoneNumberByApplyingMissingAreaCode =
        [self applyMissingAreaCodeWithCallingCodeForReferenceNumber:callingCodeForLocalNumber
                                                    referenceNumber:clientPhoneNumber
                                                 sanitizedInputText:sanitizedString];
    if (phoneNumberByApplyingMissingAreaCode) {
        tryParsingWithCountryCode(phoneNumberByApplyingMissingAreaCode, localCountryCode);
    }

    for (NSString *phoneNumber in [self generateAdditionalMexicanCandidatesIfMexicanNumbers:phoneNumberSet]) {
        tryParsingWithCountryCode(phoneNumber, @"MX");
    }

    return result;
}

#pragma mark - missing/extra mobile prefix

+ (NSSet<NSString *> *)generateAdditionalMexicanCandidatesIfMexicanNumbers:(NSSet<NSString *> *)e164PhoneNumbers
{
    NSMutableSet<NSString *> *mexicanNumbers = [NSMutableSet new];
    for (NSString *phoneNumber in e164PhoneNumbers) {
        if ([phoneNumber hasPrefix:@"+52"]) {
            [mexicanNumbers addObject:phoneNumber];
        }
    }

    NSMutableSet<NSString *> *additionalCandidates = [NSMutableSet new];
    for (NSString *mexicanNumber in mexicanNumbers) {
        if ([mexicanNumber hasPrefix:@"+521"]) {
            NSString *withoutMobilePrefix = [mexicanNumber stringByReplacingOccurrencesOfString:@"+521"
                                                                                     withString:@"+52"];
            [additionalCandidates addObject:mexicanNumber];
            [additionalCandidates addObject:withoutMobilePrefix];
        } else {
            OWSAssertDebug([mexicanNumber hasPrefix:@"+52"]);
            NSString *withMobilePrefix = [mexicanNumber stringByReplacingOccurrencesOfString:@"+52" withString:@"+521"];
            [additionalCandidates addObject:mexicanNumber];
            [additionalCandidates addObject:withMobilePrefix];
        }
    }

    return [additionalCandidates copy];
}

#pragma mark - missing area code

+ (nullable NSString *)applyMissingAreaCodeWithCallingCodeForReferenceNumber:(NSNumber *)callingCodeForReferenceNumber
                                                             referenceNumber:(NSString *)referenceNumber
                                                          sanitizedInputText:(NSString *)sanitizedInputText
{
    if ([callingCodeForReferenceNumber isEqual:@(55)]) {
        return
            [self applyMissingBrazilAreaCodeWithReferenceNumber:referenceNumber sanitizedInputText:sanitizedInputText];
    } else if ([callingCodeForReferenceNumber isEqual:@(1)]) {
        return [self applyMissingUnitedStatesAreaCodeWithReferenceNumber:referenceNumber
                                                      sanitizedInputText:sanitizedInputText];
    } else {
        return nil;
    }
}

#pragma mark - missing brazil area code

+ (nullable NSString *)applyMissingBrazilAreaCodeWithReferenceNumber:(NSString *)referenceNumber
                                                  sanitizedInputText:(NSString *)sanitizedInputText
{
    NSError *error;
    NSRegularExpression *missingAreaCodeRegex =
        [[NSRegularExpression alloc] initWithPattern:@"^(9?\\d{8})$" options:0 error:&error];
    if (error) {
        OWSFailDebug(@"failure: %@", error);
        return nil;
    }

    if ([missingAreaCodeRegex firstMatchInString:sanitizedInputText
                                         options:0
                                           range:NSMakeRange(0, sanitizedInputText.length)]
        == nil) {
    }

    NSString *_Nullable referenceAreaCode = [self brazilAreaCodeFromReferenceNumberE164:referenceNumber];
    if (!referenceAreaCode) {
        return nil;
    }
    return [NSString stringWithFormat:@"+55%@%@", referenceAreaCode, sanitizedInputText];
}

+ (nullable NSString *)brazilAreaCodeFromReferenceNumberE164:(NSString *)referenceNumberE164
{
    NSError *error;
    NSRegularExpression *areaCodeRegex =
        [[NSRegularExpression alloc] initWithPattern:@"^\\+55(\\d{2})9?\\d{8}" options:0 error:&error];
    if (error) {
        OWSFailDebug(@"failure: %@", error);
        return nil;
    }

    NSArray<NSTextCheckingResult *> *matches =
        [areaCodeRegex matchesInString:referenceNumberE164 options:0 range:NSMakeRange(0, referenceNumberE164.length)];
    if (matches.count == 0) {
        OWSFailDebug(@"failure: unexpectedly unable to extract area code from US number");
        return nil;
    }
    NSTextCheckingResult *match = matches[0];

    NSRange firstCaptureRange = [match rangeAtIndex:1];
    return [referenceNumberE164 substringWithRange:firstCaptureRange];
}

#pragma mark - missing US area code

+ (nullable NSString *)applyMissingUnitedStatesAreaCodeWithReferenceNumber:(NSString *)referenceNumber
                                                        sanitizedInputText:(NSString *)sanitizedInputText
{
    NSError *error;
    NSRegularExpression *missingAreaCodeRegex =
        [[NSRegularExpression alloc] initWithPattern:@"^(\\d{7})$" options:0 error:&error];
    if (error) {
        OWSFailDebug(@"failure: %@", error);
        return nil;
    }

    if ([missingAreaCodeRegex firstMatchInString:sanitizedInputText
                                         options:0
                                           range:NSMakeRange(0, sanitizedInputText.length)]
        == nil) {
        // area code isn't missing
        return nil;
    }

    NSString *_Nullable referenceAreaCode = [self unitedStateAreaCodeFromReferenceNumberE164:referenceNumber];
    if (!referenceAreaCode) {
        return nil;
    }
    return [NSString stringWithFormat:@"+1%@%@", referenceAreaCode, sanitizedInputText];
}

+ (nullable NSString *)unitedStateAreaCodeFromReferenceNumberE164:(NSString *)referenceNumberE164
{
    NSError *error;
    NSRegularExpression *areaCodeRegex =
        [[NSRegularExpression alloc] initWithPattern:@"^\\+1(\\d{3})" options:0 error:&error];
    if (error) {
        OWSFailDebug(@"failure: %@", error);
        return nil;
    }

    NSArray<NSTextCheckingResult *> *matches =
        [areaCodeRegex matchesInString:referenceNumberE164 options:0 range:NSMakeRange(0, referenceNumberE164.length)];
    if (matches.count == 0) {
        OWSFailDebug(@"failure: unexpectedly unable to extract area code from US number");
        return nil;
    }
    NSTextCheckingResult *match = matches[0];

    NSRange firstCaptureRange = [match rangeAtIndex:1];
    return [referenceNumberE164 substringWithRange:firstCaptureRange];
}

#pragma mark -

+ (NSString *)removeFormattingCharacters:(NSString *)inputString {
    char outputString[inputString.length + 1];

    int outputLength = 0;
    for (NSUInteger i = 0; i < inputString.length; i++) {
        unichar c = [inputString characterAtIndex:i];
        if (c == '+' || (c >= '0' && c <= '9')) {
            outputString[outputLength++] = (char)c;
        }
    }

    outputString[outputLength] = 0;
    return [NSString stringWithUTF8String:(void *)outputString];
}

+ (nullable PhoneNumber *)tryParsePhoneNumberFromE164:(NSString *)text {
    OWSAssertDebug(text != nil);
    if (![text hasPrefix:COUNTRY_CODE_PREFIX]) {
        return nil;
    }

    return [self phoneNumberFromE164:text];
}

- (NSURL *)toSystemDialerURL {
    NSString *link = [NSString stringWithFormat:@"telprompt://%@", self.e164];
    return [NSURL URLWithString:link];
}

- (NSString *)toE164 {
    return self.e164;
}

- (nullable NSNumber *)getCountryCode {
    return self.phoneNumber.countryCode;
}

- (nullable NSString *)nationalNumber
{
    NSError *error;
    NSString *nationalNumber = [[PhoneNumberUtil sharedThreadLocal] format:self.phoneNumber
                                                              numberFormat:NBEPhoneNumberFormatNATIONAL
                                                                     error:&error];
    if (error) {
        OWSLogVerbose(@"error parsing number into national format: %@", error);
        return nil;
    }

    return nationalNumber;
}

- (BOOL)isValid
{
    return [[PhoneNumberUtil sharedThreadLocal].nbPhoneNumberUtil isValidNumber:self.phoneNumber];
}

- (NSString *)description {
    return self.e164;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:self.phoneNumber forKey:RPDefaultsKeyPhoneNumberString];
    [encoder encodeObject:self.e164 forKey:RPDefaultsKeyPhoneNumberCanonical];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if ((self = [super init])) {
        _phoneNumber = [decoder decodeObjectForKey:RPDefaultsKeyPhoneNumberString];
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

    return [self.phoneNumber isEqual:otherPhoneNumber.phoneNumber];
}

@end

NS_ASSUME_NONNULL_END
