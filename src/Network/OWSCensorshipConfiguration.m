// Created by Michael Kirk on 12/20/16.
// Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSCensorshipConfiguration.h"
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSCensorshipConfigurationFrontingHost = @"https://google.com";
NSString *const OWSCensorshipConfigurationReflectorHost = @"signal-reflector-meek.appspot.com";

@implementation OWSCensorshipConfiguration

- (NSString *)frontingHost
{
    return OWSCensorshipConfigurationFrontingHost;
}

- (NSString *)reflectorHost
{
    return OWSCensorshipConfigurationReflectorHost;
}

- (NSArray<NSString *> *)censoredCountryCodes
{
    // Reports of censorship in:
    // Egypt
    // UAE
    return @[@"+20",
             @"+971"];
}

- (BOOL)isCensoredPhoneNumber:(NSString *)e164PhonNumber
{
    for (NSString *countryCode in self.censoredCountryCodes) {
        if ([e164PhonNumber hasPrefix:countryCode]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
