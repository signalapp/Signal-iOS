//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSCountryMetadata.h"
#import "OWSCensorshipConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCountryMetadata

+ (OWSCountryMetadata *)countryMetadataWithName:(NSString *)name
                                 frontingDomain:(nullable NSString *)frontingDomain
                                    countryCode:(NSString *)countryCode
{
    OWSAssertDebug(name.length > 0);
    OWSAssertDebug(countryCode.length > 0);

    OWSCountryMetadata *instance = [OWSCountryMetadata new];
    instance.name = name;
    instance.frontingDomain = frontingDomain;
    instance.countryCode = countryCode;

    NSString *localizedCountryName = [[NSLocale currentLocale] displayNameForKey:NSLocaleCountryCode value:countryCode];
    if (localizedCountryName.length < 1) {
        localizedCountryName = name;
    }
    instance.localizedCountryName = localizedCountryName;

    return instance;
}

+ (OWSCountryMetadata *)countryMetadataForCountryCode:(NSString *)countryCode
{
    OWSAssertDebug(countryCode.length > 0);

    return [self countryCodeToCountryMetadataMap][countryCode];
}

+ (NSDictionary<NSString *, OWSCountryMetadata *> *)countryCodeToCountryMetadataMap
{
    static NSDictionary<NSString *, OWSCountryMetadata *> *cachedValue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString *, OWSCountryMetadata *> *map = [NSMutableDictionary new];
        for (OWSCountryMetadata *metadata in [self allCountryMetadatas]) {
            map[metadata.countryCode] = metadata;
        }
        cachedValue = map;
    });
    return cachedValue;
}

+ (NSArray<OWSCountryMetadata *> *)allCountryMetadatas
{
    static NSArray<OWSCountryMetadata *> *cachedValue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedValue = @[
            [OWSCountryMetadata countryMetadataWithName:@"Andorra" frontingDomain:nil countryCode:@"AD"],
            [OWSCountryMetadata countryMetadataWithName:@"United Arab Emirates"
                                         frontingDomain:OWSFrontingHost_GoogleUAE
                                            countryCode:@"AE"],
            [OWSCountryMetadata countryMetadataWithName:@"Afghanistan" frontingDomain:nil countryCode:@"AF"],
            [OWSCountryMetadata countryMetadataWithName:@"Antigua and Barbuda" frontingDomain:nil countryCode:@"AG"],
            [OWSCountryMetadata countryMetadataWithName:@"Anguilla" frontingDomain:nil countryCode:@"AI"],
            [OWSCountryMetadata countryMetadataWithName:@"Albania" frontingDomain:nil countryCode:@"AL"],
            [OWSCountryMetadata countryMetadataWithName:@"Armenia" frontingDomain:nil countryCode:@"AM"],
            [OWSCountryMetadata countryMetadataWithName:@"Angola" frontingDomain:nil countryCode:@"AO"],
            [OWSCountryMetadata countryMetadataWithName:@"Argentina" frontingDomain:nil countryCode:@"AR"],
            [OWSCountryMetadata countryMetadataWithName:@"American Samoa" frontingDomain:nil countryCode:@"AS"],
            [OWSCountryMetadata countryMetadataWithName:@"Austria" frontingDomain:nil countryCode:@"AT"],
            [OWSCountryMetadata countryMetadataWithName:@"Australia" frontingDomain:nil countryCode:@"AU"],
            [OWSCountryMetadata countryMetadataWithName:@"Azerbaijan" frontingDomain:nil countryCode:@"AZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Bosnia and Herzegovina" frontingDomain:nil countryCode:@"BA"],
            [OWSCountryMetadata countryMetadataWithName:@"Bangladesh" frontingDomain:nil countryCode:@"BD"],
            [OWSCountryMetadata countryMetadataWithName:@"Belgium" frontingDomain:nil countryCode:@"BE"],
            [OWSCountryMetadata countryMetadataWithName:@"Burkina Faso" frontingDomain:nil countryCode:@"BF"],
            [OWSCountryMetadata countryMetadataWithName:@"Bulgaria" frontingDomain:nil countryCode:@"BG"],
            [OWSCountryMetadata countryMetadataWithName:@"Bahrain" frontingDomain:nil countryCode:@"BH"],
            [OWSCountryMetadata countryMetadataWithName:@"Burundi" frontingDomain:nil countryCode:@"BI"],
            [OWSCountryMetadata countryMetadataWithName:@"Benin" frontingDomain:nil countryCode:@"BJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Brunei" frontingDomain:nil countryCode:@"BN"],
            [OWSCountryMetadata countryMetadataWithName:@"Bolivia" frontingDomain:nil countryCode:@"BO"],
            [OWSCountryMetadata countryMetadataWithName:@"Brazil" frontingDomain:nil countryCode:@"BR"],
            [OWSCountryMetadata countryMetadataWithName:@"Bahamas" frontingDomain:nil countryCode:@"BS"],
            [OWSCountryMetadata countryMetadataWithName:@"Bhutan" frontingDomain:nil countryCode:@"BT"],
            [OWSCountryMetadata countryMetadataWithName:@"Botswana" frontingDomain:nil countryCode:@"BW"],
            [OWSCountryMetadata countryMetadataWithName:@"Belarus" frontingDomain:nil countryCode:@"BY"],
            [OWSCountryMetadata countryMetadataWithName:@"Belize" frontingDomain:nil countryCode:@"BZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Canada" frontingDomain:nil countryCode:@"CA"],
            [OWSCountryMetadata countryMetadataWithName:@"Cambodia" frontingDomain:nil countryCode:@"KH"],
            [OWSCountryMetadata countryMetadataWithName:@"Cocos (Keeling) Islands"
                                         frontingDomain:nil
                                            countryCode:@"CC"],
            [OWSCountryMetadata countryMetadataWithName:@"Democratic Republic of the Congo"
                                         frontingDomain:nil
                                            countryCode:@"CD"],
            [OWSCountryMetadata countryMetadataWithName:@"Central African Republic"
                                         frontingDomain:nil
                                            countryCode:@"CF"],
            [OWSCountryMetadata countryMetadataWithName:@"Republic of the Congo" frontingDomain:nil countryCode:@"CG"],
            [OWSCountryMetadata countryMetadataWithName:@"Switzerland" frontingDomain:nil countryCode:@"CH"],
            [OWSCountryMetadata countryMetadataWithName:@"Ivory Coast" frontingDomain:nil countryCode:@"CI"],
            [OWSCountryMetadata countryMetadataWithName:@"Cook Islands" frontingDomain:nil countryCode:@"CK"],
            [OWSCountryMetadata countryMetadataWithName:@"Chile" frontingDomain:nil countryCode:@"CL"],
            [OWSCountryMetadata countryMetadataWithName:@"Cameroon" frontingDomain:nil countryCode:@"CM"],
            [OWSCountryMetadata countryMetadataWithName:@"China" frontingDomain:nil countryCode:@"CN"],
            [OWSCountryMetadata countryMetadataWithName:@"Colombia" frontingDomain:nil countryCode:@"CO"],
            [OWSCountryMetadata countryMetadataWithName:@"Costa Rica" frontingDomain:nil countryCode:@"CR"],
            [OWSCountryMetadata countryMetadataWithName:@"Cuba" frontingDomain:nil countryCode:@"CU"],
            [OWSCountryMetadata countryMetadataWithName:@"Cape Verde" frontingDomain:nil countryCode:@"CV"],
            [OWSCountryMetadata countryMetadataWithName:@"Christmas Island" frontingDomain:nil countryCode:@"CX"],
            [OWSCountryMetadata countryMetadataWithName:@"Cyprus" frontingDomain:nil countryCode:@"CY"],
            [OWSCountryMetadata countryMetadataWithName:@"Czech Republic" frontingDomain:nil countryCode:@"CZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Germany" frontingDomain:nil countryCode:@"DE"],
            [OWSCountryMetadata countryMetadataWithName:@"Djibouti" frontingDomain:nil countryCode:@"DJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Denmark" frontingDomain:nil countryCode:@"DK"],
            [OWSCountryMetadata countryMetadataWithName:@"Dominica" frontingDomain:nil countryCode:@"DM"],
            [OWSCountryMetadata countryMetadataWithName:@"Dominican Republic" frontingDomain:nil countryCode:@"DO"],
            [OWSCountryMetadata countryMetadataWithName:@"Algeria" frontingDomain:nil countryCode:@"DZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ecuador" frontingDomain:nil countryCode:@"EC"],
            [OWSCountryMetadata countryMetadataWithName:@"Estonia" frontingDomain:nil countryCode:@"EE"],
            [OWSCountryMetadata countryMetadataWithName:@"Egypt"
                                         frontingDomain:OWSFrontingHost_GoogleEgypt
                                            countryCode:@"EG"],
            [OWSCountryMetadata countryMetadataWithName:@"Spain" frontingDomain:nil countryCode:@"ES"],
            [OWSCountryMetadata countryMetadataWithName:@"Ethiopia" frontingDomain:nil countryCode:@"ET"],
            [OWSCountryMetadata countryMetadataWithName:@"Finland" frontingDomain:nil countryCode:@"FI"],
            [OWSCountryMetadata countryMetadataWithName:@"Fiji" frontingDomain:nil countryCode:@"FJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Federated States of Micronesia"
                                         frontingDomain:nil
                                            countryCode:@"FM"],
            [OWSCountryMetadata countryMetadataWithName:@"France" frontingDomain:nil countryCode:@"FR"],
            [OWSCountryMetadata countryMetadataWithName:@"Gabon" frontingDomain:nil countryCode:@"GA"],
            [OWSCountryMetadata countryMetadataWithName:@"Georgia" frontingDomain:nil countryCode:@"GE"],
            [OWSCountryMetadata countryMetadataWithName:@"French Guiana" frontingDomain:nil countryCode:@"GF"],
            [OWSCountryMetadata countryMetadataWithName:@"Guernsey" frontingDomain:nil countryCode:@"GG"],
            [OWSCountryMetadata countryMetadataWithName:@"Ghana" frontingDomain:nil countryCode:@"GH"],
            [OWSCountryMetadata countryMetadataWithName:@"Gibraltar" frontingDomain:nil countryCode:@"GI"],
            [OWSCountryMetadata countryMetadataWithName:@"Greenland" frontingDomain:nil countryCode:@"GL"],
            [OWSCountryMetadata countryMetadataWithName:@"Gambia" frontingDomain:nil countryCode:@"GM"],
            [OWSCountryMetadata countryMetadataWithName:@"Guadeloupe" frontingDomain:nil countryCode:@"GP"],
            [OWSCountryMetadata countryMetadataWithName:@"Greece" frontingDomain:nil countryCode:@"GR"],
            [OWSCountryMetadata countryMetadataWithName:@"Guatemala" frontingDomain:nil countryCode:@"GT"],
            [OWSCountryMetadata countryMetadataWithName:@"Guyana" frontingDomain:nil countryCode:@"GY"],
            [OWSCountryMetadata countryMetadataWithName:@"Hong Kong" frontingDomain:nil countryCode:@"HK"],
            [OWSCountryMetadata countryMetadataWithName:@"Honduras" frontingDomain:nil countryCode:@"HN"],
            [OWSCountryMetadata countryMetadataWithName:@"Croatia" frontingDomain:nil countryCode:@"HR"],
            [OWSCountryMetadata countryMetadataWithName:@"Haiti" frontingDomain:nil countryCode:@"HT"],
            [OWSCountryMetadata countryMetadataWithName:@"Hungary" frontingDomain:nil countryCode:@"HU"],
            [OWSCountryMetadata countryMetadataWithName:@"Indonesia" frontingDomain:nil countryCode:@"ID"],
            [OWSCountryMetadata countryMetadataWithName:@"Iraq" frontingDomain:nil countryCode:@"IQ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ireland" frontingDomain:nil countryCode:@"IE"],
            [OWSCountryMetadata countryMetadataWithName:@"Israel" frontingDomain:nil countryCode:@"IL"],
            [OWSCountryMetadata countryMetadataWithName:@"Isle of Man" frontingDomain:nil countryCode:@"IM"],
            [OWSCountryMetadata countryMetadataWithName:@"India" frontingDomain:nil countryCode:@"IN"],
            [OWSCountryMetadata countryMetadataWithName:@"British Indian Ocean Territory"
                                         frontingDomain:nil
                                            countryCode:@"IO"],
            [OWSCountryMetadata countryMetadataWithName:@"Iceland" frontingDomain:nil countryCode:@"IS"],
            [OWSCountryMetadata countryMetadataWithName:@"Italy" frontingDomain:nil countryCode:@"IT"],
            [OWSCountryMetadata countryMetadataWithName:@"Jersey" frontingDomain:nil countryCode:@"JE"],
            [OWSCountryMetadata countryMetadataWithName:@"Jamaica" frontingDomain:nil countryCode:@"JM"],
            [OWSCountryMetadata countryMetadataWithName:@"Jordan" frontingDomain:nil countryCode:@"JO"],
            [OWSCountryMetadata countryMetadataWithName:@"Japan" frontingDomain:nil countryCode:@"JP"],
            [OWSCountryMetadata countryMetadataWithName:@"Kenya" frontingDomain:nil countryCode:@"KE"],
            [OWSCountryMetadata countryMetadataWithName:@"Kiribati" frontingDomain:nil countryCode:@"KI"],
            [OWSCountryMetadata countryMetadataWithName:@"Kyrgyzstan" frontingDomain:nil countryCode:@"KG"],
            [OWSCountryMetadata countryMetadataWithName:@"South Korea" frontingDomain:nil countryCode:@"KR"],
            [OWSCountryMetadata countryMetadataWithName:@"Kuwait" frontingDomain:nil countryCode:@"KW"],
            [OWSCountryMetadata countryMetadataWithName:@"Kazakhstan" frontingDomain:nil countryCode:@"KZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Laos" frontingDomain:nil countryCode:@"LA"],
            [OWSCountryMetadata countryMetadataWithName:@"Lebanon" frontingDomain:nil countryCode:@"LB"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Lucia" frontingDomain:nil countryCode:@"LC"],
            [OWSCountryMetadata countryMetadataWithName:@"Liechtenstein" frontingDomain:nil countryCode:@"LI"],
            [OWSCountryMetadata countryMetadataWithName:@"Sri Lanka" frontingDomain:nil countryCode:@"LK"],
            [OWSCountryMetadata countryMetadataWithName:@"Lesotho" frontingDomain:nil countryCode:@"LS"],
            [OWSCountryMetadata countryMetadataWithName:@"Lithuania" frontingDomain:nil countryCode:@"LT"],
            [OWSCountryMetadata countryMetadataWithName:@"Luxembourg" frontingDomain:nil countryCode:@"LU"],
            [OWSCountryMetadata countryMetadataWithName:@"Latvia" frontingDomain:nil countryCode:@"LV"],
            [OWSCountryMetadata countryMetadataWithName:@"Libya" frontingDomain:nil countryCode:@"LY"],
            [OWSCountryMetadata countryMetadataWithName:@"Morocco" frontingDomain:nil countryCode:@"MA"],
            [OWSCountryMetadata countryMetadataWithName:@"Moldova" frontingDomain:nil countryCode:@"MD"],
            [OWSCountryMetadata countryMetadataWithName:@"Montenegro" frontingDomain:nil countryCode:@"ME"],
            [OWSCountryMetadata countryMetadataWithName:@"Madagascar" frontingDomain:nil countryCode:@"MG"],
            [OWSCountryMetadata countryMetadataWithName:@"Macedonia" frontingDomain:nil countryCode:@"MK"],
            [OWSCountryMetadata countryMetadataWithName:@"Mali" frontingDomain:nil countryCode:@"ML"],
            [OWSCountryMetadata countryMetadataWithName:@"Myanmar" frontingDomain:nil countryCode:@"MM"],
            [OWSCountryMetadata countryMetadataWithName:@"Mongolia" frontingDomain:nil countryCode:@"MN"],
            [OWSCountryMetadata countryMetadataWithName:@"Montserrat" frontingDomain:nil countryCode:@"MS"],
            [OWSCountryMetadata countryMetadataWithName:@"Malta" frontingDomain:nil countryCode:@"MT"],
            [OWSCountryMetadata countryMetadataWithName:@"Mauritius" frontingDomain:nil countryCode:@"MU"],
            [OWSCountryMetadata countryMetadataWithName:@"Maldives" frontingDomain:nil countryCode:@"MV"],
            [OWSCountryMetadata countryMetadataWithName:@"Malawi" frontingDomain:nil countryCode:@"MW"],
            [OWSCountryMetadata countryMetadataWithName:@"Mexico" frontingDomain:nil countryCode:@"MX"],
            [OWSCountryMetadata countryMetadataWithName:@"Malaysia" frontingDomain:nil countryCode:@"MY"],
            [OWSCountryMetadata countryMetadataWithName:@"Mozambique" frontingDomain:nil countryCode:@"MZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Namibia" frontingDomain:nil countryCode:@"NA"],
            [OWSCountryMetadata countryMetadataWithName:@"Niger" frontingDomain:nil countryCode:@"NE"],
            [OWSCountryMetadata countryMetadataWithName:@"Norfolk Island" frontingDomain:nil countryCode:@"NF"],
            [OWSCountryMetadata countryMetadataWithName:@"Nigeria" frontingDomain:nil countryCode:@"NG"],
            [OWSCountryMetadata countryMetadataWithName:@"Nicaragua" frontingDomain:nil countryCode:@"NI"],
            [OWSCountryMetadata countryMetadataWithName:@"Netherlands" frontingDomain:nil countryCode:@"NL"],
            [OWSCountryMetadata countryMetadataWithName:@"Norway" frontingDomain:nil countryCode:@"NO"],
            [OWSCountryMetadata countryMetadataWithName:@"Nepal" frontingDomain:nil countryCode:@"NP"],
            [OWSCountryMetadata countryMetadataWithName:@"Nauru" frontingDomain:nil countryCode:@"NR"],
            [OWSCountryMetadata countryMetadataWithName:@"Niue" frontingDomain:nil countryCode:@"NU"],
            [OWSCountryMetadata countryMetadataWithName:@"New Zealand" frontingDomain:nil countryCode:@"NZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Oman"
                                         frontingDomain:OWSFrontingHost_GoogleOman
                                            countryCode:@"OM"],
            [OWSCountryMetadata countryMetadataWithName:@"Pakistan" frontingDomain:nil countryCode:@"PK"],
            [OWSCountryMetadata countryMetadataWithName:@"Panama" frontingDomain:nil countryCode:@"PA"],
            [OWSCountryMetadata countryMetadataWithName:@"Peru" frontingDomain:nil countryCode:@"PE"],
            [OWSCountryMetadata countryMetadataWithName:@"Philippines" frontingDomain:nil countryCode:@"PH"],
            [OWSCountryMetadata countryMetadataWithName:@"Poland" frontingDomain:nil countryCode:@"PL"],
            [OWSCountryMetadata countryMetadataWithName:@"Papua New Guinea" frontingDomain:nil countryCode:@"PG"],
            [OWSCountryMetadata countryMetadataWithName:@"Pitcairn Islands" frontingDomain:nil countryCode:@"PN"],
            [OWSCountryMetadata countryMetadataWithName:@"Puerto Rico" frontingDomain:nil countryCode:@"PR"],
            [OWSCountryMetadata countryMetadataWithName:@"Palestine[4]" frontingDomain:nil countryCode:@"PS"],
            [OWSCountryMetadata countryMetadataWithName:@"Portugal" frontingDomain:nil countryCode:@"PT"],
            [OWSCountryMetadata countryMetadataWithName:@"Paraguay" frontingDomain:nil countryCode:@"PY"],
            [OWSCountryMetadata countryMetadataWithName:@"Qatar"
                                         frontingDomain:OWSFrontingHost_GoogleQatar
                                            countryCode:@"QA"],
            [OWSCountryMetadata countryMetadataWithName:@"Romania" frontingDomain:nil countryCode:@"RO"],
            [OWSCountryMetadata countryMetadataWithName:@"Serbia" frontingDomain:nil countryCode:@"RS"],
            [OWSCountryMetadata countryMetadataWithName:@"Russia" frontingDomain:nil countryCode:@"RU"],
            [OWSCountryMetadata countryMetadataWithName:@"Rwanda" frontingDomain:nil countryCode:@"RW"],
            [OWSCountryMetadata countryMetadataWithName:@"Saudi Arabia" frontingDomain:nil countryCode:@"SA"],
            [OWSCountryMetadata countryMetadataWithName:@"Solomon Islands" frontingDomain:nil countryCode:@"SB"],
            [OWSCountryMetadata countryMetadataWithName:@"Seychelles" frontingDomain:nil countryCode:@"SC"],
            [OWSCountryMetadata countryMetadataWithName:@"Sweden" frontingDomain:nil countryCode:@"SE"],
            [OWSCountryMetadata countryMetadataWithName:@"Singapore" frontingDomain:nil countryCode:@"SG"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Helena, Ascension and Tristan da Cunha"
                                         frontingDomain:nil
                                            countryCode:@"SH"],
            [OWSCountryMetadata countryMetadataWithName:@"Slovenia" frontingDomain:nil countryCode:@"SI"],
            [OWSCountryMetadata countryMetadataWithName:@"Slovakia" frontingDomain:nil countryCode:@"SK"],
            [OWSCountryMetadata countryMetadataWithName:@"Sierra Leone" frontingDomain:nil countryCode:@"SL"],
            [OWSCountryMetadata countryMetadataWithName:@"Senegal" frontingDomain:nil countryCode:@"SN"],
            [OWSCountryMetadata countryMetadataWithName:@"San Marino" frontingDomain:nil countryCode:@"SM"],
            [OWSCountryMetadata countryMetadataWithName:@"Somalia" frontingDomain:nil countryCode:@"SO"],
            [OWSCountryMetadata countryMetadataWithName:@"São Tomé and Príncipe" frontingDomain:nil countryCode:@"ST"],
            [OWSCountryMetadata countryMetadataWithName:@"Suriname" frontingDomain:nil countryCode:@"SR"],
            [OWSCountryMetadata countryMetadataWithName:@"El Salvador" frontingDomain:nil countryCode:@"SV"],
            [OWSCountryMetadata countryMetadataWithName:@"Chad" frontingDomain:nil countryCode:@"TD"],
            [OWSCountryMetadata countryMetadataWithName:@"Togo" frontingDomain:nil countryCode:@"TG"],
            [OWSCountryMetadata countryMetadataWithName:@"Thailand" frontingDomain:nil countryCode:@"TH"],
            [OWSCountryMetadata countryMetadataWithName:@"Tajikistan" frontingDomain:nil countryCode:@"TJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Tokelau" frontingDomain:nil countryCode:@"TK"],
            [OWSCountryMetadata countryMetadataWithName:@"Timor-Leste" frontingDomain:nil countryCode:@"TL"],
            [OWSCountryMetadata countryMetadataWithName:@"Turkmenistan" frontingDomain:nil countryCode:@"TM"],
            [OWSCountryMetadata countryMetadataWithName:@"Tonga" frontingDomain:nil countryCode:@"TO"],
            [OWSCountryMetadata countryMetadataWithName:@"Tunisia" frontingDomain:nil countryCode:@"TN"],
            [OWSCountryMetadata countryMetadataWithName:@"Turkey" frontingDomain:nil countryCode:@"TR"],
            [OWSCountryMetadata countryMetadataWithName:@"Trinidad and Tobago" frontingDomain:nil countryCode:@"TT"],
            [OWSCountryMetadata countryMetadataWithName:@"Taiwan" frontingDomain:nil countryCode:@"TW"],
            [OWSCountryMetadata countryMetadataWithName:@"Tanzania" frontingDomain:nil countryCode:@"TZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ukraine" frontingDomain:nil countryCode:@"UA"],
            [OWSCountryMetadata countryMetadataWithName:@"Uganda" frontingDomain:nil countryCode:@"UG"],
            [OWSCountryMetadata countryMetadataWithName:@"United States" frontingDomain:nil countryCode:@"US"],
            [OWSCountryMetadata countryMetadataWithName:@"Uruguay" frontingDomain:nil countryCode:@"UY"],
            [OWSCountryMetadata countryMetadataWithName:@"Uzbekistan"
                                         frontingDomain:OWSFrontingHost_GoogleUzbekistan
                                            countryCode:@"UZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Vincent and the Grenadines"
                                         frontingDomain:nil
                                            countryCode:@"VC"],
            [OWSCountryMetadata countryMetadataWithName:@"Venezuela" frontingDomain:nil countryCode:@"VE"],
            [OWSCountryMetadata countryMetadataWithName:@"British Virgin Islands" frontingDomain:nil countryCode:@"VG"],
            [OWSCountryMetadata countryMetadataWithName:@"United States Virgin Islands"
                                         frontingDomain:nil
                                            countryCode:@"VI"],
            [OWSCountryMetadata countryMetadataWithName:@"Vietnam" frontingDomain:nil countryCode:@"VN"],
            [OWSCountryMetadata countryMetadataWithName:@"Vanuatu" frontingDomain:nil countryCode:@"VU"],
            [OWSCountryMetadata countryMetadataWithName:@"Samoa" frontingDomain:nil countryCode:@"WS"],
            [OWSCountryMetadata countryMetadataWithName:@"South Africa" frontingDomain:nil countryCode:@"ZA"],
            [OWSCountryMetadata countryMetadataWithName:@"Zambia" frontingDomain:nil countryCode:@"ZM"],
            [OWSCountryMetadata countryMetadataWithName:@"Zimbabwe" frontingDomain:nil countryCode:@"ZW"],
        ];
        cachedValue = [cachedValue sortedArrayUsingComparator:^NSComparisonResult(
            OWSCountryMetadata *_Nonnull left, OWSCountryMetadata *_Nonnull right) {
            return [left.localizedCountryName compare:right.localizedCountryName];
        }];
    });
    return cachedValue;
}

@end

NS_ASSUME_NONNULL_END
