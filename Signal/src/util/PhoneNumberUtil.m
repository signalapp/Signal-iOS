#import "PhoneNumberUtil.h"
#import "ContactsManager.h"
#import "NBPhoneNumberUtil.h"
#import "Util.h"

@implementation PhoneNumberUtil


+ (NSString *)countryNameFromCountryCode:(NSString *)code {
    NSDictionary *countryCodeComponent = @{NSLocaleCountryCode: code};
    NSString *identifier = [NSLocale localeIdentifierFromComponents:countryCodeComponent];
    NSString *country = [NSLocale.currentLocale displayNameForKey:NSLocaleIdentifier
                                                              value:identifier];
    return country;
}

+ (NSString *)callingCodeFromCountryCode:(NSString *)code {
    NSNumber *callingCode = [NBPhoneNumberUtil.sharedInstance getCountryCodeForRegion:code];
    return [NSString stringWithFormat:@"%@%@", COUNTRY_CODE_PREFIX, callingCode];
}

+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm {
    
    NSArray *countryCodes = NSLocale.ISOCountryCodes;
    
    if (searchTerm) {
        countryCodes = [countryCodes filter:^int(NSString *code) {
            NSString *countryName = [self countryNameFromCountryCode:code];
            return [ContactsManager name:countryName matchesQuery:searchTerm];
        }];
    }
    return countryCodes;
}

+ (NSString*) normalizePhoneNumber:(NSString *) number {
    return [NBPhoneNumberUtil.sharedInstance normalizePhoneNumber:number];
}

+(NSUInteger) translateCursorPosition:(NSUInteger)offset
                                 from:(NSString*)source
                                   to:(NSString*)target
                    stickingRightward:(bool)preferHigh {
    require(source != nil);
    require(target != nil);
    require(offset <= source.length);
    
    NSUInteger n = source.length;
    NSUInteger m = target.length;
    
    int moves[n+1][m+1];
    {
        // Wagner-Fischer algorithm for computing edit distance, with a tweaks:
        // - Tracks best moves at each location, to allow reconstruction of edit path
        // - Does not allow substitutions
        // - Over-values digits relative to other characters, so they're "harder" to delete or insert
        const int DIGIT_VALUE = 10;
        NSUInteger scores[n+1][m+1];
        moves[0][0] = 0; // (match) move up and left
        scores[0][0] = 0;
        for (NSUInteger i = 1; i <= n; i++) {
            scores[i][0] = i;
            moves[i][0] = -1; // (deletion) move left
        }
        for (NSUInteger j = 1; j <= m; j++) {
            scores[0][j] = j;
            moves[0][j] = +1; // (insertion) move up
        }
        
        NSCharacterSet* digits = NSCharacterSet.decimalDigitCharacterSet;
        for (NSUInteger i = 1; i <= n; i++) {
            unichar c1 = [source characterAtIndex:i-1];
            bool isDigit1 = [digits characterIsMember:c1];
            for (NSUInteger j = 1; j <= m; j++) {
                unichar c2 = [target characterAtIndex:j-1];
                bool isDigit2 = [digits characterIsMember:c2];
                if (c1 == c2) {
                    scores[i][j] = scores[i-1][j-1];
                    moves[i][j] = 0; // move up-and-left
                } else {
                    NSUInteger del = scores[i-1][j] + (isDigit1 ? DIGIT_VALUE : 1);
                    NSUInteger ins = scores[i][j-1] + (isDigit2 ? DIGIT_VALUE : 1);
                    bool isDel = del < ins;
                    scores[i][j] = isDel ? del : ins;
                    moves[i][j] = isDel ? -1 : +1;
                }
            }
        }
    }
    
    // Backtrack to find desired corresponding offset
    for (NSUInteger i = n, j = m; ; i -= 1) {
        if (i == offset && preferHigh) return j; // early exit
        while (moves[i][j] == +1) j -= 1; // zip upward
        if (i == offset) return j; // late exit
        if (moves[i][j] == 0) j -= 1;
    }
}

@end
