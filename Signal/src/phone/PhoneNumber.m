#import "PhoneNumber.h"
#import "Constraints.h"
#import "Util.h"
#import "PreferencesUtil.h"
#import "Environment.h"
#import "NBPhoneNumber.h"
#import "NBAsYouTypeFormatter.h"

static NSString *const RPDefaultsKeyPhoneNumberString = @"RPDefaultsKeyPhoneNumberString";
static NSString *const RPDefaultsKeyPhoneNumberCanonical = @"RPDefaultsKeyPhoneNumberCanonical";

@interface PhoneNumber ()

@property (strong, nonatomic) NBPhoneNumber* phoneNumber;
@property (strong, nonatomic) NSString* e164;

@end

@implementation PhoneNumber

- (instancetype)initFromText:(NSString*)text andRegion:(NSString*)regionCode {
    if (self = [super init]) {
        require(text != nil);
        require(regionCode != nil);
        
        NBPhoneNumberUtil *phoneUtil = [NBPhoneNumberUtil sharedInstance];
        
        NSError* parseError = nil;
        NBPhoneNumber* number = [phoneUtil parse:text
                                   defaultRegion:regionCode
                                           error:&parseError];
        checkOperationDescribe(parseError == nil, [parseError description]);
        //checkOperation([phoneUtil isValidNumber:number]);
        
        NSError* toE164Error;
        NSString* e164 = [phoneUtil format:number numberFormat:NBEPhoneNumberFormatE164 error:&toE164Error];
        checkOperationDescribe(toE164Error == nil, [e164 description]);
        
        self.phoneNumber = number;
        self.e164 = e164;
    }
    
    return self;
}

- (instancetype)initFromUserSpecifiedText:(NSString*)text {
    return [self initFromText:text andRegion:[Environment currentRegionCodeForPhoneNumbers]];
}

- (instancetype)initFromE164:(NSString*)text {
    require(text != nil);
    checkOperation([text hasPrefix:COUNTRY_CODE_PREFIX]);
    self = [self initFromText:text andRegion:@"ZZ"];
    checkOperation(self != nil);
    return self;
}

+ (PhoneNumber*)phoneNumberFromText:(NSString*)text andRegion:(NSString*)regionCode {
    return [[PhoneNumber alloc] initFromText:text andRegion:regionCode];
}

+ (PhoneNumber*)phoneNumberFromUserSpecifiedText:(NSString*)text {
    return [[PhoneNumber alloc] initFromUserSpecifiedText:text];
}

+ (PhoneNumber*)phoneNumberFromE164:(NSString*)text {
    return [[PhoneNumber alloc] initFromE164:text];
}

+ (NSString*)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input {
    return [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:input
                                                               withSpecifiedRegionCode:[Environment currentRegionCodeForPhoneNumbers]];
}

+ (NSString*)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input
                                             withSpecifiedCountryCodeString:(NSString*)countryCodeString {
    return [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:input
                                                               withSpecifiedRegionCode:[PhoneNumber regionCodeFromCountryCodeString:countryCodeString]];
}

+ (NSString*)bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:(NSString*)input
                                                    withSpecifiedRegionCode:(NSString*)regionCode {
    NBAsYouTypeFormatter* formatter = [[NBAsYouTypeFormatter alloc] initWithRegionCode:regionCode];
    
    NSString* result = input;
    for (NSUInteger i = 0; i < input.length; i++) {
        result = [formatter inputDigit:[input substringWithRange:NSMakeRange(i, 1)]];
    }
    return result;
}

+ (NSString*)regionCodeFromCountryCodeString:(NSString*) countryCodeString {
    NBPhoneNumberUtil* phoneUtil = [NBPhoneNumberUtil sharedInstance];
    NSString* regionCode = [phoneUtil getRegionCodeForCountryCode:@([[countryCodeString substringFromIndex:1] integerValue])];
    return regionCode;
}


+ (PhoneNumber*)tryParsePhoneNumberFromText:(NSString*)text fromRegion:(NSString*)regionCode {
    require(text != nil);
    require(regionCode != nil);
    
    @try {
        return [[PhoneNumber alloc] initFromText:text andRegion:regionCode];
    } @catch (OperationFailed* ex) {
        DDLogError(@"Error parsing phone number from region code");
        return nil;
    }
}

+ (PhoneNumber*)tryParsePhoneNumberFromUserSpecifiedText:(NSString*)text {
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
        return [[PhoneNumber alloc] initFromUserSpecifiedText:text];
    } @catch (OperationFailed* ex) {
        return nil;
    }
}

+ (PhoneNumber*)tryParsePhoneNumberFromE164:(NSString*)text {
    require(text != nil);
	
    @try {
        return [[PhoneNumber alloc] initFromE164:text];
    } @catch (OperationFailed* ex) {
        return nil;
    }
}

- (NSURL*)toSystemDialerURL {
    NSString* link = [NSString stringWithFormat:@"telprompt://%@", self.e164];
    return [NSURL URLWithString:link];
}

- (NSString*)toE164 {
    return self.e164;
}

- (NSNumber*)getCountryCode {
    return self.phoneNumber.countryCode;
}

- (BOOL)isValid {
    return [[NBPhoneNumberUtil sharedInstance] isValidNumber:self.phoneNumber];
}

- (NSString*)localizedDescriptionForUser {
    NBPhoneNumberUtil* phoneUtil = [NBPhoneNumberUtil sharedInstance];

    NSError* formatError = nil;
    NSString* pretty = [phoneUtil format:self.phoneNumber
                            numberFormat:NBEPhoneNumberFormatINTERNATIONAL
                                   error:&formatError];
    
    if (formatError != nil) return self.e164;
    return pretty;
}

- (BOOL)resolvesInternationallyTo:(PhoneNumber*)otherPhoneNumber {
    return [self.toE164 isEqualToString:otherPhoneNumber.toE164];
}

- (NSString*)description {
    return self.e164;
}

- (void)encodeWithCoder:(NSCoder*)encoder {
    [encoder encodeObject:self.phoneNumber forKey:RPDefaultsKeyPhoneNumberString];
    [encoder encodeObject:self.e164 forKey:RPDefaultsKeyPhoneNumberCanonical];
}

- (id)initWithCoder:(NSCoder*)decoder {
    if (self = [super init]) {
        self.phoneNumber = [decoder decodeObjectForKey:RPDefaultsKeyPhoneNumberString];
        self.e164 = [decoder decodeObjectForKey:RPDefaultsKeyPhoneNumberCanonical];
    }
    
    return self;
}

@end
