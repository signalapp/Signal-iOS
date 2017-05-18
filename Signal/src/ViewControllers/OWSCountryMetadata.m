//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCountryMetadata.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCountryMetadata

+ (OWSCountryMetadata *)countryMetadataWithName:(NSString *)name
                                            tld:(NSString *)tld
                                   googleDomain:(NSString *)googleDomain
                                    countryCode:(NSString *)countryCode
{
    OWSAssert(name.length > 0);
    OWSAssert(tld.length > 0);
    OWSAssert(googleDomain.length > 0);
    OWSAssert(countryCode.length > 0);

    OWSCountryMetadata *instance = [OWSCountryMetadata new];
    instance.name = name;
    instance.tld = tld;
    instance.googleDomain = googleDomain;
    instance.countryCode = countryCode;

    NSString *localizedCountryName = [[NSLocale currentLocale] localizedStringForCountryCode:countryCode];
    if (localizedCountryName.length < 1) {
        localizedCountryName = name;
    }
    instance.localizedCountryName = localizedCountryName;

    return instance;
}

+ (OWSCountryMetadata *)countryMetadataForCountryCode:(NSString *)countryCode
{
    OWSAssert(countryCode.length > 0);

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
        // This list is derived from:
        //
        // * https://en.wikipedia.org/wiki/List_of_Google_domains
        // * https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
        cachedValue = @[
            [OWSCountryMetadata countryMetadataWithName:@"Andorra"
                                                    tld:@".ad"
                                           googleDomain:@"google.ad"
                                            countryCode:@"AD"],
            [OWSCountryMetadata countryMetadataWithName:@"United Arab Emirates"
                                                    tld:@".ae"
                                           googleDomain:@"google.ae"
                                            countryCode:@"AE"],
            [OWSCountryMetadata countryMetadataWithName:@"Afghanistan"
                                                    tld:@".af"
                                           googleDomain:@"google.com.af"
                                            countryCode:@"AF"],
            [OWSCountryMetadata countryMetadataWithName:@"Antigua and Barbuda"
                                                    tld:@".ag"
                                           googleDomain:@"google.com.ag"
                                            countryCode:@"AG"],
            [OWSCountryMetadata countryMetadataWithName:@"Anguilla"
                                                    tld:@".ai"
                                           googleDomain:@"google.com.ai"
                                            countryCode:@"AI"],
            [OWSCountryMetadata countryMetadataWithName:@"Albania"
                                                    tld:@".al"
                                           googleDomain:@"google.al"
                                            countryCode:@"AL"],
            [OWSCountryMetadata countryMetadataWithName:@"Armenia"
                                                    tld:@".am"
                                           googleDomain:@"google.am"
                                            countryCode:@"AM"],
            [OWSCountryMetadata countryMetadataWithName:@"Angola"
                                                    tld:@".ao"
                                           googleDomain:@"google.co.ao"
                                            countryCode:@"AO"],
            [OWSCountryMetadata countryMetadataWithName:@"Argentina"
                                                    tld:@".ar"
                                           googleDomain:@"google.com.ar"
                                            countryCode:@"AR"],
            [OWSCountryMetadata countryMetadataWithName:@"American Samoa"
                                                    tld:@".as"
                                           googleDomain:@"google.as"
                                            countryCode:@"AS"],
            [OWSCountryMetadata countryMetadataWithName:@"Austria"
                                                    tld:@".at"
                                           googleDomain:@"google.at"
                                            countryCode:@"AT"],
            [OWSCountryMetadata countryMetadataWithName:@"Australia"
                                                    tld:@".au"
                                           googleDomain:@"google.com.au"
                                            countryCode:@"AU"],
            [OWSCountryMetadata countryMetadataWithName:@"Azerbaijan"
                                                    tld:@".az"
                                           googleDomain:@"google.az"
                                            countryCode:@"AZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Bosnia and Herzegovina"
                                                    tld:@".ba"
                                           googleDomain:@"google.ba"
                                            countryCode:@"BA"],
            [OWSCountryMetadata countryMetadataWithName:@"Bangladesh"
                                                    tld:@".bd"
                                           googleDomain:@"google.com.bd"
                                            countryCode:@"BD"],
            [OWSCountryMetadata countryMetadataWithName:@"Belgium"
                                                    tld:@".be"
                                           googleDomain:@"google.be"
                                            countryCode:@"BE"],
            [OWSCountryMetadata countryMetadataWithName:@"Burkina Faso"
                                                    tld:@".bf"
                                           googleDomain:@"google.bf"
                                            countryCode:@"BF"],
            [OWSCountryMetadata countryMetadataWithName:@"Bulgaria"
                                                    tld:@".bg"
                                           googleDomain:@"google.bg"
                                            countryCode:@"BG"],
            [OWSCountryMetadata countryMetadataWithName:@"Bahrain"
                                                    tld:@".bh"
                                           googleDomain:@"google.com.bh"
                                            countryCode:@"BH"],
            [OWSCountryMetadata countryMetadataWithName:@"Burundi"
                                                    tld:@".bi"
                                           googleDomain:@"google.bi"
                                            countryCode:@"BI"],
            [OWSCountryMetadata countryMetadataWithName:@"Benin"
                                                    tld:@".bj"
                                           googleDomain:@"google.bj"
                                            countryCode:@"BJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Brunei"
                                                    tld:@".bn"
                                           googleDomain:@"google.com.bn"
                                            countryCode:@"BN"],
            [OWSCountryMetadata countryMetadataWithName:@"Bolivia"
                                                    tld:@".bo"
                                           googleDomain:@"google.com.bo"
                                            countryCode:@"BO"],
            [OWSCountryMetadata countryMetadataWithName:@"Brazil"
                                                    tld:@".br"
                                           googleDomain:@"google.com.br"
                                            countryCode:@"BR"],
            [OWSCountryMetadata countryMetadataWithName:@"Bahamas"
                                                    tld:@".bs"
                                           googleDomain:@"google.bs"
                                            countryCode:@"BS"],
            [OWSCountryMetadata countryMetadataWithName:@"Bhutan"
                                                    tld:@".bt"
                                           googleDomain:@"google.bt"
                                            countryCode:@"BT"],
            [OWSCountryMetadata countryMetadataWithName:@"Botswana"
                                                    tld:@".bw"
                                           googleDomain:@"google.co.bw"
                                            countryCode:@"BW"],
            [OWSCountryMetadata countryMetadataWithName:@"Belarus"
                                                    tld:@".by"
                                           googleDomain:@"google.by"
                                            countryCode:@"BY"],
            [OWSCountryMetadata countryMetadataWithName:@"Belize"
                                                    tld:@".bz"
                                           googleDomain:@"google.com.bz"
                                            countryCode:@"BZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Canada"
                                                    tld:@".ca"
                                           googleDomain:@"google.ca"
                                            countryCode:@"CA"],
            [OWSCountryMetadata countryMetadataWithName:@"Cambodia"
                                                    tld:@".kh"
                                           googleDomain:@"google.com.kh"
                                            countryCode:@"KH"],
            [OWSCountryMetadata countryMetadataWithName:@"Cocos (Keeling) Islands"
                                                    tld:@".cc"
                                           googleDomain:@"google.cc"
                                            countryCode:@"CC"],
            [OWSCountryMetadata countryMetadataWithName:@"Democratic Republic of the Congo"
                                                    tld:@".cd"
                                           googleDomain:@"google.cd"
                                            countryCode:@"CD"],
            [OWSCountryMetadata countryMetadataWithName:@"Central African Republic"
                                                    tld:@".cf"
                                           googleDomain:@"google.cf"
                                            countryCode:@"CF"],
            [OWSCountryMetadata countryMetadataWithName:@"Republic of the Congo"
                                                    tld:@".cg"
                                           googleDomain:@"google.cg"
                                            countryCode:@"CG"],
            [OWSCountryMetadata countryMetadataWithName:@"Switzerland"
                                                    tld:@".ch"
                                           googleDomain:@"google.ch"
                                            countryCode:@"CH"],
            [OWSCountryMetadata countryMetadataWithName:@"Ivory Coast"
                                                    tld:@".ci"
                                           googleDomain:@"google.ci"
                                            countryCode:@"CI"],
            [OWSCountryMetadata countryMetadataWithName:@"Cook Islands"
                                                    tld:@".ck"
                                           googleDomain:@"google.co.ck"
                                            countryCode:@"CK"],
            [OWSCountryMetadata countryMetadataWithName:@"Chile"
                                                    tld:@".cl"
                                           googleDomain:@"google.cl"
                                            countryCode:@"CL"],
            [OWSCountryMetadata countryMetadataWithName:@"Cameroon"
                                                    tld:@".cm"
                                           googleDomain:@"google.cm"
                                            countryCode:@"CM"],
            [OWSCountryMetadata countryMetadataWithName:@"China"
                                                    tld:@".cn"
                                           googleDomain:@"google.cn"
                                            countryCode:@"CN"],
            [OWSCountryMetadata countryMetadataWithName:@"Colombia"
                                                    tld:@".co"
                                           googleDomain:@"google.co"
                                            countryCode:@"CO"],
            [OWSCountryMetadata countryMetadataWithName:@"Costa Rica"
                                                    tld:@".cr"
                                           googleDomain:@"google.co.cr"
                                            countryCode:@"CR"],
            [OWSCountryMetadata countryMetadataWithName:@"Cuba"
                                                    tld:@".cu"
                                           googleDomain:@"google.com.cu"
                                            countryCode:@"CU"],
            [OWSCountryMetadata countryMetadataWithName:@"Cape Verde"
                                                    tld:@".cv"
                                           googleDomain:@"google.cv"
                                            countryCode:@"CV"],
            [OWSCountryMetadata countryMetadataWithName:@"Christmas Island"
                                                    tld:@".cx"
                                           googleDomain:@"google.cx"
                                            countryCode:@"CX"],
            [OWSCountryMetadata countryMetadataWithName:@"Cyprus"
                                                    tld:@".cy"
                                           googleDomain:@"google.com.cy"
                                            countryCode:@"CY"],
            [OWSCountryMetadata countryMetadataWithName:@"Czech Republic"
                                                    tld:@".cz"
                                           googleDomain:@"google.cz"
                                            countryCode:@"CZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Germany"
                                                    tld:@".de"
                                           googleDomain:@"google.de"
                                            countryCode:@"DE"],
            [OWSCountryMetadata countryMetadataWithName:@"Djibouti"
                                                    tld:@".dj"
                                           googleDomain:@"google.dj"
                                            countryCode:@"DJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Denmark"
                                                    tld:@".dk"
                                           googleDomain:@"google.dk"
                                            countryCode:@"DK"],
            [OWSCountryMetadata countryMetadataWithName:@"Dominica"
                                                    tld:@".dm"
                                           googleDomain:@"google.dm"
                                            countryCode:@"DM"],
            [OWSCountryMetadata countryMetadataWithName:@"Dominican Republic"
                                                    tld:@".do"
                                           googleDomain:@"google.com.do"
                                            countryCode:@"DO"],
            [OWSCountryMetadata countryMetadataWithName:@"Algeria"
                                                    tld:@".dz"
                                           googleDomain:@"google.dz"
                                            countryCode:@"DZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ecuador"
                                                    tld:@".ec"
                                           googleDomain:@"google.com.ec"
                                            countryCode:@"EC"],
            [OWSCountryMetadata countryMetadataWithName:@"Estonia"
                                                    tld:@".ee"
                                           googleDomain:@"google.ee"
                                            countryCode:@"EE"],
            [OWSCountryMetadata countryMetadataWithName:@"Egypt"
                                                    tld:@".eg"
                                           googleDomain:@"google.com.eg"
                                            countryCode:@"EG"],
            [OWSCountryMetadata countryMetadataWithName:@"Spain"
                                                    tld:@".es"
                                           googleDomain:@"google.es"
                                            countryCode:@"ES"],
            [OWSCountryMetadata countryMetadataWithName:@"Ethiopia"
                                                    tld:@".et"
                                           googleDomain:@"google.com.et"
                                            countryCode:@"ET"],
            [OWSCountryMetadata countryMetadataWithName:@"Finland"
                                                    tld:@".fi"
                                           googleDomain:@"google.fi"
                                            countryCode:@"FI"],
            [OWSCountryMetadata countryMetadataWithName:@"Fiji"
                                                    tld:@".fj"
                                           googleDomain:@"google.com.fj"
                                            countryCode:@"FJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Federated States of Micronesia"
                                                    tld:@".fm"
                                           googleDomain:@"google.fm"
                                            countryCode:@"FM"],
            [OWSCountryMetadata countryMetadataWithName:@"France"
                                                    tld:@".fr"
                                           googleDomain:@"google.fr"
                                            countryCode:@"FR"],
            [OWSCountryMetadata countryMetadataWithName:@"Gabon"
                                                    tld:@".ga"
                                           googleDomain:@"google.ga"
                                            countryCode:@"GA"],
            [OWSCountryMetadata countryMetadataWithName:@"Georgia"
                                                    tld:@".ge"
                                           googleDomain:@"google.ge"
                                            countryCode:@"GE"],
            [OWSCountryMetadata countryMetadataWithName:@"French Guiana"
                                                    tld:@".gf"
                                           googleDomain:@"google.gf"
                                            countryCode:@"GF"],
            [OWSCountryMetadata countryMetadataWithName:@"Guernsey"
                                                    tld:@".gg"
                                           googleDomain:@"google.gg"
                                            countryCode:@"GG"],
            [OWSCountryMetadata countryMetadataWithName:@"Ghana"
                                                    tld:@".gh"
                                           googleDomain:@"google.com.gh"
                                            countryCode:@"GH"],
            [OWSCountryMetadata countryMetadataWithName:@"Gibraltar"
                                                    tld:@".gi"
                                           googleDomain:@"google.com.gi"
                                            countryCode:@"GI"],
            [OWSCountryMetadata countryMetadataWithName:@"Greenland"
                                                    tld:@".gl"
                                           googleDomain:@"google.gl"
                                            countryCode:@"GL"],
            [OWSCountryMetadata countryMetadataWithName:@"Gambia"
                                                    tld:@".gm"
                                           googleDomain:@"google.gm"
                                            countryCode:@"GM"],
            [OWSCountryMetadata countryMetadataWithName:@"Guadeloupe"
                                                    tld:@".gp"
                                           googleDomain:@"google.gp"
                                            countryCode:@"GP"],
            [OWSCountryMetadata countryMetadataWithName:@"Greece"
                                                    tld:@".gr"
                                           googleDomain:@"google.gr"
                                            countryCode:@"GR"],
            [OWSCountryMetadata countryMetadataWithName:@"Guatemala"
                                                    tld:@".gt"
                                           googleDomain:@"google.com.gt"
                                            countryCode:@"GT"],
            [OWSCountryMetadata countryMetadataWithName:@"Guyana"
                                                    tld:@".gy"
                                           googleDomain:@"google.gy"
                                            countryCode:@"GY"],
            [OWSCountryMetadata countryMetadataWithName:@"Hong Kong"
                                                    tld:@".hk"
                                           googleDomain:@"google.com.hk"
                                            countryCode:@"HK"],
            [OWSCountryMetadata countryMetadataWithName:@"Honduras"
                                                    tld:@".hn"
                                           googleDomain:@"google.hn"
                                            countryCode:@"HN"],
            [OWSCountryMetadata countryMetadataWithName:@"Croatia"
                                                    tld:@".hr"
                                           googleDomain:@"google.hr"
                                            countryCode:@"HR"],
            [OWSCountryMetadata countryMetadataWithName:@"Haiti"
                                                    tld:@".ht"
                                           googleDomain:@"google.ht"
                                            countryCode:@"HT"],
            [OWSCountryMetadata countryMetadataWithName:@"Hungary"
                                                    tld:@".hu"
                                           googleDomain:@"google.hu"
                                            countryCode:@"HU"],
            [OWSCountryMetadata countryMetadataWithName:@"Indonesia"
                                                    tld:@".id"
                                           googleDomain:@"google.co.id"
                                            countryCode:@"ID"],
            [OWSCountryMetadata countryMetadataWithName:@"Iraq" tld:@".iq" googleDomain:@"google.iq" countryCode:@"IQ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ireland"
                                                    tld:@".ie"
                                           googleDomain:@"google.ie"
                                            countryCode:@"IE"],
            [OWSCountryMetadata countryMetadataWithName:@"Israel"
                                                    tld:@".il"
                                           googleDomain:@"google.co.il"
                                            countryCode:@"IL"],
            [OWSCountryMetadata countryMetadataWithName:@"Isle of Man"
                                                    tld:@".im"
                                           googleDomain:@"google.im"
                                            countryCode:@"IM"],
            [OWSCountryMetadata countryMetadataWithName:@"India"
                                                    tld:@".in"
                                           googleDomain:@"google.co.in"
                                            countryCode:@"IN"],
            [OWSCountryMetadata countryMetadataWithName:@"British Indian Ocean Territory"
                                                    tld:@".io"
                                           googleDomain:@"google.io"
                                            countryCode:@"IO"],
            [OWSCountryMetadata countryMetadataWithName:@"Iceland"
                                                    tld:@".is"
                                           googleDomain:@"google.is"
                                            countryCode:@"IS"],
            [OWSCountryMetadata countryMetadataWithName:@"Italy"
                                                    tld:@".it"
                                           googleDomain:@"google.it"
                                            countryCode:@"IT"],
            [OWSCountryMetadata countryMetadataWithName:@"Jersey"
                                                    tld:@".je"
                                           googleDomain:@"google.je"
                                            countryCode:@"JE"],
            [OWSCountryMetadata countryMetadataWithName:@"Jamaica"
                                                    tld:@".jm"
                                           googleDomain:@"google.com.jm"
                                            countryCode:@"JM"],
            [OWSCountryMetadata countryMetadataWithName:@"Jordan"
                                                    tld:@".jo"
                                           googleDomain:@"google.jo"
                                            countryCode:@"JO"],
            [OWSCountryMetadata countryMetadataWithName:@"Japan"
                                                    tld:@".jp"
                                           googleDomain:@"google.co.jp"
                                            countryCode:@"JP"],
            [OWSCountryMetadata countryMetadataWithName:@"Kenya"
                                                    tld:@".ke"
                                           googleDomain:@"google.co.ke"
                                            countryCode:@"KE"],
            [OWSCountryMetadata countryMetadataWithName:@"Kiribati"
                                                    tld:@".ki"
                                           googleDomain:@"google.ki"
                                            countryCode:@"KI"],
            [OWSCountryMetadata countryMetadataWithName:@"Kyrgyzstan"
                                                    tld:@".kg"
                                           googleDomain:@"google.kg"
                                            countryCode:@"KG"],
            [OWSCountryMetadata countryMetadataWithName:@"South Korea"
                                                    tld:@".kr"
                                           googleDomain:@"google.co.kr"
                                            countryCode:@"KR"],
            [OWSCountryMetadata countryMetadataWithName:@"Kuwait"
                                                    tld:@".kw"
                                           googleDomain:@"google.com.kw"
                                            countryCode:@"KW"],
            [OWSCountryMetadata countryMetadataWithName:@"Kazakhstan"
                                                    tld:@".kz"
                                           googleDomain:@"google.kz"
                                            countryCode:@"KZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Laos" tld:@".la" googleDomain:@"google.la" countryCode:@"LA"],
            [OWSCountryMetadata countryMetadataWithName:@"Lebanon"
                                                    tld:@".lb"
                                           googleDomain:@"google.com.lb"
                                            countryCode:@"LB"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Lucia"
                                                    tld:@".lc"
                                           googleDomain:@"google.com.lc"
                                            countryCode:@"LC"],
            [OWSCountryMetadata countryMetadataWithName:@"Liechtenstein"
                                                    tld:@".li"
                                           googleDomain:@"google.li"
                                            countryCode:@"LI"],
            [OWSCountryMetadata countryMetadataWithName:@"Sri Lanka"
                                                    tld:@".lk"
                                           googleDomain:@"google.lk"
                                            countryCode:@"LK"],
            [OWSCountryMetadata countryMetadataWithName:@"Lesotho"
                                                    tld:@".ls"
                                           googleDomain:@"google.co.ls"
                                            countryCode:@"LS"],
            [OWSCountryMetadata countryMetadataWithName:@"Lithuania"
                                                    tld:@".lt"
                                           googleDomain:@"google.lt"
                                            countryCode:@"LT"],
            [OWSCountryMetadata countryMetadataWithName:@"Luxembourg"
                                                    tld:@".lu"
                                           googleDomain:@"google.lu"
                                            countryCode:@"LU"],
            [OWSCountryMetadata countryMetadataWithName:@"Latvia"
                                                    tld:@".lv"
                                           googleDomain:@"google.lv"
                                            countryCode:@"LV"],
            [OWSCountryMetadata countryMetadataWithName:@"Libya"
                                                    tld:@".ly"
                                           googleDomain:@"google.com.ly"
                                            countryCode:@"LY"],
            [OWSCountryMetadata countryMetadataWithName:@"Morocco"
                                                    tld:@".ma"
                                           googleDomain:@"google.co.ma"
                                            countryCode:@"MA"],
            [OWSCountryMetadata countryMetadataWithName:@"Moldova"
                                                    tld:@".md"
                                           googleDomain:@"google.md"
                                            countryCode:@"MD"],
            [OWSCountryMetadata countryMetadataWithName:@"Montenegro"
                                                    tld:@".me"
                                           googleDomain:@"google.me"
                                            countryCode:@"ME"],
            [OWSCountryMetadata countryMetadataWithName:@"Madagascar"
                                                    tld:@".mg"
                                           googleDomain:@"google.mg"
                                            countryCode:@"MG"],
            [OWSCountryMetadata countryMetadataWithName:@"Macedonia"
                                                    tld:@".mk"
                                           googleDomain:@"google.mk"
                                            countryCode:@"MK"],
            [OWSCountryMetadata countryMetadataWithName:@"Mali" tld:@".ml" googleDomain:@"google.ml" countryCode:@"ML"],
            [OWSCountryMetadata countryMetadataWithName:@"Myanmar"
                                                    tld:@".mm"
                                           googleDomain:@"google.com.mm"
                                            countryCode:@"MM"],
            [OWSCountryMetadata countryMetadataWithName:@"Mongolia"
                                                    tld:@".mn"
                                           googleDomain:@"google.mn"
                                            countryCode:@"MN"],
            [OWSCountryMetadata countryMetadataWithName:@"Montserrat"
                                                    tld:@".ms"
                                           googleDomain:@"google.ms"
                                            countryCode:@"MS"],
            [OWSCountryMetadata countryMetadataWithName:@"Malta"
                                                    tld:@".mt"
                                           googleDomain:@"google.com.mt"
                                            countryCode:@"MT"],
            [OWSCountryMetadata countryMetadataWithName:@"Mauritius"
                                                    tld:@".mu"
                                           googleDomain:@"google.mu"
                                            countryCode:@"MU"],
            [OWSCountryMetadata countryMetadataWithName:@"Maldives"
                                                    tld:@".mv"
                                           googleDomain:@"google.mv"
                                            countryCode:@"MV"],
            [OWSCountryMetadata countryMetadataWithName:@"Malawi"
                                                    tld:@".mw"
                                           googleDomain:@"google.mw"
                                            countryCode:@"MW"],
            [OWSCountryMetadata countryMetadataWithName:@"Mexico"
                                                    tld:@".mx"
                                           googleDomain:@"google.com.mx"
                                            countryCode:@"MX"],
            [OWSCountryMetadata countryMetadataWithName:@"Malaysia"
                                                    tld:@".my"
                                           googleDomain:@"google.com.my"
                                            countryCode:@"MY"],
            [OWSCountryMetadata countryMetadataWithName:@"Mozambique"
                                                    tld:@".mz"
                                           googleDomain:@"google.co.mz"
                                            countryCode:@"MZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Namibia"
                                                    tld:@".na"
                                           googleDomain:@"google.com.na"
                                            countryCode:@"NA"],
            [OWSCountryMetadata countryMetadataWithName:@"Niger"
                                                    tld:@".ne"
                                           googleDomain:@"google.ne"
                                            countryCode:@"NE"],
            [OWSCountryMetadata countryMetadataWithName:@"Norfolk Island"
                                                    tld:@".nf"
                                           googleDomain:@"google.nf"
                                            countryCode:@"NF"],
            [OWSCountryMetadata countryMetadataWithName:@"Nigeria"
                                                    tld:@".ng"
                                           googleDomain:@"google.com.ng"
                                            countryCode:@"NG"],
            [OWSCountryMetadata countryMetadataWithName:@"Nicaragua"
                                                    tld:@".ni"
                                           googleDomain:@"google.com.ni"
                                            countryCode:@"NI"],
            [OWSCountryMetadata countryMetadataWithName:@"Netherlands"
                                                    tld:@".nl"
                                           googleDomain:@"google.nl"
                                            countryCode:@"NL"],
            [OWSCountryMetadata countryMetadataWithName:@"Norway"
                                                    tld:@".no"
                                           googleDomain:@"google.no"
                                            countryCode:@"NO"],
            [OWSCountryMetadata countryMetadataWithName:@"Nepal"
                                                    tld:@".np"
                                           googleDomain:@"google.com.np"
                                            countryCode:@"NP"],
            [OWSCountryMetadata countryMetadataWithName:@"Nauru"
                                                    tld:@".nr"
                                           googleDomain:@"google.nr"
                                            countryCode:@"NR"],
            [OWSCountryMetadata countryMetadataWithName:@"Niue" tld:@".nu" googleDomain:@"google.nu" countryCode:@"NU"],
            [OWSCountryMetadata countryMetadataWithName:@"New Zealand"
                                                    tld:@".nz"
                                           googleDomain:@"google.co.nz"
                                            countryCode:@"NZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Oman"
                                                    tld:@".om"
                                           googleDomain:@"google.com.om"
                                            countryCode:@"OM"],
            [OWSCountryMetadata countryMetadataWithName:@"Pakistan"
                                                    tld:@".pk"
                                           googleDomain:@"google.com.pk"
                                            countryCode:@"PK"],
            [OWSCountryMetadata countryMetadataWithName:@"Panama"
                                                    tld:@".pa"
                                           googleDomain:@"google.com.pa"
                                            countryCode:@"PA"],
            [OWSCountryMetadata countryMetadataWithName:@"Peru"
                                                    tld:@".pe"
                                           googleDomain:@"google.com.pe"
                                            countryCode:@"PE"],
            [OWSCountryMetadata countryMetadataWithName:@"Philippines"
                                                    tld:@".ph"
                                           googleDomain:@"google.com.ph"
                                            countryCode:@"PH"],
            [OWSCountryMetadata countryMetadataWithName:@"Poland"
                                                    tld:@".pl"
                                           googleDomain:@"google.pl"
                                            countryCode:@"PL"],
            [OWSCountryMetadata countryMetadataWithName:@"Papua New Guinea"
                                                    tld:@".pg"
                                           googleDomain:@"google.com.pg"
                                            countryCode:@"PG"],
            [OWSCountryMetadata countryMetadataWithName:@"Pitcairn Islands"
                                                    tld:@".pn"
                                           googleDomain:@"google.pn"
                                            countryCode:@"PN"],
            [OWSCountryMetadata countryMetadataWithName:@"Puerto Rico"
                                                    tld:@".pr"
                                           googleDomain:@"google.com.pr"
                                            countryCode:@"PR"],
            [OWSCountryMetadata countryMetadataWithName:@"Palestine[4]"
                                                    tld:@".ps"
                                           googleDomain:@"google.ps"
                                            countryCode:@"PS"],
            [OWSCountryMetadata countryMetadataWithName:@"Portugal"
                                                    tld:@".pt"
                                           googleDomain:@"google.pt"
                                            countryCode:@"PT"],
            [OWSCountryMetadata countryMetadataWithName:@"Paraguay"
                                                    tld:@".py"
                                           googleDomain:@"google.com.py"
                                            countryCode:@"PY"],
            [OWSCountryMetadata countryMetadataWithName:@"Qatar"
                                                    tld:@".qa"
                                           googleDomain:@"google.com.qa"
                                            countryCode:@"QA"],
            [OWSCountryMetadata countryMetadataWithName:@"Romania"
                                                    tld:@".ro"
                                           googleDomain:@"google.ro"
                                            countryCode:@"RO"],
            [OWSCountryMetadata countryMetadataWithName:@"Serbia"
                                                    tld:@".rs"
                                           googleDomain:@"google.rs"
                                            countryCode:@"RS"],
            [OWSCountryMetadata countryMetadataWithName:@"Russia"
                                                    tld:@".ru"
                                           googleDomain:@"google.ru"
                                            countryCode:@"RU"],
            [OWSCountryMetadata countryMetadataWithName:@"Rwanda"
                                                    tld:@".rw"
                                           googleDomain:@"google.rw"
                                            countryCode:@"RW"],
            [OWSCountryMetadata countryMetadataWithName:@"Saudi Arabia"
                                                    tld:@".sa"
                                           googleDomain:@"google.com.sa"
                                            countryCode:@"SA"],
            [OWSCountryMetadata countryMetadataWithName:@"Solomon Islands"
                                                    tld:@".sb"
                                           googleDomain:@"google.com.sb"
                                            countryCode:@"SB"],
            [OWSCountryMetadata countryMetadataWithName:@"Seychelles"
                                                    tld:@".sc"
                                           googleDomain:@"google.sc"
                                            countryCode:@"SC"],
            [OWSCountryMetadata countryMetadataWithName:@"Sweden"
                                                    tld:@".se"
                                           googleDomain:@"google.se"
                                            countryCode:@"SE"],
            [OWSCountryMetadata countryMetadataWithName:@"Singapore"
                                                    tld:@".sg"
                                           googleDomain:@"google.com.sg"
                                            countryCode:@"SG"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Helena, Ascension and Tristan da Cunha"
                                                    tld:@".sh"
                                           googleDomain:@"google.sh"
                                            countryCode:@"SH"],
            [OWSCountryMetadata countryMetadataWithName:@"Slovenia"
                                                    tld:@".si"
                                           googleDomain:@"google.si"
                                            countryCode:@"SI"],
            [OWSCountryMetadata countryMetadataWithName:@"Slovakia"
                                                    tld:@".sk"
                                           googleDomain:@"google.sk"
                                            countryCode:@"SK"],
            [OWSCountryMetadata countryMetadataWithName:@"Sierra Leone"
                                                    tld:@".sl"
                                           googleDomain:@"google.com.sl"
                                            countryCode:@"SL"],
            [OWSCountryMetadata countryMetadataWithName:@"Senegal"
                                                    tld:@".sn"
                                           googleDomain:@"google.sn"
                                            countryCode:@"SN"],
            [OWSCountryMetadata countryMetadataWithName:@"San Marino"
                                                    tld:@".sm"
                                           googleDomain:@"google.sm"
                                            countryCode:@"SM"],
            [OWSCountryMetadata countryMetadataWithName:@"Somalia"
                                                    tld:@".so"
                                           googleDomain:@"google.so"
                                            countryCode:@"SO"],
            [OWSCountryMetadata countryMetadataWithName:@"São Tomé and Príncipe"
                                                    tld:@".st"
                                           googleDomain:@"google.st"
                                            countryCode:@"ST"],
            [OWSCountryMetadata countryMetadataWithName:@"Suriname"
                                                    tld:@".sr"
                                           googleDomain:@"google.sr"
                                            countryCode:@"SR"],
            [OWSCountryMetadata countryMetadataWithName:@"El Salvador"
                                                    tld:@".sv"
                                           googleDomain:@"google.com.sv"
                                            countryCode:@"SV"],
            [OWSCountryMetadata countryMetadataWithName:@"Chad" tld:@".td" googleDomain:@"google.td" countryCode:@"TD"],
            [OWSCountryMetadata countryMetadataWithName:@"Togo" tld:@".tg" googleDomain:@"google.tg" countryCode:@"TG"],
            [OWSCountryMetadata countryMetadataWithName:@"Thailand"
                                                    tld:@".th"
                                           googleDomain:@"google.co.th"
                                            countryCode:@"TH"],
            [OWSCountryMetadata countryMetadataWithName:@"Tajikistan"
                                                    tld:@".tj"
                                           googleDomain:@"google.com.tj"
                                            countryCode:@"TJ"],
            [OWSCountryMetadata countryMetadataWithName:@"Tokelau"
                                                    tld:@".tk"
                                           googleDomain:@"google.tk"
                                            countryCode:@"TK"],
            [OWSCountryMetadata countryMetadataWithName:@"Timor-Leste"
                                                    tld:@".tl"
                                           googleDomain:@"google.tl"
                                            countryCode:@"TL"],
            [OWSCountryMetadata countryMetadataWithName:@"Turkmenistan"
                                                    tld:@".tm"
                                           googleDomain:@"google.tm"
                                            countryCode:@"TM"],
            [OWSCountryMetadata countryMetadataWithName:@"Tonga"
                                                    tld:@".to"
                                           googleDomain:@"google.to"
                                            countryCode:@"TO"],
            [OWSCountryMetadata countryMetadataWithName:@"Tunisia"
                                                    tld:@".tn"
                                           googleDomain:@"google.tn"
                                            countryCode:@"TN"],
            [OWSCountryMetadata countryMetadataWithName:@"Turkey"
                                                    tld:@".tr"
                                           googleDomain:@"google.com.tr"
                                            countryCode:@"TR"],
            [OWSCountryMetadata countryMetadataWithName:@"Trinidad and Tobago"
                                                    tld:@".tt"
                                           googleDomain:@"google.tt"
                                            countryCode:@"TT"],
            [OWSCountryMetadata countryMetadataWithName:@"Taiwan"
                                                    tld:@".tw"
                                           googleDomain:@"google.com.tw"
                                            countryCode:@"TW"],
            [OWSCountryMetadata countryMetadataWithName:@"Tanzania"
                                                    tld:@".tz"
                                           googleDomain:@"google.co.tz"
                                            countryCode:@"TZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Ukraine"
                                                    tld:@".ua"
                                           googleDomain:@"google.com.ua"
                                            countryCode:@"UA"],
            [OWSCountryMetadata countryMetadataWithName:@"Uganda"
                                                    tld:@".ug"
                                           googleDomain:@"google.co.ug"
                                            countryCode:@"UG"],
            [OWSCountryMetadata countryMetadataWithName:@"United States"
                                                    tld:@".us"
                                           googleDomain:@"google.us"
                                            countryCode:@"US"],
            [OWSCountryMetadata countryMetadataWithName:@"Uruguay"
                                                    tld:@".uy"
                                           googleDomain:@"google.com.uy"
                                            countryCode:@"UY"],
            [OWSCountryMetadata countryMetadataWithName:@"Uzbekistan"
                                                    tld:@".uz"
                                           googleDomain:@"google.co.uz"
                                            countryCode:@"UZ"],
            [OWSCountryMetadata countryMetadataWithName:@"Saint Vincent and the Grenadines"
                                                    tld:@".vc"
                                           googleDomain:@"google.com.vc"
                                            countryCode:@"VC"],
            [OWSCountryMetadata countryMetadataWithName:@"Venezuela"
                                                    tld:@".ve"
                                           googleDomain:@"google.co.ve"
                                            countryCode:@"VE"],
            [OWSCountryMetadata countryMetadataWithName:@"British Virgin Islands"
                                                    tld:@".vg"
                                           googleDomain:@"google.vg"
                                            countryCode:@"VG"],
            [OWSCountryMetadata countryMetadataWithName:@"United States Virgin Islands"
                                                    tld:@".vi"
                                           googleDomain:@"google.co.vi"
                                            countryCode:@"VI"],
            [OWSCountryMetadata countryMetadataWithName:@"Vietnam"
                                                    tld:@".vn"
                                           googleDomain:@"google.com.vn"
                                            countryCode:@"VN"],
            [OWSCountryMetadata countryMetadataWithName:@"Vanuatu"
                                                    tld:@".vu"
                                           googleDomain:@"google.vu"
                                            countryCode:@"VU"],
            [OWSCountryMetadata countryMetadataWithName:@"Samoa"
                                                    tld:@".ws"
                                           googleDomain:@"google.ws"
                                            countryCode:@"WS"],
            [OWSCountryMetadata countryMetadataWithName:@"South Africa"
                                                    tld:@".za"
                                           googleDomain:@"google.co.za"
                                            countryCode:@"ZA"],
            [OWSCountryMetadata countryMetadataWithName:@"Zambia"
                                                    tld:@".zm"
                                           googleDomain:@"google.co.zm"
                                            countryCode:@"ZM"],
            [OWSCountryMetadata countryMetadataWithName:@"Zimbabwe"
                                                    tld:@".zw"
                                           googleDomain:@"google.co.zw"
                                            countryCode:@"ZW"],
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
