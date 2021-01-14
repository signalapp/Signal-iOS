//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSPreKeyManager.h"
#import "AppContext.h"
#import "NSURLSessionDataTask+OWS_HTTP.h"
#import "OWSIdentityManager.h"
#import "SSKEnvironment.h"
#import "SSKSignedPreKeyStore.h"
#import "TSNetworkManager.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SSKPreKeyStore.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// Time before deletion of signed prekeys (measured in seconds)
#define kSignedPreKeysDeletionTime (30 * kDayInterval)

// Time before rotation of signed prekeys (measured in seconds)
#define kSignedPreKeyRotationTime (2 * kDayInterval)

// How often we check prekey state on app activation.
#define kPreKeyCheckFrequencySeconds (12 * kHourInterval)

// Maximum number of failures while updating signed prekeys
// before the message sending is disabled.
static const NSUInteger kMaxPrekeyUpdateFailureCount = 5;

// Maximum amount of time that can elapse without updating signed prekeys
// before the message sending is disabled.
#define kSignedPreKeyUpdateFailureMaxFailureDuration (10 * kDayInterval)

#pragma mark -

@interface TSPreKeyManager ()

@property (atomic, nullable) NSDate *lastPreKeyCheckTimestamp;

@end

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

+ (SSKPreKeyStore *)preKeyStore
{
    return SSKEnvironment.shared.preKeyStore;
}

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (instancetype)shared
{
    static TSPreKeyManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    return instance;
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
    TSPreKeyManager.shared.lastPreKeyCheckTimestamp = [NSDate new];
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
    [self checkPreKeysWithShouldThrottle:YES];
}

#if TESTABLE_BUILD
+ (void)checkPreKeysImmediately
{
    [self checkPreKeysWithShouldThrottle:NO];
}
#endif

+ (void)checkPreKeysWithShouldThrottle:(BOOL)shouldThrottle
{
    if (!CurrentAppContext().isMainAppAndActive) {
        return;
    }
    if (!self.tsAccountManager.isRegisteredAndReady) {
        return;
    }

    // Order matters here - if we rotated *before* refreshing, we'd risk uploading
    // two SPK's in a row since RefreshPreKeysOperation can also upload a new SPK.
    NSMutableArray<NSOperation *> *operations = [NSMutableArray new];

    // Don't rotate or clean up prekeys until all incoming messages
    // have been drained, decrypted and processed.
    MessageProcessingOperation *messageProcessingOperation = [MessageProcessingOperation new];
    [operations addObject:messageProcessingOperation];

    SSKRefreshPreKeysOperation *refreshOperation = [SSKRefreshPreKeysOperation new];

    if (shouldThrottle) {
        __weak SSKRefreshPreKeysOperation *weakRefreshOperation = refreshOperation;
        NSBlockOperation *checkIfRefreshNecessaryOperation = [NSBlockOperation blockOperationWithBlock:^{
            NSDate *_Nullable lastPreKeyCheckTimestamp = TSPreKeyManager.shared.lastPreKeyCheckTimestamp;
            BOOL shouldCheck = (lastPreKeyCheckTimestamp == nil
                || fabs([lastPreKeyCheckTimestamp timeIntervalSinceNow]) >= kPreKeyCheckFrequencySeconds);
            if (!shouldCheck) {
                [weakRefreshOperation cancel];
            }
        }];
        [operations addObject:checkIfRefreshNecessaryOperation];
    }
    [operations addObject:refreshOperation];

    SSKRotateSignedPreKeyOperation *rotationOperation = [SSKRotateSignedPreKeyOperation new];

    if (shouldThrottle) {
        __weak SSKRotateSignedPreKeyOperation *weakRotationOperation = rotationOperation;
        NSBlockOperation *checkIfRotationNecessaryOperation = [NSBlockOperation blockOperationWithBlock:^{
            SignedPreKeyRecord *_Nullable signedPreKey = [self.signedPreKeyStore currentSignedPreKey];

            BOOL shouldCheck
                = !signedPreKey || fabs(signedPreKey.generatedAt.timeIntervalSinceNow) >= kSignedPreKeyRotationTime;
            if (!shouldCheck) {
                [weakRotationOperation cancel];
            }
        }];
        [operations addObject:checkIfRotationNecessaryOperation];
    }
    [operations addObject:rotationOperation];

    // Set up dependencies; we want to perform these operations serially.
    NSOperation *_Nullable lastOperation;
    for (NSOperation *operation in operations) {
        if (lastOperation != nil) {
            [operation addDependency:lastOperation];
        }
        lastOperation = operation;
    }

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

    __block SignedPreKeyRecord *_Nullable currentRecord;
    __block NSArray *allSignedPrekeys;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        currentRecord = [self.signedPreKeyStore loadSignedPreKey:keyId.intValue transaction:transaction];
        allSignedPrekeys = [self.signedPreKeyStore loadSignedPreKeysWithTransaction:transaction];
    }];
    if (!currentRecord) {
        OWSFailDebug(@"Couldn't find signed prekey for id: %@", keyId);
        return;
    }
    NSArray *oldSignedPrekeys
        = (currentRecord != nil ? [self removeCurrentRecord:currentRecord fromRecords:allSignedPrekeys]
                                : allSignedPrekeys);
    
    // Sort the signed prekeys in ascending order of generation time.
    oldSignedPrekeys = [oldSignedPrekeys sortedArrayUsingComparator:^NSComparisonResult(
        SignedPreKeyRecord *left, SignedPreKeyRecord *right) { return [left.generatedAt compare:right.generatedAt]; }];

    NSUInteger oldSignedPreKeyCount = oldSignedPrekeys.count;

    int oldAcceptedSignedPreKeyCount = 0;
    for (SignedPreKeyRecord *signedPrekey in oldSignedPrekeys) {
        if (signedPrekey.wasAcceptedByService) {
            oldAcceptedSignedPreKeyCount++;
        }
    }

    OWSLogInfo(@"oldSignedPreKeyCount: %lu., oldAcceptedSignedPreKeyCount: %lu",
        (unsigned long)oldSignedPreKeyCount,
        (unsigned long)oldAcceptedSignedPreKeyCount);

    // Iterate the signed prekeys in ascending order so that we try to delete older keys first.
    for (SignedPreKeyRecord *signedPrekey in oldSignedPrekeys) {

        OWSLogInfo(@"Considering signed prekey id: %lu., generatedAt: %@, createdAt: %@, wasAcceptedByService: %d",
            (unsigned long)signedPrekey.Id,
            [self formatDate:signedPrekey.generatedAt],
            [self formatDate:signedPrekey.createdAt],
            signedPrekey.wasAcceptedByService);

        // Always keep at least 3 keys, accepted or otherwise.
        if (oldSignedPreKeyCount <= 3) {
            break;
        }

        // Never delete signed prekeys until they are N days old.
        if (fabs([signedPrekey.generatedAt timeIntervalSinceNow]) < kSignedPreKeysDeletionTime) {
            break;
        }

        // We try to keep a minimum of 3 "old, accepted" signed prekeys.
        if (signedPrekey.wasAcceptedByService) {
            if (oldAcceptedSignedPreKeyCount <= 3) {
                break;
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

        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.signedPreKeyStore removeSignedPreKey:signedPrekey.Id transaction:transaction];
        });
    }
}

+ (void)cullPreKeyRecords {
    NSTimeInterval expirationInterval = kDayInterval * 30;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSMutableArray<NSString *> *keys = [[self.preKeyStore.keyStore allKeysWithTransaction:transaction] mutableCopy];
        NSMutableSet<NSString *> *keysToRemove = [NSMutableSet new];
        [Batching loopObjcWithBatchSize:Batching.kDefaultBatchSize
                              loopBlock:^(BOOL *stop) {
                                  NSString *_Nullable key = [keys lastObject];
                                  if (key == nil) {
                                      *stop = YES;
                                      return;
                                  }
                                  [keys removeLastObject];
                                  PreKeyRecord *_Nullable record =
                                      [self.preKeyStore.keyStore getObjectForKey:key transaction:transaction];
                                  if (![record isKindOfClass:[PreKeyRecord class]]) {
                                      OWSFailDebug(@"Unexpected value: %@", [record class]);
                                      return;
                                  }
                                  if (record.createdAt == nil) {
                                      OWSFailDebug(@"Missing createdAt.");
                                      [keysToRemove addObject:key];
                                      return;
                                  }
                                  BOOL shouldRemove = fabs(record.createdAt.timeIntervalSinceNow) > expirationInterval;
                                  if (shouldRemove) {
                                      OWSLogInfo(@"Removing prekey id: %lu., createdAt: %@",
                                          (unsigned long)record.Id,
                                          [self formatDate:record.createdAt]);
                                      [keysToRemove addObject:key];
                                  }
                              }];
        if (keysToRemove.count < 1) {
            return;
        }
        OWSLogInfo(@"Culling prekeys: %lu", (unsigned long) keysToRemove.count);
        for (NSString *key in keysToRemove) {
            [self.preKeyStore.keyStore removeValueForKey:key
                                             transaction:transaction];
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

+ (NSString *)formatDate:(nullable NSDate *)date
{
    return (date != nil ? [self.dateFormatter stringFromDate:date] : @"Unknown");
}

+ (NSDateFormatter *)dateFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setTimeStyle:NSDateFormatterShortStyle];
        [formatter setDateStyle:NSDateFormatterShortStyle];
    });
    return formatter;
}

@end

NS_ASSUME_NONNULL_END
