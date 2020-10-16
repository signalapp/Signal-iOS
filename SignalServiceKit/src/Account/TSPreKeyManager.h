//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSPreKeyManager : NSObject

#pragma mark - State Tracking

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures;

+ (void)incrementPreKeyUpdateFailureCount;

+ (void)clearPreKeyUpdateFailureCount;

+ (void)clearSignedPreKeyRecords;

+ (void)cullPreKeyRecords;

// This should only be called from the TSPreKeyManager.operationQueue
+ (void)refreshPreKeysDidSucceed;

#pragma mark - Check/Request Initiation

+ (void)rotateSignedPreKeyWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)createPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)checkPreKeysIfNecessary;

#if TESTABLE_BUILD
+ (void)checkPreKeysImmediately;
#endif

@end

NS_ASSUME_NONNULL_END
