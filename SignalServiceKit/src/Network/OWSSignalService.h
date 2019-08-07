//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_IsCensorshipCircumventionActiveDidChange;

@class AFHTTPSessionManager;
@class SDSKeyValueStore;
@class TSAccountManager;

@interface OWSSignalService : NSObject

- (SDSKeyValueStore *)keyValueStore;

/// For uploading and downloading avatar assets and attachments
@property (nonatomic, readonly) AFHTTPSessionManager *CDNSessionManager;

/// For backing up and restoring signal account information
@property (nonatomic, readonly) AFHTTPSessionManager *storageServiceSessionManager;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Censorship Circumvention

@property (atomic, readonly) BOOL isCensorshipCircumventionActive;
@property (atomic, readonly) BOOL hasCensoredPhoneNumber;
@property (atomic) BOOL isCensorshipCircumventionManuallyActivated;
@property (atomic) BOOL isCensorshipCircumventionManuallyDisabled;
@property (atomic, nullable) NSString *manualCensorshipCircumventionCountryCode;

/// should only be accessed if censorship circumvention is active.
@property (nonatomic, readonly) NSURL *domainFrontBaseURL;

/// For interacting with the Signal Service
- (AFHTTPSessionManager *)buildSignalServiceSessionManager;

@end

NS_ASSUME_NONNULL_END
