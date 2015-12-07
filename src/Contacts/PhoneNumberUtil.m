#import "Constraints.h"
#import "FunctionalUtil.h"
#import "PhoneNumberUtil.h"
#import "TextSecureKitEnv.h"
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
    }

    return self;
}

// country code -> country name
+ (NSString *)countryNameFromCountryCode:(NSString *)code {
    NSDictionary *countryCodeComponent = @{NSLocaleCountryCode : code};
    NSString *identifier               = [NSLocale localeIdentifierFromComponents:countryCodeComponent];
    NSString *country                  = [NSLocale.currentLocale displayNameForKey:NSLocaleIdentifier value:identifier];
    return country;
}

// country code -> calling code
+ (NSString *)callingCodeFromCountryCode:(NSString *)code {
    NSNumber *callingCode = [[[self sharedUtil] nbPhoneNumberUtil] getCountryCodeForRegion:code];
    return [NSString stringWithFormat:@"%@%@", COUNTRY_CODE_PREFIX, callingCode];
}

// search term -> country codes
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm {
    NSArray *countryCodes = NSLocale.ISOCountryCodes;

    if (searchTerm) {
        countryCodes = [countryCodes filter:^int(NSString *code) {
          NSString *countryName = [self countryNameFromCountryCode:code];
          NSString *callingCode = [self callingCodeFromCountryCode:code];

          if ([[[TextSecureKitEnv sharedEnv].contactsManager class] name:countryName matchesQuery:searchTerm]) {
              return YES;
          }

          // We rely on the already internationalized string; as that is what
          // the user would see entered (i.e. with COUNTRY_CODE_PREFIX).

          if ([callingCode containsString:searchTerm]) {
              return YES;
          }
          return NO;
        }];
    }

    return [self sortedCountryCodesByName:countryCodes];
}

+ (NSArray *)validCountryCallingPrefixes:(NSString *)string {
    NSArray *countryCodes = NSLocale.ISOCountryCodes;
    NSArray *matches      = [countryCodes filter:^int(NSString *code) {
      NSString *callingCode = [self callingCodeFromCountryCode:code];

      return [string hasPrefix:callingCode];
    }];

    return [matches sortedArrayWithOptions:NSSortConcurrent
                           usingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
                             if (obj1 == nil) {
                                 return obj2 ? NSOrderedAscending : NSOrderedSame;
                             }

                             if (obj2 == nil) {
                                 return NSOrderedDescending;
                             }

                             NSInteger d = (NSInteger)[obj1 length] - (NSInteger)[obj2 length];
                             return d ? (d < 0 ? NSOrderedAscending : NSOrderedDescending) : NSOrderedSame;
                           }];
}

+ (NSArray *)sortedCountryCodesByName:(NSArray *)countryCodesByISOCode {
    return [countryCodesByISOCode sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
      return [[self countryNameFromCountryCode:obj1] caseInsensitiveCompare:[self countryNameFromCountryCode:obj2]];
    }];
}

// normalizes a phone number, so parentheses and spaces are stripped
+ (NSString *)normalizePhoneNumber:(NSString *)number {
    return [[[self sharedUtil] nbPhoneNumberUtil] normalizePhoneNumber:number];
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