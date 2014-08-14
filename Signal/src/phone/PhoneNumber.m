#import "PhoneNumber.h"
#import "Constraints.h"
#import "Util.h"
#import "PreferencesUtil.h"
#import "Environment.h"
#import "NBPhoneNumber.h"
#import "NBAsYouTypeFormatter.h"

static NSString *const RPDefaultsKeyPhoneNumberString = @"RPDefaultsKeyPhoneNumberString";
static NSString *const RPDefaultsKeyPhoneNumberCanonical = @"RPDefaultsKeyPhoneNumberCanonical";

@implementation PhoneNumber

+(PhoneNumber*) phoneNumberFromText:(NSString*)text andRegion:(NSString*)regionCode {
    require(text != nil);
    require(regionCode != nil);
    
    NBPhoneNumberUtil *phoneUtil = [NBPhoneNumberUtil sharedInstance];
    
    NSError* parseError = nil;
    NBPhoneNumber *number = [phoneUtil parse:text
                               defaultRegion:regionCode
                                       error:&parseError];
    checkOperationDescribe(parseError == nil, [parseError description]);
    //checkOperation([phoneUtil isValidNumber:number]);
    
    NSError* toE164Error;
    NSString* e164 = [phoneUtil format:number numberFormat:NBEPhoneNumberFormatE164 error:&toE164Error];
    checkOperationDescribe(toE164Error == nil, [e164 description]);
    
    PhoneNumber* phoneNumber = [PhoneNumber new];
    phoneNumber->phoneNumber = number;
    phoneNumber->e164 = e164;
    return phoneNumber;
}

+(PhoneNumber*) phoneNumberFromUserSpecifiedText:(NSString*)text {
    require(text != nil);
    
    return [PhoneNumber phoneNumberFromText:text
                                  andRegion:[Environment currentRegionCodeForPhoneNumbers]];
}

+(PhoneNumber*) phoneNumberFromE164:(NSString*)text {
    require(text != nil);
    checkOperation([text hasPrefix:COUNTRY_CODE_PREFIX]);
    PhoneNumber *number = [PhoneNumber phoneNumberFromText:text
                                                 andRegion:@"ZZ"];

    checkOperation(number != nil);
    return number;
}

+(NSString*) bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input {
    return [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:input
                                                               withSpecifiedRegionCode:[Environment currentRegionCodeForPhoneNumbers]];
}

+(NSString*) bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input withSpecifiedCountryCodeString:(NSString *)countryCodeString{
    return [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:input
                                                               withSpecifiedRegionCode:[PhoneNumber regionCodeFromCountryCodeString:countryCodeString]];
}

+(NSString*) bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input withSpecifiedRegionCode:(NSString *) regionCode{
    NBAsYouTypeFormatter* formatter = [[NBAsYouTypeFormatter alloc] initWithRegionCode:regionCode];
    
    NSString* result = input;
    for (NSUInteger i = 0; i < input.length; i++) {
        result = [formatter inputDigit:[input substringWithRange:NSMakeRange(i, 1)]];
    }
    return result;
}


+(NSString*) regionCodeFromCountryCodeString:(NSString*) countryCodeString {
    NBPhoneNumberUtil* phoneUtil = [NBPhoneNumberUtil sharedInstance];
    NSString* regionCode = [phoneUtil getRegionCodeForCountryCode:@([[countryCodeString substringFromIndex:1] integerValue])];
    return regionCode;
}


+(PhoneNumber*) tryParsePhoneNumberFromText:(NSString*)text fromRegion:(NSString*)regionCode {
    require(text != nil);
    require(regionCode != nil);
    
    @try {
        return [self phoneNumberFromText:text andRegion:regionCode];
    } @catch (OperationFailed* ex) {
        DDLogError(@"Error parsing phone number from region code");
        return nil;
    }
}

+(PhoneNumber*) tryParsePhoneNumberFromUserSpecifiedText:(NSString*)text {
    require(text != nil);

    char s[text.length+1];
    int xx = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar x = [text characterAtIndex:i];
        if (x == '+' || (x >= '0' && x <= '9')) {
            s[xx++] = (char)x;
        }
    }

    s[xx]=0;
    text = [NSString stringWithUTF8String:(void*)s];

    @try {
        return [self phoneNumberFromUserSpecifiedText:text];
    } @catch (OperationFailed* ex) {
        return nil;
    }
}
+(PhoneNumber*) tryParsePhoneNumberFromE164:(NSString*)text {
    require(text != nil);
	
    @try {
        return [self phoneNumberFromE164:text];
    } @catch (OperationFailed* ex) {
        return nil;
    }
}

-(NSURL*) toSystemDialerURL {
    NSString* link = [NSString stringWithFormat:@"telprompt://%@", e164];
    return [NSURL URLWithString:link];
}

-(NSString *)toE164 {
    return e164;
}

- (NSNumber*)getCountryCode {
    return phoneNumber.countryCode;
}

-(BOOL)isValid {
    return [[NBPhoneNumberUtil sharedInstance] isValidNumber:phoneNumber];
}

-(NSString *)localizedDescriptionForUser {
    NBPhoneNumberUtil *phoneUtil = [NBPhoneNumberUtil sharedInstance];

    NSError* formatError = nil;
    NSString* pretty = [phoneUtil format:phoneNumber
                            numberFormat:NBEPhoneNumberFormatINTERNATIONAL
                                   error:&formatError];
    
    if (formatError != nil) return e164;
    return pretty;
}

-(BOOL)resolvesInternationallyTo:(PhoneNumber*) otherPhoneNumber {
    return [self.toE164 isEqualToString:otherPhoneNumber.toE164];
}

-(NSString*) description {
    return e164;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:phoneNumber forKey:RPDefaultsKeyPhoneNumberString];
    [encoder encodeObject:e164 forKey:RPDefaultsKeyPhoneNumberCanonical];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if((self = [super init])) {
        phoneNumber = [decoder decodeObjectForKey:RPDefaultsKeyPhoneNumberString];
        e164 = [decoder decodeObjectForKey:RPDefaultsKeyPhoneNumberCanonical];
    }
    return self;
}

@end
