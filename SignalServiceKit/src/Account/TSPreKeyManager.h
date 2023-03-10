//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@class ChatServiceAuth;
@class SDSAnyWriteTransaction;

typedef NS_CLOSED_ENUM(uint8_t, OWSIdentity);

@interface TSPreKeyManager : NSObject

#pragma mark - State Tracking

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures;

// This should only be called from the TSPreKeyManager.operationQueue
+ (void)refreshPreKeysDidSucceed;

#pragma mark -

@property (class, nonatomic, readonly) NSOperationQueue *operationQueue;

#pragma mark - Check/Request Initiation

+ (void)rotateSignedPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)createPreKeysWithAuth:(ChatServiceAuth *)auth
                      success:(void (^)(void))successHandler
                      failure:(void (^)(NSError *error))failureHandler;
/// Uses implicit auth.
+ (void)createPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)createPreKeysForIdentity:(OWSIdentity)identity
                         success:(void (^)(void))successHandler
                         failure:(void (^)(NSError *error))failureHandler;

+ (void)checkPreKeysIfNecessary;

#if TESTABLE_BUILD
+ (void)checkPreKeysImmediately;

+ (void)storeFakePreKeyUploadFailuresForIdentity:(OWSIdentity)identity;
#endif

@end

NS_ASSUME_NONNULL_END
