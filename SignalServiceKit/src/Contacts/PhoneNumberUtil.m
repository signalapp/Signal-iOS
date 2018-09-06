//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "PhoneNumberUtil.h"
#import "ContactsManagerProtocol.h"
#import "FunctionalUtil.h"
#import <libPhoneNumber_iOS/NBPhoneNumber.h>

@interface PhoneNumberUtil ()

@property (nonatomic, readonly) NSMutableDictionary *countryCodesFromCallingCodeCache;
@property (nonatomic, readonly) NSCache *parsedPhoneNumberCache;

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
        _parsedPhoneNumberCache = [NSCache new];
    }

    return self;
}

- (nullable NBPhoneNumber *)parse:(NSString *)numberToParse
                    defaultRegion:(NSString *)defaultRegion
                            error:(NSError **)error
{
    NSString *hashKey = [NSString stringWithFormat:@"numberToParse:%@defaultRegion:%@", numberToParse, defaultRegion];

    NBPhoneNumber *result = [self.parsedPhoneNumberCache objectForKey:hashKey];

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
+ (NSString *)countryNameFromCountryCode:(NSString *)countryCode {
    OWSAssertDebug(countryCode);

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

- (NSDictionary<NSString *, NSNumber *> *)countryCodeToPopulationMap
{
    static dispatch_once_t onceToken;
    static NSDictionary<NSString *, NSNumber *> *instance = nil;
    dispatch_once(&onceToken, ^{
        instance = @{
            @"AD" : @(84000),
            @"AE" : @(4975593),
            @"AF" : @(29121286),
            @"AG" : @(86754),
            @"AI" : @(13254),
            @"AL" : @(2986952),
            @"AM" : @(2968000),
            @"AN" : @(300000),
            @"AO" : @(13068161),
            @"AQ" : @(0),
            @"AR" : @(41343201),
            @"AS" : @(57881),
            @"AT" : @(8205000),
            @"AU" : @(21515754),
            @"AW" : @(71566),
            @"AX" : @(26711),
            @"AZ" : @(8303512),
            @"BA" : @(4590000),
            @"BB" : @(285653),
            @"BD" : @(156118464),
            @"BE" : @(10403000),
            @"BF" : @(16241811),
            @"BG" : @(7148785),
            @"BH" : @(738004),
            @"BI" : @(9863117),
            @"BJ" : @(9056010),
            @"BL" : @(8450),
            @"BM" : @(65365),
            @"BN" : @(395027),
            @"BO" : @(9947418),
            @"BQ" : @(18012),
            @"BR" : @(201103330),
            @"BS" : @(301790),
            @"BT" : @(699847),
            @"BV" : @(0),
            @"BW" : @(2029307),
            @"BY" : @(9685000),
            @"BZ" : @(314522),
            @"CA" : @(33679000),
            @"CC" : @(628),
            @"CD" : @(70916439),
            @"CF" : @(4844927),
            @"CG" : @(3039126),
            @"CH" : @(7581000),
            @"CI" : @(21058798),
            @"CK" : @(21388),
            @"CL" : @(16746491),
            @"CM" : @(19294149),
            @"CN" : @(1330044000),
            @"CO" : @(47790000),
            @"CR" : @(4516220),
            @"CS" : @(10829175),
            @"CU" : @(11423000),
            @"CV" : @(508659),
            @"CW" : @(141766),
            @"CX" : @(1500),
            @"CY" : @(1102677),
            @"CZ" : @(10476000),
            @"DE" : @(81802257),
            @"DJ" : @(740528),
            @"DK" : @(5484000),
            @"DM" : @(72813),
            @"DO" : @(9823821),
            @"DZ" : @(34586184),
            @"EC" : @(14790608),
            @"EE" : @(1291170),
            @"EG" : @(80471869),
            @"EH" : @(273008),
            @"ER" : @(5792984),
            @"ES" : @(46505963),
            @"ET" : @(88013491),
            @"FI" : @(5244000),
            @"FJ" : @(875983),
            @"FK" : @(2638),
            @"FM" : @(107708),
            @"FO" : @(48228),
            @"FR" : @(64768389),
            @"GA" : @(1545255),
            @"GB" : @(62348447),
            @"GD" : @(107818),
            @"GE" : @(4630000),
            @"GF" : @(195506),
            @"GG" : @(65228),
            @"GH" : @(24339838),
            @"GI" : @(27884),
            @"GL" : @(56375),
            @"GM" : @(1593256),
            @"GN" : @(10324025),
            @"GP" : @(443000),
            @"GQ" : @(1014999),
            @"GR" : @(11000000),
            @"GS" : @(30),
            @"GT" : @(13550440),
            @"GU" : @(159358),
            @"GW" : @(1565126),
            @"GY" : @(748486),
            @"HK" : @(6898686),
            @"HM" : @(0),
            @"HN" : @(7989415),
            @"HR" : @(4284889),
            @"HT" : @(9648924),
            @"HU" : @(9982000),
            @"ID" : @(242968342),
            @"IE" : @(4622917),
            @"IL" : @(7353985),
            @"IM" : @(75049),
            @"IN" : @(1173108018),
            @"IO" : @(4000),
            @"IQ" : @(29671605),
            @"IR" : @(76923300),
            @"IS" : @(308910),
            @"IT" : @(60340328),
            @"JE" : @(90812),
            @"JM" : @(2847232),
            @"JO" : @(6407085),
            @"JP" : @(127288000),
            @"KE" : @(40046566),
            @"KG" : @(5776500),
            @"KH" : @(14453680),
            @"KI" : @(92533),
            @"KM" : @(773407),
            @"KN" : @(51134),
            @"KP" : @(22912177),
            @"KR" : @(48422644),
            @"KW" : @(2789132),
            @"KY" : @(44270),
            @"KZ" : @(15340000),
            @"LA" : @(6368162),
            @"LB" : @(4125247),
            @"LC" : @(160922),
            @"LI" : @(35000),
            @"LK" : @(21513990),
            @"LR" : @(3685076),
            @"LS" : @(1919552),
            @"LT" : @(2944459),
            @"LU" : @(497538),
            @"LV" : @(2217969),
            @"LY" : @(6461454),
            @"MA" : @(33848242),
            @"MC" : @(32965),
            @"MD" : @(4324000),
            @"ME" : @(666730),
            @"MF" : @(35925),
            @"MG" : @(21281844),
            @"MH" : @(65859),
            @"MK" : @(2062294),
            @"ML" : @(13796354),
            @"MM" : @(53414374),
            @"MN" : @(3086918),
            @"MO" : @(449198),
            @"MP" : @(53883),
            @"MQ" : @(432900),
            @"MR" : @(3205060),
            @"MS" : @(9341),
            @"MT" : @(403000),
            @"MU" : @(1294104),
            @"MV" : @(395650),
            @"MW" : @(15447500),
            @"MX" : @(112468855),
            @"MY" : @(28274729),
            @"MZ" : @(22061451),
            @"NA" : @(2128471),
            @"NC" : @(216494),
            @"NE" : @(15878271),
            @"NF" : @(1828),
            @"NG" : @(154000000),
            @"NI" : @(5995928),
            @"NL" : @(16645000),
            @"NO" : @(5009150),
            @"NP" : @(28951852),
            @"NR" : @(10065),
            @"NU" : @(2166),
            @"NZ" : @(4252277),
            @"OM" : @(2967717),
            @"PA" : @(3410676),
            @"PE" : @(29907003),
            @"PF" : @(270485),
            @"PG" : @(6064515),
            @"PH" : @(99900177),
            @"PK" : @(184404791),
            @"PL" : @(38500000),
            @"PM" : @(7012),
            @"PN" : @(46),
            @"PR" : @(3916632),
            @"PS" : @(3800000),
            @"PT" : @(10676000),
            @"PW" : @(19907),
            @"PY" : @(6375830),
            @"QA" : @(840926),
            @"RE" : @(776948),
            @"RO" : @(21959278),
            @"RS" : @(7344847),
            @"RU" : @(140702000),
            @"RW" : @(11055976),
            @"SA" : @(25731776),
            @"SB" : @(559198),
            @"SC" : @(88340),
            @"SD" : @(35000000),
            @"SE" : @(9828655),
            @"SG" : @(4701069),
            @"SH" : @(7460),
            @"SI" : @(2007000),
            @"SJ" : @(2550),
            @"SK" : @(5455000),
            @"SL" : @(5245695),
            @"SM" : @(31477),
            @"SN" : @(12323252),
            @"SO" : @(10112453),
            @"SR" : @(492829),
            @"SS" : @(8260490),
            @"ST" : @(175808),
            @"SV" : @(6052064),
            @"SX" : @(37429),
            @"SY" : @(22198110),
            @"SZ" : @(1354051),
            @"TC" : @(20556),
            @"TD" : @(10543464),
            @"TF" : @(140),
            @"TG" : @(6587239),
            @"TH" : @(67089500),
            @"TJ" : @(7487489),
            @"TK" : @(1466),
            @"TL" : @(1154625),
            @"TM" : @(4940916),
            @"TN" : @(10589025),
            @"TO" : @(122580),
            @"TR" : @(77804122),
            @"TT" : @(1328019),
            @"TV" : @(10472),
            @"TW" : @(22894384),
            @"TZ" : @(41892895),
            @"UA" : @(45415596),
            @"UG" : @(33398682),
            @"UM" : @(0),
            @"US" : @(310232863),
            @"UY" : @(3477000),
            @"UZ" : @(27865738),
            @"VA" : @(921),
            @"VC" : @(104217),
            @"VE" : @(27223228),
            @"VG" : @(21730),
            @"VI" : @(108708),
            @"VN" : @(89571130),
            @"VU" : @(221552),
            @"WF" : @(16025),
            @"WS" : @(192001),
            @"XK" : @(1800000),
            @"YE" : @(23495361),
            @"YT" : @(159042),
            @"ZA" : @(49000000),
            @"ZM" : @(13460305),
            @"ZW" : @(13061000),
        };
    });
    return instance;
}

- (NSArray<NSString *> *)countryCodesSortedByPopulationDescending
{
    NSDictionary<NSString *, NSNumber *> *countryCodeToPopulationMap = [self countryCodeToPopulationMap];
    NSArray<NSString *> *result = [NSLocale.ISOCountryCodes
        sortedArrayUsingComparator:^NSComparisonResult(NSString *_Nonnull left, NSString *_Nonnull right) {
            int leftPopulation = [countryCodeToPopulationMap[left] intValue];
            int rightPopulation = [countryCodeToPopulationMap[right] intValue];
            // Invert the values for a descending sort.
            return [@(-leftPopulation) compare:@(-rightPopulation)];
        }];
    return result;
}

- (NSArray<NSString *> *)countryCodesFromCallingCode:(NSString *)callingCode
{
    @synchronized(self)
    {
        OWSAssertDebug(callingCode.length > 0);

        NSArray *result = self.countryCodesFromCallingCodeCache[callingCode];
        if (!result) {
            NSMutableArray *countryCodes = [NSMutableArray new];
            for (NSString *countryCode in [self countryCodesSortedByPopulationDescending]) {
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
    OWSAssertDebug(source != nil);
    OWSAssertDebug(target != nil);
    OWSAssertDebug(offset <= source.length);

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
