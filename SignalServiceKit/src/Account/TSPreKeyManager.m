//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSPreKeyManager.h"
#import "AppContext.h"
#import "HTTPUtils.h"
#import "OWSIdentityManager.h"
#import "SSKPreKeyStore.h"
#import "SSKSignedPreKeyStore.h"
#import "SignedPrekeyRecord.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// How often we check prekey state on app activation.
#define kPreKeyCheckFrequencySeconds (12 * kHourInterval)

// Maximum number of failures while updating signed prekeys
// before the message sending is disabled.
static const NSInteger kMaxPrekeyUpdateFailureCount = 5;

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

#pragma mark -

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

#pragma mark - Check/Request Initiation

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

    NSMutableArray<NSOperation *> *operations = [NSMutableArray new];

    // Don't rotate or clean up prekeys until all incoming messages
    // have been drained, decrypted and processed.
    MessageProcessingOperation *messageProcessingOperation = [MessageProcessingOperation new];
    [operations addObject:messageProcessingOperation];

    NSDate *_Nullable lastPreKeyCheckTimestamp = TSPreKeyManager.shared.lastPreKeyCheckTimestamp;
    BOOL shouldRefreshOneTimePreKeys = !shouldThrottle || lastPreKeyCheckTimestamp == nil
        || fabs([lastPreKeyCheckTimestamp timeIntervalSinceNow]) >= kPreKeyCheckFrequencySeconds;

    void (^addOperationsForIdentity)(OWSIdentity) = ^(OWSIdentity identity) {
        NSOperation *refreshOperation = nil;
        if (shouldRefreshOneTimePreKeys) {
            refreshOperation = [[SSKRefreshPreKeysOperation alloc] initForIdentity:identity
                                                         shouldRefreshSignedPreKey:true];
            [refreshOperation addDependency:messageProcessingOperation];
            [operations addObject:refreshOperation];
        }

        // Order matters here - if we rotated *before* refreshing, we'd risk uploading
        // two SPK's in a row since RefreshPreKeysOperation can also upload a new SPK.
        NSOperation *rotationOperation = [[SSKRotateSignedPreKeyOperation alloc] initForIdentity:identity
                                                                              shouldSkipIfRecent:shouldThrottle];
        [rotationOperation addDependency:messageProcessingOperation];
        if (shouldRefreshOneTimePreKeys) {
            OWSAssertDebug(refreshOperation);
            [rotationOperation addDependency:refreshOperation];
        }
        [operations addObject:rotationOperation];
    };

    addOperationsForIdentity(OWSIdentityACI);
    addOperationsForIdentity(OWSIdentityPNI);

    [self.operationQueue addOperations:operations waitUntilFinished:NO];
}

+ (void)createPreKeysWithSuccess:(void (^)(void))successHandler failure:(void (^)(NSError *error))failureHandler
{
    [self createPreKeysWithAuth:[ChatServiceAuth implicit] success:successHandler failure:failureHandler];
}

+ (void)createPreKeysWithAuth:(ChatServiceAuth *)auth
                      success:(void (^)(void))successHandler
                      failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(!self.tsAccountManager.isRegisteredAndReady);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SSKCreatePreKeysOperation *aciOp = [[SSKCreatePreKeysOperation alloc] initForIdentity:OWSIdentityACI auth:auth];
        SSKCreatePreKeysOperation *pniOp = [[SSKCreatePreKeysOperation alloc] initForIdentity:OWSIdentityPNI auth:auth];
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
        SSKCreatePreKeysOperation *op = [[SSKCreatePreKeysOperation alloc] initForIdentity:identity
                                                                                      auth:[ChatServiceAuth implicit]];
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
        SSKRotateSignedPreKeyOperation *aciOp = [[SSKRotateSignedPreKeyOperation alloc] initForIdentity:OWSIdentityACI
                                                                                     shouldSkipIfRecent:NO];
        SSKRotateSignedPreKeyOperation *pniOp = [[SSKRotateSignedPreKeyOperation alloc] initForIdentity:OWSIdentityPNI
                                                                                     shouldSkipIfRecent:NO];
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
