//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSPreKeyManager.h"
#import "AppContext.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSIdentityManager.h"
#import "SSKEnvironment.h"
#import "SSKSignedPreKeyStore.h"
#import "TSNetworkManager.h"
#import "TSStorageHeaders.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// Time before deletion of signed prekeys (measured in seconds)
#define kSignedPreKeysDeletionTime (7 * kDayInterval)

// Time before rotation of signed prekeys (measured in seconds)
#define kSignedPreKeyRotationTime (2 * kDayInterval)

// How often we check prekey state on app activation.
#define kPreKeyCheckFrequencySeconds (12 * kHourInterval)

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

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

+ (SSKSignedPreKeyStore *)signedPreKeyStore
{
    return SSKEnvironment.shared.signedPreKeyStore;
}

#pragma mark - State Tracking

+ (BOOL)isAppLockedDueToPreKeyUpdateFailures
{
    // PERF TODO use a single transaction / take in a transaction

    // Only disable message sending if we have failed more than N times
    // over a period of at least M days.
    return ([self.signedPreKeyStore prekeyUpdateFailureCount] >= kMaxPrekeyUpdateFailureCount &&
        [self.signedPreKeyStore firstPrekeyUpdateFailureDate] != nil
        && fabs([[self.signedPreKeyStore firstPrekeyUpdateFailureDate] timeIntervalSinceNow])
            >= kSignedPreKeyUpdateFailureMaxFailureDuration);
}

+ (void)incrementPreKeyUpdateFailureCount
{
    // PERF TODO use a single transaction / take in a transaction

    // Record a prekey update failure.
    NSInteger failureCount = [self.signedPreKeyStore incrementPrekeyUpdateFailureCount];
    OWSLogInfo(@"new failureCount: %ld", (unsigned long)failureCount);

    if (failureCount == 1 || ![self.signedPreKeyStore firstPrekeyUpdateFailureDate]) {
        // If this is the "first" failure, record the timestamp of that
        // failure.
        [self.signedPreKeyStore setFirstPrekeyUpdateFailureDate:[NSDate new]];
    }
}

+ (void)clearPreKeyUpdateFailureCount
{
    [self.signedPreKeyStore clearFirstPrekeyUpdateFailureDate];
    [self.signedPreKeyStore clearPrekeyUpdateFailureCount];
}

+ (void)refreshPreKeysDidSucceed
{
    lastPreKeyCheckTimestamp = [NSDate new];
}

#pragma mark - Check/Request Initiation

+ (NSOperationQueue *)operationQueue
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *operationQueue;

    // PreKey state lives in two places - on the client and on the service.
    // Some of our pre-key operations depend on the service state, e.g. we need to check our one-time-prekey count
    // before we decide to upload new ones. This potentially entails multiple async operations, all of which should
    // complete before starting any other pre-key operation. That's why a dispatch_queue is insufficient for
    // coordinating PreKey operations and instead we use NSOperation's on a serial NSOperationQueue.
    dispatch_once(&onceToken, ^{
        operationQueue = [NSOperationQueue new];
        operationQueue.name = @"TSPreKeyManager";
        operationQueue.maxConcurrentOperationCount = 1;
    });
    return operationQueue;
}

+ (void)checkPreKeysIfNecessary
{
    if (!CurrentAppContext().isMainAppAndActive) {
        return;
    }
    if (!self.tsAccountManager.isRegisteredAndReady) {
        return;
    }

    SSKRefreshPreKeysOperation *refreshOperation = [SSKRefreshPreKeysOperation new];

    __weak SSKRefreshPreKeysOperation *weakRefreshOperation = refreshOperation;
    NSBlockOperation *checkIfRefreshNecessaryOperation = [NSBlockOperation blockOperationWithBlock:^{
        BOOL shouldCheck = (lastPreKeyCheckTimestamp == nil
                            || fabs([lastPreKeyCheckTimestamp timeIntervalSinceNow]) >= kPreKeyCheckFrequencySeconds);
        if (!shouldCheck) {
            [weakRefreshOperation cancel];
        }
    }];

    [refreshOperation addDependency:checkIfRefreshNecessaryOperation];
    
    SSKRotateSignedPreKeyOperation *rotationOperation = [SSKRotateSignedPreKeyOperation new];

    __weak SSKRotateSignedPreKeyOperation *weakRotationOperation = rotationOperation;
    NSBlockOperation *checkIfRotationNecessaryOperation = [NSBlockOperation blockOperationWithBlock:^{
        SignedPreKeyRecord *_Nullable signedPreKey = [self.signedPreKeyStore currentSignedPreKey];

        BOOL shouldCheck
        = !signedPreKey || fabs(signedPreKey.generatedAt.timeIntervalSinceNow) >= kSignedPreKeyRotationTime;
        if (!shouldCheck) {
            [weakRotationOperation cancel];
        }
    }];

    [rotationOperation addDependency:checkIfRotationNecessaryOperation];

    // Order matters here - if we rotated *before* refreshing, we'd risk uploading
    // two SPK's in a row since RefreshPreKeysOperation can also upload a new SPK.
    [checkIfRotationNecessaryOperation addDependency:refreshOperation];

    NSArray<NSOperation *> *operations =
        @[ checkIfRefreshNecessaryOperation, refreshOperation, checkIfRotationNecessaryOperation, rotationOperation ];
    [self.operationQueue addOperations:operations waitUntilFinished:NO];
}

+ (void)createPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(!self.tsAccountManager.isRegisteredAndReady);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SSKCreatePreKeysOperation *operation = [SSKCreatePreKeysOperation new];
        [self.operationQueue addOperations:@[ operation ] waitUntilFinished:YES];

        NSError *_Nullable error = operation.failingError;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failureHandler(error);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                successHandler();
            });
        }
    });
}

+ (void)rotateSignedPreKeyWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(self.tsAccountManager.isRegisteredAndReady);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SSKRotateSignedPreKeyOperation *operation = [SSKRotateSignedPreKeyOperation new];
        [self.operationQueue addOperations:@[ operation ] waitUntilFinished:YES];

        NSError *_Nullable error = operation.failingError;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failureHandler(error);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                successHandler();
            });
        }
    });
}

+ (void)checkPreKeys
{
    if (!CurrentAppContext().isMainApp) {
        return;
    }
    if (!self.tsAccountManager.isRegisteredAndReady) {
        return;
    }

    SSKRefreshPreKeysOperation *operation = [SSKRefreshPreKeysOperation new];
    [self.operationQueue addOperation:operation];
}

+ (void)clearSignedPreKeyRecords {
    NSNumber *_Nullable currentSignedPrekeyId = [self.signedPreKeyStore currentSignedPrekeyId];
    [self clearSignedPreKeyRecordsWithKeyId:currentSignedPrekeyId];
}

+ (void)clearSignedPreKeyRecordsWithKeyId:(NSNumber *_Nullable)keyId
{
    if (!keyId) {
        // currentSignedPreKeyId should only be nil before we've completed registration.
        // We have this guard here for robustness, but we should never get here.
        OWSFailDebug(@"Ignoring request to clear signed preKeys since no keyId was specified");
        return;
    }

    SignedPreKeyRecord *_Nullable currentRecord = [self.signedPreKeyStore loadSignedPreKey:keyId.intValue];
    if (!currentRecord) {
        OWSFailDebug(@"Couldn't find signed prekey for id: %@", keyId);
    }
    NSArray *allSignedPrekeys = [self.signedPreKeyStore loadSignedPreKeys];
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
        [self.signedPreKeyStore removeSignedPreKey:signedPrekey.Id];
    }
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

NS_ASSUME_NONNULL_END
