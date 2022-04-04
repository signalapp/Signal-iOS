//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "TSPreKeyManager.h"
#import "AppContext.h"
#import "HTTPUtils.h"
#import "OWSIdentityManager.h"
#import "SSKEnvironment.h"
#import "SSKPreKeyStore.h"
#import "SSKSignedPreKeyStore.h"
#import "SignedPrekeyRecord.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

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

static BOOL needsSignedPreKeyRotation(OWSIdentity identity, SDSAnyReadTransaction *transaction)
{
    SSKSignedPreKeyStore *store = [SSKEnvironment signalProtocolStoreForIdentity:identity].signedPreKeyStore;
    // Only disable message sending if we have failed more than N times...
    if ([store prekeyUpdateFailureCountWithTransaction:transaction] < kMaxPrekeyUpdateFailureCount) {
        return NO;
    }
    // ...over a period of at least M days.
    NSDate *_Nullable firstFailureDate = [store firstPrekeyUpdateFailureDateWithTransaction:transaction];
    // If firstFailureDate is nil, the time interval will be zero.
    return fabs(firstFailureDate.timeIntervalSinceNow) >= kSignedPreKeyUpdateFailureMaxFailureDuration;
}

#pragma mark -

@interface TSPreKeyManager ()

@property (atomic, nullable) NSDate *lastPreKeyCheckTimestamp;

@end

#pragma mark -

@implementation TSPreKeyManager

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
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = needsSignedPreKeyRotation(OWSIdentityACI, transaction)
            || needsSignedPreKeyRotation(OWSIdentityPNI, transaction);
    }];
    return result;
}

#if TESTABLE_BUILD
+ (void)storeFakePreKeyUploadFailuresForIdentity:(OWSIdentity)identity
{
    SSKSignedPreKeyStore *store = [self signalProtocolStoreForIdentity:identity].signedPreKeyStore;
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSDate *firstFailureDate = [NSDate dateWithTimeIntervalSinceNow:-kSignedPreKeyUpdateFailureMaxFailureDuration];
        [store setPrekeyUpdateFailureCount:kMaxPrekeyUpdateFailureCount
                          firstFailureDate:firstFailureDate
                               transaction:transaction];
    });
}
#endif

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
    // PNI TODO: handle PNI pre-keys too.
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

    SSKRotateSignedPreKeyOperation *rotationOperation =
        [[SSKRotateSignedPreKeyOperation alloc] initForIdentity:OWSIdentityACI];

    if (shouldThrottle) {
        __weak SSKRotateSignedPreKeyOperation *weakRotationOperation = rotationOperation;
        NSBlockOperation *checkIfRotationNecessaryOperation = [NSBlockOperation blockOperationWithBlock:^{
            SSKSignedPreKeyStore *signedPreKeyStore =
                [self signalProtocolStoreForIdentity:OWSIdentityACI].signedPreKeyStore;
            SignedPreKeyRecord *_Nullable signedPreKey = [signedPreKeyStore currentSignedPreKey];

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
        SSKCreatePreKeysOperation *aciOp = [[SSKCreatePreKeysOperation alloc] initForIdentity:OWSIdentityACI];
        SSKCreatePreKeysOperation *pniOp = [[SSKCreatePreKeysOperation alloc] initForIdentity:OWSIdentityPNI];
        [self.operationQueue addOperations:@[ aciOp, pniOp ] waitUntilFinished:YES];

        NSError *_Nullable error = aciOp.failingError ?: pniOp.failingError;
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

+ (void)createPreKeysForIdentity:(OWSIdentity)identity
                         success:(void (^)(void))successHandler
                         failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(self.tsAccountManager.isRegisteredAndReady);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SSKCreatePreKeysOperation *op = [[SSKCreatePreKeysOperation alloc] initForIdentity:identity];
        [self.operationQueue addOperations:@[ op ] waitUntilFinished:YES];

        NSError *_Nullable error = op.failingError;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ failureHandler(error); });
        } else {
            dispatch_async(dispatch_get_main_queue(), successHandler);
        }
    });
}

+ (void)rotateSignedPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(self.tsAccountManager.isRegisteredAndReady);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SSKRotateSignedPreKeyOperation *aciOp = [[SSKRotateSignedPreKeyOperation alloc] initForIdentity:OWSIdentityACI];
        SSKRotateSignedPreKeyOperation *pniOp = [[SSKRotateSignedPreKeyOperation alloc] initForIdentity:OWSIdentityPNI];
        [self.operationQueue addOperations:@[ aciOp, pniOp ] waitUntilFinished:YES];

        NSError *_Nullable error = aciOp.failingError ?: pniOp.failingError;
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

@end

NS_ASSUME_NONNULL_END
