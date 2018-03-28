//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AFSecurityPolicy;

extern NSString *const OWSCensorshipConfiguration_SouqFrontingHost;
extern NSString *const OWSCensorshipConfiguration_YahooViewFrontingHost;
extern NSString *const OWSCensorshipConfiguration_DefaultFrontingHost;

@interface OWSCensorshipConfiguration : NSObject

// returns nil if phone number is not known to be censored
+ (nullable instancetype)censorshipConfigurationWithPhoneNumber:(NSString *)e164PhoneNumber;

// returns best censorship configuration for country code. Will return a default if one hasn't
// been specifically configured.
+ (instancetype)censorshipConfigurationWithCountryCode:(NSString *)countryCode;

+ (BOOL)isCensoredPhoneNumber:(NSString *)e164PhoneNumber;

@property (nonatomic, readonly) NSString *signalServiceReflectorHost;
@property (nonatomic, readonly) NSString *CDNReflectorHost;
@property (nonatomic, readonly) NSURL *domainFrontBaseURL;
@property (nonatomic, readonly) AFSecurityPolicy *domainFrontSecurityPolicy;

@end

NS_ASSUME_NONNULL_END
