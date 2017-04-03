//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "PhoneNumberUtil.h"
#import "ContactsManagerProtocol.h"
#import "FunctionalUtil.h"
#import "Util.h"

@implementation PhoneNumberUtil

+ (instancetype)sharedUtil {
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
      sharedInstance = [self.class new];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        _nbPhoneNumberUtil = [[NBPhoneNumberUtil alloc] init];

        OWSSingletonAssert();
    }

    return self;
}

// country code -> country name
+ (NSString *)countryNameFromCountryCode:(NSString *)countryCode {
    NSDictionary *countryCodeComponent = @{NSLocaleCountryCode : countryCode};
    NSString *identifier               = [NSLocale localeIdentifierFromComponents:countryCodeComponent];
    NSString *country                  = [NSLocale.currentLocale displayNameForKey:NSLocaleIdentifier value:identifier];
    return country;
}

// country code -> calling code
+ (NSString *)callingCodeFromCountryCode:(NSString *)countryCode
{
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

    NSString *callingCode = [NSString stringWithFormat:@"%@%@",
                                      COUNTRY_CODE_PREFIX,
                                      [[[self sharedUtil] nbPhoneNumberUtil] getCountryCodeForRegion:countryCode]];
    return callingCode;
}

+ (NSArray *)countryCodesFromCallingCode:(NSString *)callingCode {
    NSMutableArray *countryCodes = [NSMutableArray new];
    for (NSString *countryCode in NSLocale.ISOCountryCodes) {
        NSString *callingCodeForCountryCode = [self callingCodeFromCountryCode:countryCode];
        if ([callingCode isEqualToString:callingCodeForCountryCode]) {
            [countryCodes addObject:countryCode];
        }
    }
    return countryCodes;
}

+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString {
    NSCharacterSet *whitespaceSet = NSCharacterSet.whitespaceCharacterSet;
    NSArray *queryStrings         = [queryString componentsSeparatedByCharactersInSet:whitespaceSet];
    NSArray *nameStrings          = [nameString componentsSeparatedByCharactersInSet:whitespaceSet];

    return [queryStrings all:^int(NSString *query) {
        if (query.length == 0)
            return YES;
        return [nameStrings any:^int(NSString *nameWord) {
            NSStringCompareOptions searchOpts = NSCaseInsensitiveSearch | NSAnchoredSearch;
            return [nameWord rangeOfString:query options:searchOpts].location != NSNotFound;
        }];
    }];
}

// search term -> country codes
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm {
    searchTerm = [searchTerm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSArray *countryCodes = NSLocale.ISOCountryCodes;

    countryCodes = [countryCodes filter:^int(NSString *countryCode) {
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
    ows_require(source != nil);
    ows_require(target != nil);
    ows_require(offset <= source.length);

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

@end
