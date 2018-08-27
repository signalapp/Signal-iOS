//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSPreKeyManager.h"
#import "AppContext.h"
#import "NSDate+OWS.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage+SignedPreKeyStore.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import "TSStorageHeaders.h"

// Time before deletion of signed prekeys (measured in seconds)
#define kSignedPreKeysDeletionTime (7 * kDayInterval)

// Time before rotation of signed prekeys (measured in seconds)
#define kSignedPreKeyRotationTime (2 * kDayInterval)

// How often we check prekey state on app activation.
#define kPreKeyCheckFrequencySeconds (12 * kHourInterval)

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
static const NSUInteger kEphemeralPreKeysMinimumCount = 35;

// This global should only be accessed on prekeyQueue.
static NSDate *lastPreKeyCheckTimestamp = nil;

// Maximum number of failures while updating signed prekeys
// before the message sending is disabled.
static const NSUInteger kMaxPrekeyUpdateFailureCount = 5;

// Maximum amount of time that can elapse without updating signed prekeys
// before the message sending is disabled.
#define kSignedPreKeyUpdateFailureMaxFailureDuration (10 * kDayInterval)

#pragma mark -

@implementation TSPreKeyManager

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures
{
    // Only disable message sending if we have failed more than N times
    // over a period of at least M days.
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    return ([primaryStorage prekeyUpdateFailureCount] >= kMaxPrekeyUpdateFailureCount &&
        [primaryStorage firstPrekeyUpdateFailureDate] != nil
        && fabs([[primaryStorage firstPrekeyUpdateFailureDate] timeIntervalSinceNow])
            >= kSignedPreKeyUpdateFailureMaxFailureDuration);
}

+ (void)incrementPreKeyUpdateFailureCount
{
    // Record a prekey update failure.
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    int failureCount = [primaryStorage incrementPrekeyUpdateFailureCount];
    if (failureCount == 1 || ![primaryStorage firstPrekeyUpdateFailureDate]) {
        // If this is the "first" failure, record the timestamp of that
        // failure.
        [primaryStorage setFirstPrekeyUpdateFailureDate:[NSDate new]];
    }
}

+ (void)clearPreKeyUpdateFailureCount
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    [primaryStorage clearFirstPrekeyUpdateFailureDate];
    [primaryStorage clearPrekeyUpdateFailureCount];
}

// We should never dispatch sync to this queue.
+ (dispatch_queue_t)prekeyQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.prekeyQueue", NULL);
    });
    return queue;
}

+ (void)checkPreKeysIfNecessary
{
    if (!CurrentAppContext().isMainApp) {
        return;
    }
    OWSAssert(CurrentAppContext().isMainAppAndActive);

    // Update the prekey check timestamp.
    dispatch_async(TSPreKeyManager.prekeyQueue, ^{
        BOOL shouldCheck = (lastPreKeyCheckTimestamp == nil
            || fabs([lastPreKeyCheckTimestamp timeIntervalSinceNow]) >= kPreKeyCheckFrequencySeconds);
        if (shouldCheck) {
            // Optimistically mark the prekeys as checked. This
            // de-bounces prekey checks.
            //
            // If the check or key registration fails, the prekeys
            // will be marked as _NOT_ checked.
            //
            // Note: [TSPreKeyManager checkPreKeys] will also
            //       optimistically mark them as checked. This
            //       redundancy is fine and precludes a race
            //       condition.
            lastPreKeyCheckTimestamp = [NSDate date];

            if ([TSAccountManager isRegistered]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [TSPreKeyManager checkPreKeys];
                });
            }
        }
    });
}

+ (void)registerPreKeysWithMode:(RefreshPreKeysMode)mode
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    // We use prekeyQueue to serialize this logic and ensure that only
    // one thread is "registering" or "clearing" prekeys at a time.
    dispatch_async(TSPreKeyManager.prekeyQueue, ^{
        // Mark the prekeys as checked every time we try to register prekeys.
        lastPreKeyCheckTimestamp = [NSDate date];

        RefreshPreKeysMode modeCopy = mode;
        OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
        ECKeyPair *identityKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];

        if (!identityKeyPair) {
            [[OWSIdentityManager sharedManager] generateNewIdentityKey];
            identityKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];

            // Switch modes if necessary.
            modeCopy = RefreshPreKeysMode_SignedAndOneTime;
        }

        SignedPreKeyRecord *signedPreKey = [primaryStorage generateRandomSignedRecord];
        // Store the new signed key immediately, before it is sent to the
        // service to prevent race conditions and other edge cases.
        [primaryStorage storeSignedPreKey:signedPreKey.Id signedPreKeyRecord:signedPreKey];

        NSArray *preKeys = nil;
        TSRequest *request;
        NSString *description;
        if (modeCopy == RefreshPreKeysMode_SignedAndOneTime) {
            description = @"signed and one-time prekeys";
            PreKeyRecord *lastResortPreKey = [primaryStorage getOrGenerateLastResortKey];
            preKeys = [primaryStorage generatePreKeyRecords];
            // Store the new one-time keys immediately, before they are sent to the
            // service to prevent race conditions and other edge cases.
            [primaryStorage storePreKeyRecords:preKeys];

            request = [OWSRequestFactory registerPrekeysRequestWithPrekeyArray:preKeys
                                                                   identityKey:identityKeyPair.publicKey
                                                                  signedPreKey:signedPreKey
                                                              preKeyLastResort:lastResortPreKey];
        } else {
            description = @"just signed prekey";
            request = [OWSRequestFactory registerSignedPrekeyRequestWithSignedPreKeyRecord:signedPreKey];
        }

        [[TSNetworkManager sharedManager] makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                OWSLogInfo(@"%@ Successfully registered %@.", self.logTag, description);

                // Mark signed prekey as accepted by service.
                [signedPreKey markAsAcceptedByService];
                [primaryStorage storeSignedPreKey:signedPreKey.Id signedPreKeyRecord:signedPreKey];

                // On success, update the "current" signed prekey state.
                [primaryStorage setCurrentSignedPrekeyId:signedPreKey.Id];

                successHandler();

                [TSPreKeyManager clearPreKeyUpdateFailureCount];
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                if (!IsNSErrorNetworkFailure(error)) {
                    if (modeCopy == RefreshPreKeysMode_SignedAndOneTime) {
                        OWSProdError([OWSAnalyticsEvents errorPrekeysUpdateFailedSignedAndOnetime]);
                    } else {
                        OWSProdError([OWSAnalyticsEvents errorPrekeysUpdateFailedJustSigned]);
                    }
                }

                // Mark the prekeys as _NOT_ checked on failure.
                [self markPreKeysAsNotChecked];

                failureHandler(error);

                NSInteger statusCode = 0;
                if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
                    statusCode = httpResponse.statusCode;
                }
                if (statusCode >= 400 && statusCode <= 599) {
                    // Only treat 4xx and 5xx errors from the service as failures.
                    // Ignore network failures, for example.
                    [TSPreKeyManager incrementPreKeyUpdateFailureCount];
                }
            }];
    });
}

+ (void)checkPreKeys
{
    if (!CurrentAppContext().isMainApp) {
        return;
    }

    // Optimistically mark the prekeys as checked. This
    // de-bounces prekey checks.
    //
    // If the check or key registration fails, the prekeys
    // will be marked as _NOT_ checked.
    dispatch_async(TSPreKeyManager.prekeyQueue, ^{
        lastPreKeyCheckTimestamp = [NSDate date];
    });

    // We want to update prekeys if either the one-time or signed prekeys need an update, so
    // we check the status of both.
    //
    // Most users will refresh their signed prekeys much more often than their
    // one-time PreKeys, so we use a "signed only" mode to avoid updating the
    // one-time keys in this case.
    //
    // We do not need a "one-time only" mode.
    TSRequest *preKeyCountRequest = [OWSRequestFactory availablePreKeysCountRequest];
    [[TSNetworkManager sharedManager] makeRequest:preKeyCountRequest
        success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
            NSString *preKeyCountKey = @"count";
            NSNumber *count = [responseObject objectForKey:preKeyCountKey];

            BOOL didUpdatePreKeys = NO;
            void (^updatePreKeys)(RefreshPreKeysMode) = ^(RefreshPreKeysMode mode) {
                [self registerPreKeysWithMode:mode
                    success:^{
                        OWSLogInfo(@"%@ New prekeys registered with server.", self.logTag);

                        [self clearSignedPreKeyRecords];
                    }
                    failure:^(NSError *error) {
                        OWSLogWarn(@"%@ Failed to update prekeys with the server: %@", self.logTag, error);
                    }];
            };

            BOOL shouldUpdateOneTimePreKeys = count.integerValue <= kEphemeralPreKeysMinimumCount;

            if (shouldUpdateOneTimePreKeys) {
                OWSLogInfo(
                    @"%@ Updating one-time and signed prekeys due to shortage of one-time prekeys.", self.logTag);
                updatePreKeys(RefreshPreKeysMode_SignedAndOneTime);
                didUpdatePreKeys = YES;
            } else {
                OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
                NSNumber *currentSignedPrekeyId = [primaryStorage currentSignedPrekeyId];
                BOOL shouldUpdateSignedPrekey = NO;
                if (!currentSignedPrekeyId) {
                    OWSLogError(@"Couldn't find current signed prekey id");
                    shouldUpdateSignedPrekey = YES;
                } else {
                    SignedPreKeyRecord *currentRecord =
                        [primaryStorage loadSignedPrekeyOrNil:currentSignedPrekeyId.intValue];
                    if (!currentRecord) {
                        OWSFailDebug(@"%@ %s Couldn't find signed prekey for id: %@",
                            self.logTag,
                            __PRETTY_FUNCTION__,
                            currentSignedPrekeyId);
                        shouldUpdateSignedPrekey = YES;
                    } else {
                        shouldUpdateSignedPrekey
                        = fabs([currentRecord.generatedAt timeIntervalSinceNow]) >= kSignedPreKeyRotationTime;
                    }
                }
                
                if (shouldUpdateSignedPrekey) {
                    OWSLogInfo(@"%@ Updating signed prekey due to rotation period.", self.logTag);
                    updatePreKeys(RefreshPreKeysMode_SignedOnly);
                    didUpdatePreKeys = YES;
                } else {
                    OWSLogDebug(@"%@ Not updating prekeys.", self.logTag);
                }
            }

            if (!didUpdatePreKeys) {
                // If we didn't update the prekeys, our local "current signed key" state should
                // agree with the service's "current signed key" state.  Let's verify that,
                // since it's closely related to the issues we saw with the 2.7.0.10 release.
                TSRequest *currentSignedPreKey = [OWSRequestFactory currentSignedPreKeyRequest];
                [[TSNetworkManager sharedManager] makeRequest:currentSignedPreKey
                    success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
                        NSString *keyIdDictKey = @"keyId";
                        NSNumber *keyId = [responseObject objectForKey:keyIdDictKey];
                        OWSAssert(keyId);

                        OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
                        NSNumber *currentSignedPrekeyId = [primaryStorage currentSignedPrekeyId];

                        if (!keyId || !currentSignedPrekeyId || ![currentSignedPrekeyId isEqualToNumber:keyId]) {
                            OWSLogError(
                                @"%@ Local and service 'current signed prekey ids' did not match. %@ == %@ == %d.",
                                self.logTag,
                                keyId,
                                currentSignedPrekeyId,
                                [currentSignedPrekeyId isEqualToNumber:keyId]);
                        }
                    }
                    failure:^(NSURLSessionDataTask *task, NSError *error) {
                        if (!IsNSErrorNetworkFailure(error)) {
                            OWSProdError([OWSAnalyticsEvents errorPrekeysCurrentSignedPrekeyRequestFailed]);
                        }
                        OWSLogWarn(@"%@ Could not retrieve current signed key from the service.", self.logTag);

                        // Mark the prekeys as _NOT_ checked on failure.
                        [self markPreKeysAsNotChecked];
                    }];
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorPrekeysAvailablePrekeysRequestFailed]);
            }
            OWSLogError(@"%@ Failed to retrieve the number of available prekeys.", self.logTag);

            // Mark the prekeys as _NOT_ checked on failure.
            [self markPreKeysAsNotChecked];
        }];
}

+ (void)markPreKeysAsNotChecked
{
    dispatch_async(TSPreKeyManager.prekeyQueue, ^{
        lastPreKeyCheckTimestamp = nil;
    });
}

+ (void)clearSignedPreKeyRecords {
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    NSNumber *currentSignedPrekeyId = [primaryStorage currentSignedPrekeyId];
    [self clearSignedPreKeyRecordsWithKeyId:currentSignedPrekeyId success:nil];
}

+ (void)clearSignedPreKeyRecordsWithKeyId:(NSNumber *)keyId success:(void (^_Nullable)(void))successHandler
{
    if (!keyId) {
        OWSFailDebug(@"%@ Ignoring request to clear signed preKeys since no keyId was specified", self.logTag);
        return;
    }

    // We use prekeyQueue to serialize this logic and ensure that only
    // one thread is "registering" or "clearing" prekeys at a time.
    dispatch_async(TSPreKeyManager.prekeyQueue, ^{
        OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
        SignedPreKeyRecord *currentRecord = [primaryStorage loadSignedPrekeyOrNil:keyId.intValue];
        if (!currentRecord) {
            OWSFailDebug(@"Couldn't find signed prekey for id: %@", keyId);
        }
        NSArray *allSignedPrekeys = [primaryStorage loadSignedPreKeys];
        NSArray *oldSignedPrekeys
            = (currentRecord != nil ? [self removeCurrentRecord:currentRecord fromRecords:allSignedPrekeys]
                                    : allSignedPrekeys);

        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.timeStyle = NSDateFormatterMediumStyle;
        dateFormatter.locale = [NSLocale systemLocale];

        // Sort the signed prekeys in ascending order of generation time.
        oldSignedPrekeys = [oldSignedPrekeys sortedArrayUsingComparator:^NSComparisonResult(
            SignedPreKeyRecord *_Nonnull left, SignedPreKeyRecord *_Nonnull right) {
            return [left.generatedAt compare:right.generatedAt];
        }];

        NSUInteger oldSignedPreKeyCount = oldSignedPrekeys.count;

        int oldAcceptedSignedPreKeyCount = 0;
        for (SignedPreKeyRecord *signedPrekey in oldSignedPrekeys) {
            if (signedPrekey.wasAcceptedByService) {
                oldAcceptedSignedPreKeyCount++;
            }
        }

        // Iterate the signed prekeys in ascending order so that we try to delete older keys first.
        for (SignedPreKeyRecord *signedPrekey in oldSignedPrekeys) {
            // Always keep at least 3 keys, accepted or otherwise.
            if (oldSignedPreKeyCount <= 3) {
                continue;
            }

            // Never delete signed prekeys until they are N days old.
            if (fabs([signedPrekey.generatedAt timeIntervalSinceNow]) < kSignedPreKeysDeletionTime) {
                continue;
            }

            // We try to keep a minimum of 3 "old, accepted" signed prekeys.
            if (signedPrekey.wasAcceptedByService) {
                if (oldAcceptedSignedPreKeyCount <= 3) {
                    continue;
                } else {
                    oldAcceptedSignedPreKeyCount--;
                }
            }

            if (signedPrekey.wasAcceptedByService) {
                OWSProdInfo([OWSAnalyticsEvents prekeysDeletedOldAcceptedSignedPrekey]);
            } else {
                OWSProdInfo([OWSAnalyticsEvents prekeysDeletedOldUnacceptedSignedPrekey]);
            }

            oldSignedPreKeyCount--;
            [primaryStorage removeSignedPreKey:signedPrekey.Id];
        }

        if (successHandler) {
            successHandler();
        }
    });
}

+ (NSArray *)removeCurrentRecord:(SignedPreKeyRecord *)currentRecord fromRecords:(NSArray *)allRecords {
    NSMutableArray *oldRecords = [NSMutableArray array];

    for (SignedPreKeyRecord *record in allRecords) {
        if (currentRecord.Id != record.Id) {
            [oldRecords addObject:record];
        }
    }

    return oldRecords;
}

@end
