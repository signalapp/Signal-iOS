//
//  NBPhoneMetaData.m
//  libPhoneNumber
//
//

#import "NBPhoneMetaData.h"
#import "NBPhoneNumberDesc.h"
#import "NBNumberFormat.h"
#import "NSArray+NBAdditions.h"

@implementation NBPhoneMetaData

@synthesize generalDesc, fixedLine, mobile, tollFree, premiumRate, sharedCost, personalNumber, voip, pager, uan, emergency, voicemail, noInternationalDialling;
@synthesize codeID, countryCode;
@synthesize internationalPrefix, preferredInternationalPrefix, nationalPrefix, preferredExtnPrefix, nationalPrefixForParsing, nationalPrefixTransformRule, sameMobileAndFixedLinePattern, numberFormats, intlNumberFormats, mainCountryForCode, leadingDigits, leadingZeroPossible;

- (id)init
{
    self = [super init];
    
    if (self)
    {
        [self setNumberFormats:[[NSMutableArray alloc] init]];
        [self setIntlNumberFormats:[[NSMutableArray alloc] init]];

        self.leadingZeroPossible = NO;
        self.mainCountryForCode = NO;
    }
    
    return self;
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"* codeID[%@] countryCode[%@] generalDesc[%@] fixedLine[%@] mobile[%@] tollFree[%@] premiumRate[%@] sharedCost[%@] personalNumber[%@] voip[%@] pager[%@] uan[%@] emergency[%@] voicemail[%@] noInternationalDialling[%@] internationalPrefix[%@] preferredInternationalPrefix[%@] nationalPrefix[%@] preferredExtnPrefix[%@] nationalPrefixForParsing[%@] nationalPrefixTransformRule[%@] sameMobileAndFixedLinePattern[%@] numberFormats[%@] intlNumberFormats[%@] mainCountryForCode[%@] leadingDigits[%@] leadingZeroPossible[%@]",
             self.codeID, self.countryCode, self.generalDesc, self.fixedLine, self.mobile, self.tollFree, self.premiumRate, self.sharedCost, self.personalNumber, self.voip, self.pager, self.uan, self.emergency, self.voicemail, self.noInternationalDialling, self.internationalPrefix, self.preferredInternationalPrefix, self.nationalPrefix, self.preferredExtnPrefix, self.nationalPrefixForParsing, self.nationalPrefixTransformRule, self.sameMobileAndFixedLinePattern?@"Y":@"N", self.numberFormats, self.intlNumberFormats, self.mainCountryForCode?@"Y":@"N", self.leadingDigits, self.leadingZeroPossible?@"Y":@"N"];
}


- (void)buildData:(id)data
{
    if (data != nil && [data isKindOfClass:[NSArray class]] )
    {
        /*  1 */ self.generalDesc = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:1]];
        /*  2 */ self.fixedLine = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:2]];
        /*  3 */ self.mobile = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:3]];
        /*  4 */ self.tollFree = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:4]];
        /*  5 */ self.premiumRate = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:5]];
        /*  6 */ self.sharedCost = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:6]];
        /*  7 */ self.personalNumber = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:7]];
        /*  8 */ self.voip = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:8]];
        /* 21 */ self.pager = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:21]];
        /* 25 */ self.uan = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:25]];
        /* 27 */ self.emergency = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:27]];
        /* 28 */ self.voicemail = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:28]];
        /* 24 */ self.noInternationalDialling = [[NBPhoneNumberDesc alloc] initWithData:[data safeObjectAtIndex:24]];
        /*  9 */ self.codeID = [data safeObjectAtIndex:9];
        /* 10 */ self.countryCode = [data safeObjectAtIndex:10];
        /* 11 */ self.internationalPrefix = [data safeObjectAtIndex:11];
        /* 17 */ self.preferredInternationalPrefix = [data safeObjectAtIndex:17];
        /* 12 */ self.nationalPrefix = [data safeObjectAtIndex:12];
        /* 13 */ self.preferredExtnPrefix = [data safeObjectAtIndex:13];
        /* 15 */ self.nationalPrefixForParsing = [data safeObjectAtIndex:15];
        /* 16 */ self.nationalPrefixTransformRule = [data safeObjectAtIndex:16];
        /* 18 */ self.sameMobileAndFixedLinePattern = [[data safeObjectAtIndex:18] boolValue];
        /* 19 */ self.numberFormats = [self numberFormatArrayFromData:[data safeObjectAtIndex:19]];     // NBNumberFormat array
        /* 20 */ self.intlNumberFormats = [self numberFormatArrayFromData:[data safeObjectAtIndex:20]]; // NBNumberFormat array
        /* 22 */ self.mainCountryForCode = [[data safeObjectAtIndex:22] boolValue];
        /* 23 */ self.leadingDigits = [data safeObjectAtIndex:23];
        /* 26 */ self.leadingZeroPossible = [[data safeObjectAtIndex:26] boolValue];
    }
    else
    {
        NSLog(@"nil data or wrong data type");
    }
}


- (id)initWithCoder:(NSCoder*)coder
{
    if (self = [super init])
    {
        self.generalDesc = [coder decodeObjectForKey:@"generalDesc"];
        self.fixedLine = [coder decodeObjectForKey:@"fixedLine"];
        self.mobile = [coder decodeObjectForKey:@"mobile"];
        self.tollFree = [coder decodeObjectForKey:@"tollFree"];
        self.premiumRate = [coder decodeObjectForKey:@"premiumRate"];
        self.sharedCost = [coder decodeObjectForKey:@"sharedCost"];
        self.personalNumber = [coder decodeObjectForKey:@"personalNumber"];
        self.voip = [coder decodeObjectForKey:@"voip"];
        self.pager = [coder decodeObjectForKey:@"pager"];
        self.uan = [coder decodeObjectForKey:@"uan"];
        self.emergency = [coder decodeObjectForKey:@"emergency"];
        self.voicemail = [coder decodeObjectForKey:@"voicemail"];
        self.noInternationalDialling = [coder decodeObjectForKey:@"noInternationalDialling"];
        self.codeID = [coder decodeObjectForKey:@"codeID"];
        self.countryCode = [coder decodeObjectForKey:@"countryCode"];
        self.internationalPrefix = [coder decodeObjectForKey:@"internationalPrefix"];
        self.preferredInternationalPrefix = [coder decodeObjectForKey:@"preferredInternationalPrefix"];
        self.nationalPrefix = [coder decodeObjectForKey:@"nationalPrefix"];
        self.preferredExtnPrefix = [coder decodeObjectForKey:@"preferredExtnPrefix"];
        self.nationalPrefixForParsing = [coder decodeObjectForKey:@"nationalPrefixForParsing"];
        self.nationalPrefixTransformRule = [coder decodeObjectForKey:@"nationalPrefixTransformRule"];
        self.sameMobileAndFixedLinePattern = [[coder decodeObjectForKey:@"sameMobileAndFixedLinePattern"] boolValue];
        self.numberFormats = [coder decodeObjectForKey:@"numberFormats"];
        self.intlNumberFormats = [coder decodeObjectForKey:@"intlNumberFormats"];
        self.mainCountryForCode = [[coder decodeObjectForKey:@"mainCountryForCode"] boolValue];
        self.leadingDigits = [coder decodeObjectForKey:@"leadingDigits"];
        self.leadingZeroPossible = [[coder decodeObjectForKey:@"leadingZeroPossible"] boolValue];
    }
    return self;
}


- (void)encodeWithCoder:(NSCoder*)coder
{
    [coder encodeObject:self.generalDesc forKey:@"generalDesc"];
    [coder encodeObject:self.fixedLine forKey:@"fixedLine"];
    [coder encodeObject:self.mobile forKey:@"mobile"];
    [coder encodeObject:self.tollFree forKey:@"tollFree"];
    [coder encodeObject:self.premiumRate forKey:@"premiumRate"];
    [coder encodeObject:self.sharedCost forKey:@"sharedCost"];
    [coder encodeObject:self.personalNumber forKey:@"personalNumber"];
    [coder encodeObject:self.voip forKey:@"voip"];
    [coder encodeObject:self.pager forKey:@"pager"];
    [coder encodeObject:self.uan forKey:@"uan"];
    [coder encodeObject:self.emergency forKey:@"emergency"];
    [coder encodeObject:self.voicemail forKey:@"voicemail"];
    [coder encodeObject:self.noInternationalDialling forKey:@"noInternationalDialling"];
    [coder encodeObject:self.codeID forKey:@"codeID"];
    [coder encodeObject:self.countryCode forKey:@"countryCode"];
    [coder encodeObject:self.internationalPrefix forKey:@"internationalPrefix"];
    [coder encodeObject:self.preferredInternationalPrefix forKey:@"preferredInternationalPrefix"];
    [coder encodeObject:self.nationalPrefix forKey:@"nationalPrefix"];
    [coder encodeObject:self.preferredExtnPrefix forKey:@"preferredExtnPrefix"];
    [coder encodeObject:self.nationalPrefixForParsing forKey:@"nationalPrefixForParsing"];
    [coder encodeObject:self.nationalPrefixTransformRule forKey:@"nationalPrefixTransformRule"];
    [coder encodeObject:[NSNumber numberWithBool:self.sameMobileAndFixedLinePattern] forKey:@"sameMobileAndFixedLinePattern"];
    [coder encodeObject:self.numberFormats forKey:@"numberFormats"];
    [coder encodeObject:self.intlNumberFormats forKey:@"intlNumberFormats"];
    [coder encodeObject:[NSNumber numberWithBool:self.mainCountryForCode] forKey:@"mainCountryForCode"];
    [coder encodeObject:self.leadingDigits forKey:@"leadingDigits"];
    [coder encodeObject:[NSNumber numberWithBool:self.leadingZeroPossible] forKey:@"leadingZeroPossible"];
}


- (NSMutableArray*)numberFormatArrayFromData:(id)data
{
    NSMutableArray *resArray = [[NSMutableArray alloc] init];
    if (data != nil && [data isKindOfClass:[NSArray class]])
    {
        for (id numFormat in data)
        {
            NBNumberFormat *newNumberFormat = [[NBNumberFormat alloc] initWithData:numFormat];
            [resArray addObject:newNumberFormat];
        }
    }
    
    return resArray;
}


@end
