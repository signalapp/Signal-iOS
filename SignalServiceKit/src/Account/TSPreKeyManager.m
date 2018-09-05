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
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

+ (NSOperationQueue *)operationQueue
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *operationQueue;
    dispatch_once(&onceToken, ^{
        operationQueue = [NSOperationQueue new];
        operationQueue.maxConcurrentOperationCount = 1;
    });
    return operationQueue;
}

+ (void)checkPreKeysIfNecessary
{
    if (!CurrentAppContext().isMainApp) {
        return;
    }
    OWSAssertDebug(CurrentAppContext().isMainAppAndActive);

    if (!TSAccountManager.isRegistered) {
        return;
    }

    SSKRefreshPreKeysOperation *refreshOperation = [SSKRefreshPreKeysOperation new];
    NSBlockOperation *checkIfRefreshNecessaryOperation = [NSBlockOperation blockOperationWithBlock:^{
        BOOL shouldCheck = (lastPreKeyCheckTimestamp == nil
                            || fabs([lastPreKeyCheckTimestamp timeIntervalSinceNow]) >= kPreKeyCheckFrequencySeconds);
        if (!shouldCheck) {
            [refreshOperation cancel];
        }
    }];
    [refreshOperation addDependency:checkIfRefreshNecessaryOperation];
    
    SSKRotateSignedPreKeyOperation *rotationOperation = [SSKRotateSignedPreKeyOperation new];
    NSBlockOperation *checkIfRotationNecessaryOperation = [NSBlockOperation blockOperationWithBlock:^{
        OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
        SignedPreKeyRecord *_Nullable signedPreKey = [primaryStorage currentSignedPreKey];
        
        BOOL shouldCheck
        = !signedPreKey || fabs(signedPreKey.generatedAt.timeIntervalSinceNow) >= kSignedPreKeyRotationTime;
        if (!shouldCheck) {
            [rotationOperation cancel];
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

    SSKRefreshPreKeysOperation *operation = [SSKRefreshPreKeysOperation new];
    [self.operationQueue addOperation:operation];
}

+ (void)clearSignedPreKeyRecords {
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    NSNumber *currentSignedPrekeyId = [primaryStorage currentSignedPrekeyId];
    [self clearSignedPreKeyRecordsWithKeyId:currentSignedPrekeyId];
}

+ (void)clearSignedPreKeyRecordsWithKeyId:(NSNumber *)keyId
{
    if (!keyId) {
        OWSFailDebug(@"Ignoring request to clear signed preKeys since no keyId was specified");
        return;
    }

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
