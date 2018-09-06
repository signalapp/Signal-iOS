//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"

@interface TSPreKeyManager : NSObject

#pragma mark - State Tracking

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures;

+ (void)incrementPreKeyUpdateFailureCount;

+ (void)clearPreKeyUpdateFailureCount;

+ (void)clearSignedPreKeyRecords;

// This should only be called from the TSPreKeyManager.operationQueue
+ (void)refreshPreKeysDidSucceed;

#pragma mark - Check/Request Initiation

+ (void)rotateSignedPreKeyWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)createPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)checkPreKeys;

+ (void)checkPreKeysIfNecessary;

@end
