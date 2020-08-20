//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSCensorshipConfiguration.h"
#import "OWSCountryMetadata.h"
#import "OWSError.h"
#import "TSConstants.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSFrontingHost_GoogleEgypt = @"www.google.com.eg";
NSString *const OWSFrontingHost_GoogleUAE = @"www.google.ae";
NSString *const OWSFrontingHost_GoogleOman = @"www.google.com.om";
NSString *const OWSFrontingHost_GoogleQatar = @"www.google.com.qa";
NSString *const OWSFrontingHost_Default = @"www.google.com";

@implementation OWSCensorshipConfiguration

// returns nil if phone number is not known to be censored
+ (nullable instancetype)censorshipConfigurationWithPhoneNumber:(NSString *)e164PhoneNumber
{
    NSString *countryCode = [self censoredCountryCodeWithPhoneNumber:e164PhoneNumber];
    if (countryCode.length == 0) {
        return nil;
    }

    return [self censorshipConfigurationWithCountryCode:countryCode];
}

// returns best censorship configuration for country code. Will return a default if one hasn't
// been specifically configured.
+ (instancetype)censorshipConfigurationWithCountryCode:(NSString *)countryCode
{
    OWSCountryMetadata *countryMetadadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    OWSAssertDebug(countryMetadadata);

    NSString *_Nullable specifiedDomain = countryMetadadata.frontingDomain;
    if (specifiedDomain.length == 0) {
        return self.defaultConfiguration;
    }

    NSString *frontingURLString = [NSString stringWithFormat:@"https://%@", specifiedDomain];
    NSURL *_Nullable baseURL = [NSURL URLWithString:frontingURLString];
    if (baseURL == nil) {
        OWSFailDebug(@"baseURL was unexpectedly nil with specifiedDomain: %@", specifiedDomain);
        return self.defaultConfiguration;
    }
    AFSecurityPolicy *securityPolicy = [self securityPolicyForDomain:specifiedDomain];
    OWSAssertDebug(securityPolicy);

    return [[OWSCensorshipConfiguration alloc] initWithDomainFrontBaseURL:baseURL securityPolicy:securityPolicy];
}

+ (instancetype)defaultConfiguration
{
    NSString *frontingURLString = [NSString stringWithFormat:@"https://%@", OWSFrontingHost_Default];
    NSURL *baseURL = [NSURL URLWithString:frontingURLString];
    AFSecurityPolicy *securityPolicy = [self securityPolicyForDomain:OWSFrontingHost_Default];

    return [[OWSCensorshipConfiguration alloc] initWithDomainFrontBaseURL:baseURL securityPolicy:securityPolicy];
}

- (instancetype)initWithDomainFrontBaseURL:(NSURL *)domainFrontBaseURL securityPolicy:(AFSecurityPolicy *)securityPolicy
{
    OWSAssertDebug(domainFrontBaseURL);
    OWSAssertDebug(securityPolicy);

    self = [super init];
    if (!self) {
        return self;
    }

    _domainFrontBaseURL = domainFrontBaseURL;
    _domainFrontSecurityPolicy = securityPolicy;

    return self;
}

// MARK: Util

+ (NSDictionary<NSString *, NSString *> *)censoredCountryCodes
{
    // The set of countries for which domain fronting should be automatically enabled.
    //
    // If you want to use a domain front other than the default, specify the domain front
    // in OWSCountryMetadata, and ensure we have a Security Policy for that domain in
    // `securityPolicyForDomain:`
    return @{
        // Egypt
        @"+20" : @"EG",
        // Oman
        @"+968" : @"OM",
        // Qatar
        @"+974" : @"QA",
        // UAE
        @"+971" : @"AE",
    };
}

+ (BOOL)isCensoredPhoneNumber:(NSString *)e164PhoneNumber
{
    return [self censoredCountryCodeWithPhoneNumber:e164PhoneNumber].length > 0;
}

// Returns nil if the phone number is not known to be censored
+ (nullable NSString *)censoredCountryCodeWithPhoneNumber:(NSString *)e164PhoneNumber
{
    NSDictionary<NSString *, NSString *> *censoredCountryCodes = self.censoredCountryCodes;

    for (NSString *callingCode in censoredCountryCodes) {
        if ([e164PhoneNumber hasPrefix:callingCode]) {
            return censoredCountryCodes[callingCode];
        }
    }

    return nil;
}

#pragma mark - Reflector Pinning Policy

// When using censorship circumvention, we pin to the fronted domain host.
// Adding a new domain front entails adding a corresponding AFSecurityPolicy
// and pinning to it's CA.
// If the security policy requires new certificates, include them in the SSK bundle
+ (AFSecurityPolicy *)securityPolicyForDomain:(NSString *)domain
{
    if ([domain isEqualToString:OWSFrontingHost_GoogleEgypt]) {
        return self.googlePinningPolicy;
    } else if ([domain isEqualToString:OWSFrontingHost_GoogleQatar]) {
        return self.googlePinningPolicy;
    } else if ([domain isEqualToString:OWSFrontingHost_GoogleOman]) {
        return self.googlePinningPolicy;
    } else if ([domain isEqualToString:OWSFrontingHost_GoogleUAE]) {
        return self.googlePinningPolicy;
    } else {
        OWSLogVerbose(@"domain: %@", domain);
        if ([domain containsString:@".google."]) {
            OWSLogWarn(@"Unknown pinning domain.");
        } else {
            OWSFailDebug(@"Unknown pinning domain.");
        }
        return self.googlePinningPolicy;
    }
}

+ (AFSecurityPolicy *)pinningPolicyWithCertNames:(NSArray<NSString *> *)certNames
{
    NSMutableSet<NSData *> *certificates = [NSMutableSet new];
    for (NSString *certName in certNames) {
        NSError *error;
        NSData *certData = [self certificateDataWithName:certName error:&error];
        if (error) {
            OWSFail(@"reading data for certificate: %@ failed with error: %@", certName, error);
        }

        if (!certData) {
            OWSFail(@"reading data for certificate: %@ failed with error: %@", certName, error);
        }
        [certificates addObject:certData];
    }

    return [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate withPinnedCertificates:certificates];
}

+ (nullable NSData *)certificateDataWithName:(NSString *)name error:(NSError **)error
{
    if (!name.length) {
        NSString *failureDescription = [NSString stringWithFormat:@"%@ expected name with length > 0", self.logTag];
        *error = OWSErrorMakeAssertionError(failureDescription);
        return nil;
    }

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:name ofType:@"crt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString *failureDescription =
            [NSString stringWithFormat:@"%@ Missing certificate for name: %@", self.logTag, name];
        *error = OWSErrorMakeAssertionError(failureDescription);
        return nil;
    }

    NSData *_Nullable certData = [NSData dataWithContentsOfFile:path options:0 error:error];

    if (*error != nil) {
        OWSFailDebug(@"Failed to read cert file with path: %@", path);
        return nil;
    }

    if (certData.length == 0) {
        OWSFailDebug(@"empty certData for name: %@", name);
        return nil;
    }

    OWSLogVerbose(@"read cert data with name: %@ length: %lu", name, (unsigned long)certData.length);
    return certData;
}

+ (AFSecurityPolicy *)yahooViewPinningPolicy_deprecated
{
    static AFSecurityPolicy *securityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // DigiCertGlobalRootG2 - view.yahoo.com
        NSArray<NSString *> *certNames = @[ @"DigiCertSHA2HighAssuranceServerCA" ];
        securityPolicy = [self pinningPolicyWithCertNames:certNames];
    });
    return securityPolicy;
}

+ (AFSecurityPolicy *)souqPinningPolicy_deprecated
{
    static AFSecurityPolicy *securityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // SFSRootCAG2 - cms.souqcdn.com
        NSArray<NSString *> *certNames = @[ @"SFSRootCAG2" ];
        securityPolicy = [self pinningPolicyWithCertNames:certNames];
    });
    return securityPolicy;
}

+ (AFSecurityPolicy *)googlePinningPolicy
{
    static AFSecurityPolicy *securityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // GIAG2 cert plus root certs from pki.goog
        NSArray<NSString *> *certNames = @[ @"GIAG2", @"GSR2", @"GSR4", @"GTSR1", @"GTSR2", @"GTSR3", @"GTSR4" ];
        securityPolicy = [self pinningPolicyWithCertNames:certNames];
    });
    return securityPolicy;
}

@end

NS_ASSUME_NONNULL_END
