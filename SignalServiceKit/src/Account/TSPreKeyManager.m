//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSPreKeyManager.h"
#import "NSDate+OWS.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSIdentityManager.h"
#import "OWSQueues.h"
#import "TSNetworkManager.h"
#import "TSRegisterSignedPrekeyRequest.h"
#import "TSStorageHeaders.h"
#import "TSStorageManager+SignedPreKeyStore.h"

NS_ASSUME_NONNULL_BEGIN

// Time before deletion of signed prekeys (measured in seconds)
//
// Currently we retain signed prekeys for at least 7 days.
static const NSTimeInterval kSignedPreKeysDeletionTime = 7 * kDayInterval;

// Time before rotation of signed prekeys (measured in seconds)
//
// Currently we rotate signed prekeys every 2 days (48 hours).
static const NSTimeInterval kSignedPreKeyRotationTime = 2 * kDayInterval;

// How often we check prekey state on app activation.
//
// Currently we check prekey state every 12 hours.
static const NSTimeInterval kPreKeyCheckSlowFrequencySeconds = 12 * kHourInterval;

// How often we check prekey state on receiving a PreKeyWhisperMessage.
//
// Currently we check prekey state every 2 minutes.
static const NSTimeInterval kPreKeyCheckFastFrequencySeconds = 2 * kMinuteInterval;

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
static const NSUInteger kEphemeralPreKeysMinimumCount = 35;

// Maximum number of failures while updating signed prekeys
// before the message sending is disabled.
static const NSUInteger kMaxPrekeyUpdateFailureCount = 5;

// Maximum amount of time that can elapse without updating signed prekeys
// before the message sending is disabled.
//
// Current value is 10 days (240 hours).
static const NSTimeInterval kSignedPreKeyUpdateFailureMaxFailureDuration = 10 * kDayInterval;

#pragma mark -

@interface TSPreKeyManager ()

// This property should only be accessed on serialQueue.
@property (atomic) NSDate *lastPreKeyCheckTimestamp;

@end

#pragma mark -

@implementation TSPreKeyManager

+ (instancetype)sharedManager
{
    static TSPreKeyManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    [self observeNotifications];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures
{
    // Only disable message sending if we have failed more than N times
    // over a period of at least M days.
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    return ([storageManager prekeyUpdateFailureCount] >= kMaxPrekeyUpdateFailureCount &&
        [storageManager firstPrekeyUpdateFailureDate] != nil
        && fabs([[storageManager firstPrekeyUpdateFailureDate] timeIntervalSinceNow])
            >= kSignedPreKeyUpdateFailureMaxFailureDuration);
}

+ (void)incrementPreKeyUpdateFailureCount
{
    // Record a prekey update failure.
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    int failureCount = [storageManager incrementPrekeyUpdateFailureCount];
    if (failureCount == 1 || ![storageManager firstPrekeyUpdateFailureDate]) {
        // If this is the "first" failure, record the timestamp of that
        // failure.
        [storageManager setFirstPrekeyUpdateFailureDate:[NSDate new]];
    }
}

+ (void)clearPreKeyUpdateFailureCount
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager clearFirstPrekeyUpdateFailureDate];
    [storageManager clearPrekeyUpdateFailureCount];
}

// We should never dispatch sync to this queue.
+ (dispatch_queue_t)serialQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.serialQueue", NULL);
    });
    return queue;
}

+ (void)registerPreKeysWithMode:(RefreshPreKeysMode)mode
                        success:(void (^)())successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    [[self sharedManager] registerPreKeysWithMode:mode success:successHandler failure:failureHandler];
}

- (void)registerPreKeysWithMode:(RefreshPreKeysMode)mode
                        success:(void (^)())successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    // We use serialQueue to serialize this logic and ensure that only
    // one thread is "registering" or "clearing" prekeys at a time.
    dispatch_async(TSPreKeyManager.serialQueue, ^{
        // Mark the prekeys as checked every time we try to register prekeys.
        self.lastPreKeyCheckTimestamp = [NSDate date];

        RefreshPreKeysMode modeCopy = mode;
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        ECKeyPair *identityKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];

        if (!identityKeyPair) {
            [[OWSIdentityManager sharedManager] generateNewIdentityKey];
            identityKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];

            // Switch modes if necessary.
            modeCopy = RefreshPreKeysMode_SignedAndOneTime;
        }

        SignedPreKeyRecord *signedPreKey = [storageManager generateRandomSignedRecord];
        // Store the new signed key immediately, before it is sent to the
        // service to prevent race conditions and other edge cases.
        [storageManager storeSignedPreKey:signedPreKey.Id signedPreKeyRecord:signedPreKey];

        NSArray *preKeys = nil;
        TSRequest *request;
        NSString *description;
        if (modeCopy == RefreshPreKeysMode_SignedAndOneTime) {
            description = @"signed and one-time prekeys";
            PreKeyRecord *lastResortPreKey = [storageManager getOrGenerateLastResortKey];
            preKeys = [storageManager generatePreKeyRecords];
            // Store the new one-time keys immediately, before they are sent to the
            // service to prevent race conditions and other edge cases.
            [storageManager storePreKeyRecords:preKeys];

            request = [[TSRegisterPrekeysRequest alloc]
                initWithPrekeyArray:preKeys
                        identityKey:identityKeyPair.publicKey
                 signedPreKeyRecord:signedPreKey
                   preKeyLastResort:lastResortPreKey];
        } else {
            description = @"just signed prekey";
            request = [[TSRegisterSignedPrekeyRequest alloc] initWithSignedPreKeyRecord:signedPreKey];
        }

        [[TSNetworkManager sharedManager] makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                DDLogInfo(@"%@ Successfully registered %@.", self.tag, description);

                // Mark signed prekey as accepted by service.
                [signedPreKey markAsAcceptedByService];
                [storageManager storeSignedPreKey:signedPreKey.Id signedPreKeyRecord:signedPreKey];

                // On success, update the "current" signed prekey state.
                [storageManager setCurrentSignedPrekeyId:signedPreKey.Id];

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

// This method is called whenever the app activates and is less insistent.
//
// Under normal circumstances, we don't need to check that often.
+ (void)checkPreKeysOnActivation
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert([UIApplication sharedApplication].applicationState == UIApplicationStateActive);

    [self checkPreKeysWithMaxFrequency:kPreKeyCheckSlowFrequencySeconds];
}

// This method is called whenever the app receives a PreKeyWhisperMessage and is more insistent.
//
// If a user was barraged by PreKeyWhisperMessages, we want to check much more often to avoid
// one-time prekey exhaustion.  We still want to throttle though, since we might just be
// receiving PreKeyWhisperMessage all signed with the same one-time prekey.
+ (void)didReceivePreKeyWhisperMessage
{
    [self checkPreKeysWithMaxFrequency:kPreKeyCheckFastFrequencySeconds];
}

+ (void)checkPreKeysWithMaxFrequency:(NSTimeInterval)maxFrequency
{
    [[TSAccountManager sharedInstance] ifRegistered:YES
                                           runAsync:^{
                                               dispatch_async(TSPreKeyManager.serialQueue, ^{
                                                   [self.sharedManager checkPreKeysWithMaxFrequency:maxFrequency];
                                               });
                                           }];
}

- (void)checkPreKeysWithMaxFrequency:(NSTimeInterval)maxFrequency
{
    AssertOnDispatchQueue(TSPreKeyManager.serialQueue);

    // Update the prekey check timestamp.
    BOOL shouldCheck = (self.lastPreKeyCheckTimestamp == nil
        || fabs([self.lastPreKeyCheckTimestamp timeIntervalSinceNow]) >= maxFrequency);
    if (!shouldCheck) {
        return;
    }

    // Optimistically mark the prekeys as checked. This
    // de-bounces prekey checks.
    //
    // If the check or key registration fails, the prekeys
    // will be marked as _NOT_ checked.
    self.lastPreKeyCheckTimestamp = [NSDate date];

    // We want to update prekeys if either the one-time or signed prekeys need an update, so
    // we check the status of both.
    //
    // Most users will refresh their signed prekeys much more often than their
    // one-time PreKeys, so we use a "signed only" mode to avoid updating the
    // one-time keys in this case.
    //
    // We do not need a "one-time only" mode.
    TSAvailablePreKeysCountRequest *preKeyCountRequest = [[TSAvailablePreKeysCountRequest alloc] init];
    [[TSNetworkManager sharedManager] makeRequest:preKeyCountRequest
        success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
            NSString *preKeyCountKey = @"count";
            NSNumber *count = [responseObject objectForKey:preKeyCountKey];

            BOOL didUpdatePreKeys = NO;
            void (^updatePreKeys)(RefreshPreKeysMode) = ^(RefreshPreKeysMode mode) {
                [self registerPreKeysWithMode:mode
                    success:^{
                        DDLogInfo(@"%@ New prekeys registered with server.", self.tag);

                        [self clearSignedPreKeyRecords];
                    }
                    failure:^(NSError *error) {
                        DDLogWarn(@"%@ Failed to update prekeys with the server: %@", self.tag, error);

                        // Mark the prekeys as _NOT_ checked on failure.
                        [self markPreKeysAsNotChecked];
                    }];
            };

            BOOL shouldUpdateOneTimePreKeys = count.integerValue <= kEphemeralPreKeysMinimumCount;

            if (shouldUpdateOneTimePreKeys) {
                DDLogInfo(@"%@ Updating one-time and signed prekeys due to shortage of one-time prekeys.", self.tag);
                updatePreKeys(RefreshPreKeysMode_SignedAndOneTime);
                didUpdatePreKeys = YES;
            } else {
                TSStorageManager *storageManager = [TSStorageManager sharedManager];
                NSNumber *currentSignedPrekeyId = [storageManager currentSignedPrekeyId];
                BOOL shouldUpdateSignedPrekey = NO;
                if (!currentSignedPrekeyId) {
                    DDLogError(@"%@ %s Couldn't find current signed prekey id", self.tag, __PRETTY_FUNCTION__);
                    shouldUpdateSignedPrekey = YES;
                } else {
                    SignedPreKeyRecord *currentRecord = [storageManager loadSignedPrekeyOrNil:currentSignedPrekeyId.intValue];
                    if (!currentRecord) {
                        DDLogError(@"%@ %s Couldn't find signed prekey for id: %@", self.tag, __PRETTY_FUNCTION__, currentSignedPrekeyId);
                        OWSAssert(0);
                        shouldUpdateSignedPrekey = YES;
                    } else {
                        shouldUpdateSignedPrekey
                        = fabs([currentRecord.generatedAt timeIntervalSinceNow]) >= kSignedPreKeyRotationTime;
                    }
                }
                
                if (shouldUpdateSignedPrekey) {
                    DDLogInfo(@"%@ Updating signed prekey due to rotation period.", self.tag);
                    updatePreKeys(RefreshPreKeysMode_SignedOnly);
                    didUpdatePreKeys = YES;
                } else {
                    DDLogDebug(@"%@ Not updating prekeys.", self.tag);
                }
            }

            if (!didUpdatePreKeys) {
                // If we didn't update the prekeys, our local "current signed key" state should
                // agree with the service's "current signed key" state.  Let's verify that,
                // since it's closely related to the issues we saw with the 2.7.0.10 release.
                TSRequest *currentSignedPreKey = [[TSCurrentSignedPreKeyRequest alloc] init];
                [[TSNetworkManager sharedManager] makeRequest:currentSignedPreKey
                    success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
                        NSString *keyIdDictKey = @"keyId";
                        NSNumber *keyId = [responseObject objectForKey:keyIdDictKey];
                        OWSAssert(keyId);

                        TSStorageManager *storageManager = [TSStorageManager sharedManager];
                        NSNumber *currentSignedPrekeyId = [storageManager currentSignedPrekeyId];

                        if (!keyId || !currentSignedPrekeyId || ![currentSignedPrekeyId isEqualToNumber:keyId]) {
                            DDLogError(
                                @"%@ Local and service 'current signed prekey ids' did not match. %@ == %@ == %d.",
                                self.tag,
                                keyId,
                                currentSignedPrekeyId,
                                [currentSignedPrekeyId isEqualToNumber:keyId]);
                        }
                    }
                    failure:^(NSURLSessionDataTask *task, NSError *error) {
                        if (!IsNSErrorNetworkFailure(error)) {
                            OWSProdError([OWSAnalyticsEvents errorPrekeysCurrentSignedPrekeyRequestFailed]);
                        }
                        DDLogWarn(@"%@ Could not retrieve current signed key from the service.", self.tag);

                        // Mark the prekeys as _NOT_ checked on failure.
                        [self markPreKeysAsNotChecked];
                    }];
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorPrekeysAvailablePrekeysRequestFailed]);
            }
            DDLogError(@"%@ Failed to retrieve the number of available prekeys.", self.tag);

            // Mark the prekeys as _NOT_ checked on failure.
            [self markPreKeysAsNotChecked];
        }];
}

- (void)markPreKeysAsNotChecked
{
    dispatch_async(TSPreKeyManager.serialQueue, ^{
        self.lastPreKeyCheckTimestamp = nil;
    });
}

- (void)clearSignedPreKeyRecords
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    NSNumber *currentSignedPrekeyId = [storageManager currentSignedPrekeyId];
    [self clearSignedPreKeyRecordsWithKeyId:currentSignedPrekeyId success:nil];
}

- (void)clearSignedPreKeyRecordsWithKeyId:(NSNumber *)keyId success:(void (^_Nullable)())successHandler
{
    if (!keyId) {
        OWSAssert(NO);
        DDLogError(@"%@ Ignoring request to clear signed preKeys since no keyId was specified", self.tag);
        return;
    }

    // We use serialQueue to serialize this logic and ensure that only
    // one thread is "registering" or "clearing" prekeys at a time.
    dispatch_async(TSPreKeyManager.serialQueue, ^{
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        SignedPreKeyRecord *currentRecord = [storageManager loadSignedPrekeyOrNil:keyId.intValue];
        if (!currentRecord) {
            DDLogError(@"%@ %s Couldn't find signed prekey for id: %@", self.tag, __PRETTY_FUNCTION__, keyId);
            OWSAssert(0);
        }
        NSArray *allSignedPrekeys = [storageManager loadSignedPreKeys];
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
            [storageManager removeSignedPreKey:signedPrekey.Id];
        }

        if (successHandler) {
            successHandler();
        }
    });
}

- (NSArray *)removeCurrentRecord:(SignedPreKeyRecord *)currentRecord fromRecords:(NSArray *)allRecords
{
    NSMutableArray *oldRecords = [NSMutableArray array];

    for (SignedPreKeyRecord *record in allRecords) {
        if (currentRecord.Id != record.Id) {
            [oldRecords addObject:record];
        }
    }

    return oldRecords;
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysOnActivation];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
