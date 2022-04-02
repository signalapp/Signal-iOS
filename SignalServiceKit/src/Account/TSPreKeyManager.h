//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(uint8_t, OWSIdentity);

@interface TSPreKeyManager : NSObject

#pragma mark - State Tracking

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures;

+ (void)incrementPreKeyUpdateFailureCount;

+ (void)clearPreKeyUpdateFailureCount;

// This should only be called from the TSPreKeyManager.operationQueue
+ (void)refreshPreKeysDidSucceed;

#pragma mark - Check/Request Initiation

+ (void)rotateSignedPreKeyWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)createPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)createPreKeysForIdentity:(OWSIdentity)identity
                         success:(void (^)(void))successHandler
                         failure:(void (^)(NSError *error))failureHandler;

+ (void)checkPreKeysIfNecessary;

#if TESTABLE_BUILD
+ (void)checkPreKeysImmediately;
#endif

@end

NS_ASSUME_NONNULL_END
