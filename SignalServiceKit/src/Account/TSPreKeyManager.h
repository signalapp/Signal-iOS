//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"

typedef NS_ENUM(NSInteger, RefreshPreKeysMode) {
    // Refresh the signed prekey AND the one-time prekeys.
    RefreshPreKeysMode_SignedAndOneTime,
    // Only refresh the signed prekey, which should happen around every 48 hours.
    //
    // Most users will refresh their signed prekeys much more often than their
    // one-time prekeys, so we use a "signed only" mode to avoid updating the
    // one-time keys in this case.
    //
    // We do not need a "one-time only" mode.
    RefreshPreKeysMode_SignedOnly,
};

@interface TSPreKeyManager : NSObject

#pragma mark - State Tracking

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures;

+ (void)incrementPreKeyUpdateFailureCount;

+ (void)clearPreKeyUpdateFailureCount;

+ (void)clearSignedPreKeyRecords;

#pragma mark - Check/Request Initiation

+ (void)rotateSignedPreKeyWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)createPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler;

+ (void)checkPreKeys;

+ (void)checkPreKeysIfNecessary;

@end
