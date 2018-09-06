//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCountryMetadata.h"
#import "OWSCensorshipConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCountryMetadata

+ (OWSCountryMetadata *)countryMetadataWithName:(NSString *)name
                                            tld:(NSString *)tld
                                 frontingDomain:(nullable NSString *)frontingDomain
                                    countryCode:(NSString *)countryCode
{
    OWSAssertDebug(name.length > 0);
    OWSAssertDebug(tld.length > 0);
    OWSAssertDebug(countryCode.length > 0);

    OWSCountryMetadata *instance = [OWSCountryMetadata new];
    instance.name = name;
    instance.tld = tld;
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
            [OWSCountryMetadata countryMetadataWithName:@"Andorra" tld:@".ad" frontingDomain:nil countryCode:@"AD"],
            [OWSCountryMetadata countryMetadataWithName:@"United Arab Emirates"
                                                    tld:@".ae"
                                         frontingDomain:OWSCensorshipConfiguration_SouqFrontingHost
                                            countryCode:@"AE"],
            [OWSCountryMetadata countryMetadataWithName:@"Afghanistan" tld:@".af" frontingDomain:nil countryCode:@"AF"],
            [OWSCountryMetadata countryMetadataWithName:@"Antigua and Barbuda"
                                                    tld:@".ag"
                                         frontingDomain:nil
                                            countryCode:@"AG"],
            [OWSCountryMetadata countryMetadataWithName:@"Anguilla" tld:@".ai" frontingDomain:nil countryCode:@"AI"],
            [OWSCountryMetadata countryMetadataWithName:@"Albania" tld:@".al" frontingDomain:nil countryCode:@"AL"],
            [OWSCountryMetadata countryMetadataWithName:@"Armenia" tld:@".am" frontingDomain:nil countryCode:@"AM"],
            [OWSCountryMetadata countryMetadataWithName:@"Angola" tld:@".ao" frontingDomain:nil countryCode:@"AO"],
            [OWSCountryMetadata countryMetadataWithName:@"Argentina" tld:@".ar" frontingDomain:nil countryCode:@"AR"],
            [OWSCountryMetadata countryMetadataWithName:@"American Samoa"
                                                    tld:@".as"
                                         frontingDomain:nil
                                            countryCode:@"AS"],
            [OWSCountryMetadata countryMetadataWithName:@"Austria" tld:@".at" frontingDomain:nil countryCode:@"AT"],
            [OWSCountryMetadata countryMetadataWithName:@"Australia" tld:@".au" frontingDomain:nil countryCode:@"AU"],
            [OWSCountryMetadata countryMetadataWithName:@"Azerbaijan" tld:@".az" frontingDomain:nil countryCode:@"AZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Bosnia and Herzegovina"
                                                    tld:@".ba"
                                         frontingDomain:nil
                                            countryCode:@"BA"],
            [OWSCountryMetadata countryMetadataWithName:@"Bangladesh" tld:@".bd" frontingDomain:nil countryCode:@"BD"],
            [OWSCountryMetadata countryMetadataWithName:@"Belgium" tld:@".be" frontingDomain:nil countryCode:@"BE"],
            [OWSCountryMetadata countryMetadataWithName:@"Burkina Faso"
                                                    tld:@".bf"
                                         frontingDomain:nil
                                            countryCode:@"BF"],
            [OWSCountryMetadata countryMetadataWithName:@"Bulgaria" tld:@".bg" frontingDomain:nil countryCode:@"BG"],
            [OWSCountryMetadata countryMetadataWithName:@"Bahrain" tld:@".bh" frontingDomain:nil countryCode:@"BH"],
            [OWSCountryMetadata countryMetadataWithName:@"Burundi" tld:@".bi" frontingDomain:nil countryCode:@"BI"],
            [OWSCountryMetadata countryMetadataWithName:@"Benin" tld:@".bj" frontingDomain:nil countryCode:@"BJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Brunei" tld:@".bn" frontingDomain:nil countryCode:@"BN"],
            [OWSCountryMetadata countryMetadataWithName:@"Bolivia" tld:@".bo" frontingDomain:nil countryCode:@"BO"],
            [OWSCountryMetadata countryMetadataWithName:@"Brazil" tld:@".br" frontingDomain:nil countryCode:@"BR"],
            [OWSCountryMetadata countryMetadataWithName:@"Bahamas" tld:@".bs" frontingDomain:nil countryCode:@"BS"],
            [OWSCountryMetadata countryMetadataWithName:@"Bhutan" tld:@".bt" frontingDomain:nil countryCode:@"BT"],
            [OWSCountryMetadata countryMetadataWithName:@"Botswana" tld:@".bw" frontingDomain:nil countryCode:@"BW"],
            [OWSCountryMetadata countryMetadataWithName:@"Belarus" tld:@".by" frontingDomain:nil countryCode:@"BY"],
            [OWSCountryMetadata countryMetadataWithName:@"Belize" tld:@".bz" frontingDomain:nil countryCode:@"BZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Canada" tld:@".ca" frontingDomain:nil countryCode:@"CA"],
            [OWSCountryMetadata countryMetadataWithName:@"Cambodia" tld:@".kh" frontingDomain:nil countryCode:@"KH"],
            [OWSCountryMetadata countryMetadataWithName:@"Cocos (Keeling) Islands"
                                                    tld:@".cc"
                                         frontingDomain:nil
                                            countryCode:@"CC"],
            [OWSCountryMetadata countryMetadataWithName:@"Democratic Republic of the Congo"
                                                    tld:@".cd"
                                         frontingDomain:nil
                                            countryCode:@"CD"],
            [OWSCountryMetadata countryMetadataWithName:@"Central African Republic"
                                                    tld:@".cf"
                                         frontingDomain:nil
                                            countryCode:@"CF"],
            [OWSCountryMetadata countryMetadataWithName:@"Republic of the Congo"
                                                    tld:@".cg"
                                         frontingDomain:nil
                                            countryCode:@"CG"],
            [OWSCountryMetadata countryMetadataWithName:@"Switzerland" tld:@".ch" frontingDomain:nil countryCode:@"CH"],
            [OWSCountryMetadata countryMetadataWithName:@"Ivory Coast" tld:@".ci" frontingDomain:nil countryCode:@"CI"],
            [OWSCountryMetadata countryMetadataWithName:@"Cook Islands"
                                                    tld:@".ck"
                                         frontingDomain:nil
                                            countryCode:@"CK"],
            [OWSCountryMetadata countryMetadataWithName:@"Chile" tld:@".cl" frontingDomain:nil countryCode:@"CL"],
            [OWSCountryMetadata countryMetadataWithName:@"Cameroon" tld:@".cm" frontingDomain:nil countryCode:@"CM"],
            [OWSCountryMetadata countryMetadataWithName:@"China" tld:@".cn" frontingDomain:nil countryCode:@"CN"],
            [OWSCountryMetadata countryMetadataWithName:@"Colombia" tld:@".co" frontingDomain:nil countryCode:@"CO"],
            [OWSCountryMetadata countryMetadataWithName:@"Costa Rica" tld:@".cr" frontingDomain:nil countryCode:@"CR"],
            [OWSCountryMetadata countryMetadataWithName:@"Cuba" tld:@".cu" frontingDomain:nil countryCode:@"CU"],
            [OWSCountryMetadata countryMetadataWithName:@"Cape Verde" tld:@".cv" frontingDomain:nil countryCode:@"CV"],
            [OWSCountryMetadata countryMetadataWithName:@"Christmas Island"
                                                    tld:@".cx"
                                         frontingDomain:nil
                                            countryCode:@"CX"],
            [OWSCountryMetadata countryMetadataWithName:@"Cyprus" tld:@".cy" frontingDomain:nil countryCode:@"CY"],
            [OWSCountryMetadata countryMetadataWithName:@"Czech Republic"
                                                    tld:@".cz"
                                         frontingDomain:nil
                                            countryCode:@"CZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Germany" tld:@".de" frontingDomain:nil countryCode:@"DE"],
            [OWSCountryMetadata countryMetadataWithName:@"Djibouti" tld:@".dj" frontingDomain:nil countryCode:@"DJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Denmark" tld:@".dk" frontingDomain:nil countryCode:@"DK"],
            [OWSCountryMetadata countryMetadataWithName:@"Dominica" tld:@".dm" frontingDomain:nil countryCode:@"DM"],
            [OWSCountryMetadata countryMetadataWithName:@"Dominican Republic"
                                                    tld:@".do"
                                         frontingDomain:nil
                                            countryCode:@"DO"],
            [OWSCountryMetadata countryMetadataWithName:@"Algeria" tld:@".dz" frontingDomain:nil countryCode:@"DZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ecuador" tld:@".ec" frontingDomain:nil countryCode:@"EC"],
            [OWSCountryMetadata countryMetadataWithName:@"Estonia" tld:@".ee" frontingDomain:nil countryCode:@"EE"],
            [OWSCountryMetadata countryMetadataWithName:@"Egypt"
                                                    tld:@".eg"
                                         frontingDomain:OWSCensorshipConfiguration_SouqFrontingHost
                                            countryCode:@"EG"],
            [OWSCountryMetadata countryMetadataWithName:@"Spain" tld:@".es" frontingDomain:nil countryCode:@"ES"],
            [OWSCountryMetadata countryMetadataWithName:@"Ethiopia" tld:@".et" frontingDomain:nil countryCode:@"ET"],
            [OWSCountryMetadata countryMetadataWithName:@"Finland" tld:@".fi" frontingDomain:nil countryCode:@"FI"],
            [OWSCountryMetadata countryMetadataWithName:@"Fiji" tld:@".fj" frontingDomain:nil countryCode:@"FJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Federated States of Micronesia"
                                                    tld:@".fm"
                                         frontingDomain:nil
                                            countryCode:@"FM"],
            [OWSCountryMetadata countryMetadataWithName:@"France" tld:@".fr" frontingDomain:nil countryCode:@"FR"],
            [OWSCountryMetadata countryMetadataWithName:@"Gabon" tld:@".ga" frontingDomain:nil countryCode:@"GA"],
            [OWSCountryMetadata countryMetadataWithName:@"Georgia" tld:@".ge" frontingDomain:nil countryCode:@"GE"],
            [OWSCountryMetadata countryMetadataWithName:@"French Guiana"
                                                    tld:@".gf"
                                         frontingDomain:nil
                                            countryCode:@"GF"],
            [OWSCountryMetadata countryMetadataWithName:@"Guernsey" tld:@".gg" frontingDomain:nil countryCode:@"GG"],
            [OWSCountryMetadata countryMetadataWithName:@"Ghana" tld:@".gh" frontingDomain:nil countryCode:@"GH"],
            [OWSCountryMetadata countryMetadataWithName:@"Gibraltar" tld:@".gi" frontingDomain:nil countryCode:@"GI"],
            [OWSCountryMetadata countryMetadataWithName:@"Greenland" tld:@".gl" frontingDomain:nil countryCode:@"GL"],
            [OWSCountryMetadata countryMetadataWithName:@"Gambia" tld:@".gm" frontingDomain:nil countryCode:@"GM"],
            [OWSCountryMetadata countryMetadataWithName:@"Guadeloupe" tld:@".gp" frontingDomain:nil countryCode:@"GP"],
            [OWSCountryMetadata countryMetadataWithName:@"Greece" tld:@".gr" frontingDomain:nil countryCode:@"GR"],
            [OWSCountryMetadata countryMetadataWithName:@"Guatemala" tld:@".gt" frontingDomain:nil countryCode:@"GT"],
            [OWSCountryMetadata countryMetadataWithName:@"Guyana" tld:@".gy" frontingDomain:nil countryCode:@"GY"],
            [OWSCountryMetadata countryMetadataWithName:@"Hong Kong" tld:@".hk" frontingDomain:nil countryCode:@"HK"],
            [OWSCountryMetadata countryMetadataWithName:@"Honduras" tld:@".hn" frontingDomain:nil countryCode:@"HN"],
            [OWSCountryMetadata countryMetadataWithName:@"Croatia" tld:@".hr" frontingDomain:nil countryCode:@"HR"],
            [OWSCountryMetadata countryMetadataWithName:@"Haiti" tld:@".ht" frontingDomain:nil countryCode:@"HT"],
            [OWSCountryMetadata countryMetadataWithName:@"Hungary" tld:@".hu" frontingDomain:nil countryCode:@"HU"],
            [OWSCountryMetadata countryMetadataWithName:@"Indonesia" tld:@".id" frontingDomain:nil countryCode:@"ID"],
            [OWSCountryMetadata countryMetadataWithName:@"Iraq" tld:@".iq" frontingDomain:nil countryCode:@"IQ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ireland" tld:@".ie" frontingDomain:nil countryCode:@"IE"],
            [OWSCountryMetadata countryMetadataWithName:@"Israel" tld:@".il" frontingDomain:nil countryCode:@"IL"],
            [OWSCountryMetadata countryMetadataWithName:@"Isle of Man" tld:@".im" frontingDomain:nil countryCode:@"IM"],
            [OWSCountryMetadata countryMetadataWithName:@"India" tld:@".in" frontingDomain:nil countryCode:@"IN"],
            [OWSCountryMetadata countryMetadataWithName:@"British Indian Ocean Territory"
                                                    tld:@".io"
                                         frontingDomain:nil
                                            countryCode:@"IO"],
            [OWSCountryMetadata countryMetadataWithName:@"Iceland" tld:@".is" frontingDomain:nil countryCode:@"IS"],
            [OWSCountryMetadata countryMetadataWithName:@"Italy" tld:@".it" frontingDomain:nil countryCode:@"IT"],
            [OWSCountryMetadata countryMetadataWithName:@"Jersey" tld:@".je" frontingDomain:nil countryCode:@"JE"],
            [OWSCountryMetadata countryMetadataWithName:@"Jamaica" tld:@".jm" frontingDomain:nil countryCode:@"JM"],
            [OWSCountryMetadata countryMetadataWithName:@"Jordan" tld:@".jo" frontingDomain:nil countryCode:@"JO"],
            [OWSCountryMetadata countryMetadataWithName:@"Japan" tld:@".jp" frontingDomain:nil countryCode:@"JP"],
            [OWSCountryMetadata countryMetadataWithName:@"Kenya" tld:@".ke" frontingDomain:nil countryCode:@"KE"],
            [OWSCountryMetadata countryMetadataWithName:@"Kiribati" tld:@".ki" frontingDomain:nil countryCode:@"KI"],
            [OWSCountryMetadata countryMetadataWithName:@"Kyrgyzstan" tld:@".kg" frontingDomain:nil countryCode:@"KG"],
            [OWSCountryMetadata countryMetadataWithName:@"South Korea" tld:@".kr" frontingDomain:nil countryCode:@"KR"],
            [OWSCountryMetadata countryMetadataWithName:@"Kuwait" tld:@".kw" frontingDomain:nil countryCode:@"KW"],
            [OWSCountryMetadata countryMetadataWithName:@"Kazakhstan" tld:@".kz" frontingDomain:nil countryCode:@"KZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Laos" tld:@".la" frontingDomain:nil countryCode:@"LA"],
            [OWSCountryMetadata countryMetadataWithName:@"Lebanon" tld:@".lb" frontingDomain:nil countryCode:@"LB"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Lucia" tld:@".lc" frontingDomain:nil countryCode:@"LC"],
            [OWSCountryMetadata countryMetadataWithName:@"Liechtenstein"
                                                    tld:@".li"
                                         frontingDomain:nil
                                            countryCode:@"LI"],
            [OWSCountryMetadata countryMetadataWithName:@"Sri Lanka" tld:@".lk" frontingDomain:nil countryCode:@"LK"],
            [OWSCountryMetadata countryMetadataWithName:@"Lesotho" tld:@".ls" frontingDomain:nil countryCode:@"LS"],
            [OWSCountryMetadata countryMetadataWithName:@"Lithuania" tld:@".lt" frontingDomain:nil countryCode:@"LT"],
            [OWSCountryMetadata countryMetadataWithName:@"Luxembourg" tld:@".lu" frontingDomain:nil countryCode:@"LU"],
            [OWSCountryMetadata countryMetadataWithName:@"Latvia" tld:@".lv" frontingDomain:nil countryCode:@"LV"],
            [OWSCountryMetadata countryMetadataWithName:@"Libya" tld:@".ly" frontingDomain:nil countryCode:@"LY"],
            [OWSCountryMetadata countryMetadataWithName:@"Morocco" tld:@".ma" frontingDomain:nil countryCode:@"MA"],
            [OWSCountryMetadata countryMetadataWithName:@"Moldova" tld:@".md" frontingDomain:nil countryCode:@"MD"],
            [OWSCountryMetadata countryMetadataWithName:@"Montenegro" tld:@".me" frontingDomain:nil countryCode:@"ME"],
            [OWSCountryMetadata countryMetadataWithName:@"Madagascar" tld:@".mg" frontingDomain:nil countryCode:@"MG"],
            [OWSCountryMetadata countryMetadataWithName:@"Macedonia" tld:@".mk" frontingDomain:nil countryCode:@"MK"],
            [OWSCountryMetadata countryMetadataWithName:@"Mali" tld:@".ml" frontingDomain:nil countryCode:@"ML"],
            [OWSCountryMetadata countryMetadataWithName:@"Myanmar" tld:@".mm" frontingDomain:nil countryCode:@"MM"],
            [OWSCountryMetadata countryMetadataWithName:@"Mongolia" tld:@".mn" frontingDomain:nil countryCode:@"MN"],
            [OWSCountryMetadata countryMetadataWithName:@"Montserrat" tld:@".ms" frontingDomain:nil countryCode:@"MS"],
            [OWSCountryMetadata countryMetadataWithName:@"Malta" tld:@".mt" frontingDomain:nil countryCode:@"MT"],
            [OWSCountryMetadata countryMetadataWithName:@"Mauritius" tld:@".mu" frontingDomain:nil countryCode:@"MU"],
            [OWSCountryMetadata countryMetadataWithName:@"Maldives" tld:@".mv" frontingDomain:nil countryCode:@"MV"],
            [OWSCountryMetadata countryMetadataWithName:@"Malawi" tld:@".mw" frontingDomain:nil countryCode:@"MW"],
            [OWSCountryMetadata countryMetadataWithName:@"Mexico" tld:@".mx" frontingDomain:nil countryCode:@"MX"],
            [OWSCountryMetadata countryMetadataWithName:@"Malaysia" tld:@".my" frontingDomain:nil countryCode:@"MY"],
            [OWSCountryMetadata countryMetadataWithName:@"Mozambique" tld:@".mz" frontingDomain:nil countryCode:@"MZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Namibia" tld:@".na" frontingDomain:nil countryCode:@"NA"],
            [OWSCountryMetadata countryMetadataWithName:@"Niger" tld:@".ne" frontingDomain:nil countryCode:@"NE"],
            [OWSCountryMetadata countryMetadataWithName:@"Norfolk Island"
                                                    tld:@".nf"
                                         frontingDomain:nil
                                            countryCode:@"NF"],
            [OWSCountryMetadata countryMetadataWithName:@"Nigeria" tld:@".ng" frontingDomain:nil countryCode:@"NG"],
            [OWSCountryMetadata countryMetadataWithName:@"Nicaragua" tld:@".ni" frontingDomain:nil countryCode:@"NI"],
            [OWSCountryMetadata countryMetadataWithName:@"Netherlands" tld:@".nl" frontingDomain:nil countryCode:@"NL"],
            [OWSCountryMetadata countryMetadataWithName:@"Norway" tld:@".no" frontingDomain:nil countryCode:@"NO"],
            [OWSCountryMetadata countryMetadataWithName:@"Nepal" tld:@".np" frontingDomain:nil countryCode:@"NP"],
            [OWSCountryMetadata countryMetadataWithName:@"Nauru" tld:@".nr" frontingDomain:nil countryCode:@"NR"],
            [OWSCountryMetadata countryMetadataWithName:@"Niue" tld:@".nu" frontingDomain:nil countryCode:@"NU"],
            [OWSCountryMetadata countryMetadataWithName:@"New Zealand" tld:@".nz" frontingDomain:nil countryCode:@"NZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Oman"
                                                    tld:@".om"
                                         frontingDomain:OWSCensorshipConfiguration_SouqFrontingHost
                                            countryCode:@"OM"],
            [OWSCountryMetadata countryMetadataWithName:@"Pakistan" tld:@".pk" frontingDomain:nil countryCode:@"PK"],
            [OWSCountryMetadata countryMetadataWithName:@"Panama" tld:@".pa" frontingDomain:nil countryCode:@"PA"],
            [OWSCountryMetadata countryMetadataWithName:@"Peru" tld:@".pe" frontingDomain:nil countryCode:@"PE"],
            [OWSCountryMetadata countryMetadataWithName:@"Philippines" tld:@".ph" frontingDomain:nil countryCode:@"PH"],
            [OWSCountryMetadata countryMetadataWithName:@"Poland" tld:@".pl" frontingDomain:nil countryCode:@"PL"],
            [OWSCountryMetadata countryMetadataWithName:@"Papua New Guinea"
                                                    tld:@".pg"
                                         frontingDomain:nil
                                            countryCode:@"PG"],
            [OWSCountryMetadata countryMetadataWithName:@"Pitcairn Islands"
                                                    tld:@".pn"
                                         frontingDomain:nil
                                            countryCode:@"PN"],
            [OWSCountryMetadata countryMetadataWithName:@"Puerto Rico" tld:@".pr" frontingDomain:nil countryCode:@"PR"],
            [OWSCountryMetadata countryMetadataWithName:@"Palestine[4]"
                                                    tld:@".ps"
                                         frontingDomain:nil
                                            countryCode:@"PS"],
            [OWSCountryMetadata countryMetadataWithName:@"Portugal" tld:@".pt" frontingDomain:nil countryCode:@"PT"],
            [OWSCountryMetadata countryMetadataWithName:@"Paraguay" tld:@".py" frontingDomain:nil countryCode:@"PY"],
            [OWSCountryMetadata countryMetadataWithName:@"Qatar"
                                                    tld:@".qa"
                                         frontingDomain:OWSCensorshipConfiguration_SouqFrontingHost
                                            countryCode:@"QA"],
            [OWSCountryMetadata countryMetadataWithName:@"Romania" tld:@".ro" frontingDomain:nil countryCode:@"RO"],
            [OWSCountryMetadata countryMetadataWithName:@"Serbia" tld:@".rs" frontingDomain:nil countryCode:@"RS"],
            [OWSCountryMetadata countryMetadataWithName:@"Russia" tld:@".ru" frontingDomain:nil countryCode:@"RU"],
            [OWSCountryMetadata countryMetadataWithName:@"Rwanda" tld:@".rw" frontingDomain:nil countryCode:@"RW"],
            [OWSCountryMetadata countryMetadataWithName:@"Saudi Arabia"
                                                    tld:@".sa"
                                         frontingDomain:nil
                                            countryCode:@"SA"],
            [OWSCountryMetadata countryMetadataWithName:@"Solomon Islands"
                                                    tld:@".sb"
                                         frontingDomain:nil
                                            countryCode:@"SB"],
            [OWSCountryMetadata countryMetadataWithName:@"Seychelles" tld:@".sc" frontingDomain:nil countryCode:@"SC"],
            [OWSCountryMetadata countryMetadataWithName:@"Sweden" tld:@".se" frontingDomain:nil countryCode:@"SE"],
            [OWSCountryMetadata countryMetadataWithName:@"Singapore" tld:@".sg" frontingDomain:nil countryCode:@"SG"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Helena, Ascension and Tristan da Cunha"
                                                    tld:@".sh"
                                         frontingDomain:nil
                                            countryCode:@"SH"],
            [OWSCountryMetadata countryMetadataWithName:@"Slovenia" tld:@".si" frontingDomain:nil countryCode:@"SI"],
            [OWSCountryMetadata countryMetadataWithName:@"Slovakia" tld:@".sk" frontingDomain:nil countryCode:@"SK"],
            [OWSCountryMetadata countryMetadataWithName:@"Sierra Leone"
                                                    tld:@".sl"
                                         frontingDomain:nil
                                            countryCode:@"SL"],
            [OWSCountryMetadata countryMetadataWithName:@"Senegal" tld:@".sn" frontingDomain:nil countryCode:@"SN"],
            [OWSCountryMetadata countryMetadataWithName:@"San Marino" tld:@".sm" frontingDomain:nil countryCode:@"SM"],
            [OWSCountryMetadata countryMetadataWithName:@"Somalia" tld:@".so" frontingDomain:nil countryCode:@"SO"],
            [OWSCountryMetadata countryMetadataWithName:@"São Tomé and Príncipe"
                                                    tld:@".st"
                                         frontingDomain:nil
                                            countryCode:@"ST"],
            [OWSCountryMetadata countryMetadataWithName:@"Suriname" tld:@".sr" frontingDomain:nil countryCode:@"SR"],
            [OWSCountryMetadata countryMetadataWithName:@"El Salvador" tld:@".sv" frontingDomain:nil countryCode:@"SV"],
            [OWSCountryMetadata countryMetadataWithName:@"Chad" tld:@".td" frontingDomain:nil countryCode:@"TD"],
            [OWSCountryMetadata countryMetadataWithName:@"Togo" tld:@".tg" frontingDomain:nil countryCode:@"TG"],
            [OWSCountryMetadata countryMetadataWithName:@"Thailand" tld:@".th" frontingDomain:nil countryCode:@"TH"],
            [OWSCountryMetadata countryMetadataWithName:@"Tajikistan" tld:@".tj" frontingDomain:nil countryCode:@"TJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Tokelau" tld:@".tk" frontingDomain:nil countryCode:@"TK"],
            [OWSCountryMetadata countryMetadataWithName:@"Timor-Leste" tld:@".tl" frontingDomain:nil countryCode:@"TL"],
            [OWSCountryMetadata countryMetadataWithName:@"Turkmenistan"
                                                    tld:@".tm"
                                         frontingDomain:nil
                                            countryCode:@"TM"],
            [OWSCountryMetadata countryMetadataWithName:@"Tonga" tld:@".to" frontingDomain:nil countryCode:@"TO"],
            [OWSCountryMetadata countryMetadataWithName:@"Tunisia" tld:@".tn" frontingDomain:nil countryCode:@"TN"],
            [OWSCountryMetadata countryMetadataWithName:@"Turkey" tld:@".tr" frontingDomain:nil countryCode:@"TR"],
            [OWSCountryMetadata countryMetadataWithName:@"Trinidad and Tobago"
                                                    tld:@".tt"
                                         frontingDomain:nil
                                            countryCode:@"TT"],
            [OWSCountryMetadata countryMetadataWithName:@"Taiwan" tld:@".tw" frontingDomain:nil countryCode:@"TW"],
            [OWSCountryMetadata countryMetadataWithName:@"Tanzania" tld:@".tz" frontingDomain:nil countryCode:@"TZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ukraine" tld:@".ua" frontingDomain:nil countryCode:@"UA"],
            [OWSCountryMetadata countryMetadataWithName:@"Uganda" tld:@".ug" frontingDomain:nil countryCode:@"UG"],
            [OWSCountryMetadata countryMetadataWithName:@"United States"
                                                    tld:@".com"
                                         frontingDomain:nil
                                            countryCode:@"US"],
            [OWSCountryMetadata countryMetadataWithName:@"Uruguay" tld:@".uy" frontingDomain:nil countryCode:@"UY"],
            [OWSCountryMetadata countryMetadataWithName:@"Uzbekistan" tld:@".uz" frontingDomain:nil countryCode:@"UZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Vincent and the Grenadines"
                                                    tld:@".vc"
                                         frontingDomain:nil
                                            countryCode:@"VC"],
            [OWSCountryMetadata countryMetadataWithName:@"Venezuela" tld:@".ve" frontingDomain:nil countryCode:@"VE"],
            [OWSCountryMetadata countryMetadataWithName:@"British Virgin Islands"
                                                    tld:@".vg"
                                         frontingDomain:nil
                                            countryCode:@"VG"],
            [OWSCountryMetadata countryMetadataWithName:@"United States Virgin Islands"
                                                    tld:@".vi"
                                         frontingDomain:nil
                                            countryCode:@"VI"],
            [OWSCountryMetadata countryMetadataWithName:@"Vietnam" tld:@".vn" frontingDomain:nil countryCode:@"VN"],
            [OWSCountryMetadata countryMetadataWithName:@"Vanuatu" tld:@".vu" frontingDomain:nil countryCode:@"VU"],
            [OWSCountryMetadata countryMetadataWithName:@"Samoa" tld:@".ws" frontingDomain:nil countryCode:@"WS"],
            [OWSCountryMetadata countryMetadataWithName:@"South Africa"
                                                    tld:@".za"
                                         frontingDomain:nil
                                            countryCode:@"ZA"],
            [OWSCountryMetadata countryMetadataWithName:@"Zambia" tld:@".zm" frontingDomain:nil countryCode:@"ZM"],
            [OWSCountryMetadata countryMetadataWithName:@"Zimbabwe" tld:@".zw" frontingDomain:nil countryCode:@"ZW"],
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
