//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/FunctionalUtil.h>
#import <SignalServiceKit/PhoneNumberUtil.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <libPhoneNumber_iOS/NBPhoneNumber.h>

NS_ASSUME_NONNULL_BEGIN

@interface PhoneNumberUtil ()

@property (nonatomic, readonly) NSMutableDictionary *countryCodesFromCallingCodeCache;
@property (nonatomic, readonly) AnyLRUCache *parsedPhoneNumberCache;

@end

#pragma mark -

@implementation PhoneNumberUtil

+ (PhoneNumberUtil *)sharedThreadLocal
{
    NSString *key = PhoneNumberUtil.logTag;
    PhoneNumberUtil *_Nullable threadLocal = NSThread.currentThread.threadDictionary[key];
    if (!threadLocal) {
        threadLocal = [PhoneNumberUtil new];
        NSThread.currentThread.threadDictionary[key] = threadLocal;
    }
    return threadLocal;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        _nbPhoneNumberUtil = [[NBPhoneNumberUtil alloc] init];
        _countryCodesFromCallingCodeCache = [NSMutableDictionary new];
        _parsedPhoneNumberCache = [[AnyLRUCache alloc] initWithMaxSize:256 nseMaxSize:0 shouldEvacuateInBackground:NO];
    }

    return self;
}

- (nullable NBPhoneNumber *)parse:(NSString *)numberToParse
                    defaultRegion:(NSString *)defaultRegion
                            error:(NSError **)error
{
    NSString *hashKey = [NSString stringWithFormat:@"numberToParse:%@defaultRegion:%@", numberToParse, defaultRegion];

    NBPhoneNumber *_Nullable result = (NBPhoneNumber *)[self.parsedPhoneNumberCache objectForKey:hashKey];

    if (!result) {
        result = [self.nbPhoneNumberUtil parse:numberToParse defaultRegion:defaultRegion error:error];
        if (error && *error) {
            OWSAssertDebug(!result);
            return nil;
        }

        OWSAssertDebug(result);

        if (result) {
            [self.parsedPhoneNumberCache setObject:result forKey:hashKey];
        } else {
            [self.parsedPhoneNumberCache setObject:[NSNull null] forKey:hashKey];
        }
    }

    if ([result class] == [NSNull class]) {
        return nil;
    } else {
        return result;
    }
}

- (NSString *)format:(NBPhoneNumber *)phoneNumber
        numberFormat:(NBEPhoneNumberFormat)numberFormat
               error:(NSError **)error
{
    return [self.nbPhoneNumberUtil format:phoneNumber numberFormat:numberFormat error:error];
}

// country code -> country name
+ (nullable NSString *)countryNameFromCountryCode:(NSString *)countryCode
{
    OWSAssertDebug(countryCode != nil);

    if (countryCode.length < 1) {
        return NSLocalizedString(@"UNKNOWN_VALUE", "Indicates an unknown or unrecognizable value.");
    }
    NSDictionary *countryCodeComponent = @{NSLocaleCountryCode : countryCode};
    NSString *identifier               = [NSLocale localeIdentifierFromComponents:countryCodeComponent];
    NSString *countryName = [NSLocale.currentLocale displayNameForKey:NSLocaleIdentifier value:identifier];
    if (countryName.length < 1) {
        countryName = [NSLocale.systemLocale displayNameForKey:NSLocaleIdentifier value:identifier];
    }
    if (countryName.length < 1) {
        countryName = NSLocalizedString(@"UNKNOWN_VALUE", "Indicates an unknown or unrecognizable value.");
    }
    return countryName;
}

// country code -> calling code
+ (NSString *)callingCodeFromCountryCode:(NSString *)countryCode
{
    if (countryCode.length < 1) {
        return @"+0";
    }

    if ([countryCode isEqualToString:@"AQ"]) {
        // Antarctica
        return @"+672";
    } else if ([countryCode isEqualToString:@"BV"]) {
        // Bouvet Island
        return @"+55";
    } else if ([countryCode isEqualToString:@"IC"]) {
        // Canary Islands
        return @"+34";
    } else if ([countryCode isEqualToString:@"EA"]) {
        // Ceuta & Melilla
        return @"+34";
    } else if ([countryCode isEqualToString:@"CP"]) {
        // Clipperton Island
        //
        // This country code should be filtered - it does not appear to have a calling code.
        return nil;
    } else if ([countryCode isEqualToString:@"DG"]) {
        // Diego Garcia
        return @"+246";
    } else if ([countryCode isEqualToString:@"TF"]) {
        // French Southern Territories
        return @"+262";
    } else if ([countryCode isEqualToString:@"HM"]) {
        // Heard & McDonald Islands
        return @"+672";
    } else if ([countryCode isEqualToString:@"XK"]) {
        // Kosovo
        return @"+383";
    } else if ([countryCode isEqualToString:@"PN"]) {
        // Pitcairn Islands
        return @"+64";
    } else if ([countryCode isEqualToString:@"GS"]) {
        // So. Georgia & So. Sandwich Isl.
        return @"+500";
    } else if ([countryCode isEqualToString:@"UM"]) {
        // U.S. Outlying Islands
        return @"+1";
    }

    NSString *callingCode =
        [NSString stringWithFormat:@"%@%@",
                  COUNTRY_CODE_PREFIX,
                  [[[self sharedThreadLocal] nbPhoneNumberUtil] getCountryCodeForRegion:countryCode]];
    return callingCode;
}

- (NSArray<NSString *> *)countryCodesFromCallingCode:(NSString *)callingCode
{
    @synchronized(self)
    {
        OWSAssertDebug(callingCode.length > 0);

        NSArray *result = self.countryCodesFromCallingCodeCache[callingCode];
        if (!result) {
            NSMutableArray *countryCodes = [NSMutableArray new];
            for (NSString *countryCode in [PhoneNumberUtil countryCodesSortedByPopulationDescending]) {
                NSString *callingCodeForCountryCode = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
                if ([callingCode isEqualToString:callingCodeForCountryCode]) {
                    [countryCodes addObject:countryCode];
                }
            }
            result = [countryCodes copy];
            self.countryCodesFromCallingCodeCache[callingCode] = result;
        }
        return result;
    }
}

- (NSString *)probableCountryCodeForCallingCode:(NSString *)callingCode
{
    OWSAssertDebug(callingCode.length > 0);

    NSArray<NSString *> *countryCodes = [self countryCodesFromCallingCode:callingCode];
    return (countryCodes.count > 0 ? countryCodes[0] : nil);
}

+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString {
    NSCharacterSet *whitespaceSet = NSCharacterSet.whitespaceCharacterSet;
    NSArray *queryStrings         = [queryString componentsSeparatedByCharactersInSet:whitespaceSet];
    NSArray *nameStrings          = [nameString componentsSeparatedByCharactersInSet:whitespaceSet];

    return [queryStrings allSatisfy:^BOOL(NSString *query) {
        if (query.length == 0)
            return YES;
        return [nameStrings anySatisfy:^BOOL(NSString *nameWord) {
            NSStringCompareOptions searchOpts = NSCaseInsensitiveSearch | NSAnchoredSearch;
            return [nameWord rangeOfString:query options:searchOpts].location != NSNotFound;
        }];
    }];
}

// search term -> country codes
+ (NSArray *)countryCodesForSearchTerm:(nullable NSString *)searchTerm {
    searchTerm = [searchTerm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSArray *countryCodes = NSLocale.ISOCountryCodes;

    countryCodes = [countryCodes filter:^(NSString *countryCode) {
        NSString *countryName = [self countryNameFromCountryCode:countryCode];
        NSString *callingCode = [self callingCodeFromCountryCode:countryCode];

        if (countryName.length < 1 || callingCode.length < 1 || [callingCode isEqualToString:@"+0"]) {
            // Filter out countries without a valid calling code.
            return NO;
        }

        if (searchTerm.length < 1) {
            return YES;
        }

        if ([self name:countryName matchesQuery:searchTerm]) {
            return YES;
        }

        if ([self name:countryCode matchesQuery:searchTerm]) {
            return YES;
        }

        // We rely on the already internationalized string; as that is what
        // the user would see entered (i.e. with COUNTRY_CODE_PREFIX).

        if ([callingCode containsString:searchTerm]) {
            return YES;
        }

        return NO;
    }];

    return [self sortedCountryCodesByName:countryCodes];
}

+ (NSArray *)sortedCountryCodesByName:(NSArray *)countryCodesByISOCode {
    return [countryCodesByISOCode sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
      return [[self countryNameFromCountryCode:obj1] caseInsensitiveCompare:[self countryNameFromCountryCode:obj2]];
    }];
}

// black  magic
+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh {
    OWSAssertDebug(source != nil);
    OWSAssertDebug(target != nil);
    OWSAssertDebug(offset <= source.length);
    if (source == nil || target == nil || offset > source.length) {
        return 0;
    }

    NSUInteger n = source.length;
    NSUInteger m = target.length;

    int moves[n + 1][m + 1];
    {
        // Wagner-Fischer algorithm for computing edit distance, with a tweaks:
        // - Tracks best moves at each location, to allow reconstruction of edit path
        // - Does not allow substitutions
        // - Over-values digits relative to other characters, so they're "harder" to delete or insert
        const int DIGIT_VALUE = 10;
        NSUInteger scores[n + 1][m + 1];
        moves[0][0]  = 0; // (match) move up and left
        scores[0][0] = 0;
        for (NSUInteger i = 1; i <= n; i++) {
            scores[i][0] = i;
            moves[i][0]  = -1; // (deletion) move left
        }
        for (NSUInteger j = 1; j <= m; j++) {
            scores[0][j] = j;
            moves[0][j]  = +1; // (insertion) move up
        }

        NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
        for (NSUInteger i = 1; i <= n; i++) {
            unichar c1    = [source characterAtIndex:i - 1];
            bool isDigit1 = [digits characterIsMember:c1];
            for (NSUInteger j = 1; j <= m; j++) {
                unichar c2    = [target characterAtIndex:j - 1];
                bool isDigit2 = [digits characterIsMember:c2];
                if (c1 == c2) {
                    scores[i][j] = scores[i - 1][j - 1];
                    moves[i][j]  = 0; // move up-and-left
                } else {
                    NSUInteger del = scores[i - 1][j] + (isDigit1 ? DIGIT_VALUE : 1);
                    NSUInteger ins = scores[i][j - 1] + (isDigit2 ? DIGIT_VALUE : 1);
                    bool isDel     = del < ins;
                    scores[i][j]   = isDel ? del : ins;
                    moves[i][j]    = isDel ? -1 : +1;
                }
            }
        }
    }

    // Backtrack to find desired corresponding offset
    for (NSUInteger i = n, j = m;; i -= 1) {
        if (i == offset && preferHigh)
            return j; // early exit
        while (moves[i][j] == +1)
            j -= 1; // zip upward
        if (i == offset)
            return j; // late exit
        if (moves[i][j] == 0)
            j -= 1;
    }
}

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode
{
    PhoneNumberUtil *sharedUtil = [self sharedThreadLocal];

    // Signal users are very likely using mobile devices, so prefer that kind of example.
    NSError *error;
    NBPhoneNumber *nbPhoneNumber =
        [sharedUtil.nbPhoneNumberUtil getExampleNumberForType:countryCode type:NBEPhoneNumberTypeMOBILE error:&error];
    OWSAssertDebug(!error);
    if (!nbPhoneNumber) {
        // For countries that with similar mobile and land lines, use "line or mobile"
        // examples.
        nbPhoneNumber = [sharedUtil.nbPhoneNumberUtil getExampleNumberForType:countryCode
                                                                         type:NBEPhoneNumberTypeFIXED_LINE_OR_MOBILE
                                                                        error:&error];
        OWSAssertDebug(!error);
    }
    NSString *result = (nbPhoneNumber
            ? [sharedUtil.nbPhoneNumberUtil format:nbPhoneNumber numberFormat:NBEPhoneNumberFormatE164 error:&error]
            : nil);
    OWSAssertDebug(!error);
    return result;
}

@end

NS_ASSUME_NONNULL_END
