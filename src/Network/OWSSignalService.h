//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_IsCensorshipCircumventionActiveDidChange;

@class TSStorageManager;
@class TSAccountManager;
@class AFHTTPSessionManager;

@interface OWSSignalService : NSObject

@property (nonatomic, readonly) AFHTTPSessionManager *HTTPSessionManager;

@property (atomic, readonly) BOOL isCensorshipCircumventionActive;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)isCensorshipCircumventionManuallyActivated;
- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value;

@end

NS_ASSUME_NONNULL_END
