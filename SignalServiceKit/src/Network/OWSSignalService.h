//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_IsCensorshipCircumventionActiveDidChange;

@class AFHTTPSessionManager;
@class OWSCensorshipConfiguration;
@class OWSURLSession;
@class SDSKeyValueStore;
@class TSAccountManager;

@interface OWSSignalService : NSObject

- (SDSKeyValueStore *)keyValueStore;

+ (instancetype)shared;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Censorship Circumvention

@property (atomic, readonly) BOOL isCensorshipCircumventionActive;
@property (atomic, readonly) BOOL hasCensoredPhoneNumber;
@property (atomic) BOOL isCensorshipCircumventionManuallyActivated;
@property (atomic) BOOL isCensorshipCircumventionManuallyDisabled;
@property (atomic, nullable) NSString *manualCensorshipCircumventionCountryCode;

/// should only be accessed if censorship circumvention is active.
@property (nonatomic, readonly) NSURL *domainFrontBaseURL;

- (OWSCensorshipConfiguration *)buildCensorshipConfiguration;

@end

NS_ASSUME_NONNULL_END
