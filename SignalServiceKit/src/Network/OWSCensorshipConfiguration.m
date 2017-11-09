//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCensorshipConfiguration.h"
#import "TSConstants.h"
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCensorshipConfiguration

- (NSString *)frontingHost:(NSString *)e164PhoneNumber
{
    OWSAssert(e164PhoneNumber.length > 0);

    NSString *domain = nil;
    for (NSString *countryCode in self.censoredCountryCodes) {
        if ([e164PhoneNumber hasPrefix:countryCode]) {
            domain = self.censoredCountryCodes[countryCode];
        }
    }

    // Fronting should only be auto-activated for countries specified in censoredCountryCodes,
    // all of which have a domain specified.  However users can also manually enable
    // censorship circumvention.
    if (!domain) {
        domain = @"google.com";
    }
    
    return [@"https://" stringByAppendingString:domain];
}

- (NSString *)signalServiceReflectorHost
{
    return textSecureServiceReflectorHost;
}

- (NSString *)CDNReflectorHost
{
    return textSecureCDNReflectorHost;
}

- (NSDictionary<NSString *, NSString *> *)censoredCountryCodes
{
    // The set of countries for which domain fronting should be used.
    //
    // For each country, we should add the appropriate google domain,
    // per:  https://en.wikipedia.org/wiki/List_of_Google_domains
    //
    // If we ever use any non-google domains for domain fronting,
    // remember to:
    //
    // a) Add the appropriate pinning certificate(s) in
    //    SignalServiceKit.podspec.
    // b) Update signalServiceReflectorHost accordingly.
    return @{
             // Egypt
             @"+20": @"google.com.eg",
             // Oman
             @"+968": @"google.com.om",
             // Qatar
             @"+974": @"google.com.qa",
             // UAE
             @"+971": @"google.ae",
             };
}

- (BOOL)isCensoredPhoneNumber:(NSString *)e164PhoneNumber
{
    for (NSString *countryCode in self.censoredCountryCodes) {
        if ([e164PhoneNumber hasPrefix:countryCode]) {
            return YES;
        }
    }
    return NO;
}

@end

NS_ASSUME_NONNULL_END
