//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingReceiptManager.h"
#import "AppReadiness.h"
#import "FunctionalUtil.h"
#import "MessageSender.h"
#import "OWSError.h"
#import "OWSReceiptsForSenderMessage.h"
#import "TSContactThread.h"
#import "TSYapDatabaseObject.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *NSStringForOWSReceiptType(OWSReceiptType receiptType)
{
    switch (receiptType) {
        case OWSReceiptType_Delivery:
            return @"Delivery";
        case OWSReceiptType_Read:
            return @"Read";
        case OWSReceiptType_Viewed:
            return @"Viewed";
        default:
            return @"Unknown";
    }
}

#pragma mark -

@interface OWSOutgoingReceiptManager ()

// This property should only be accessed on the serialQueue.
@property (nonatomic) BOOL isProcessing;

@end

#pragma mark -

@implementation OWSOutgoingReceiptManager

+ (SDSKeyValueStore *)deliveryReceiptStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kOutgoingDeliveryReceiptManagerCollection"];
}

+ (SDSKeyValueStore *)readReceiptStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kOutgoingReadReceiptManagerCollection"];
}

+ (SDSKeyValueStore *)viewedReceiptStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kOutgoingViewedReceiptManagerCollection"];
}

#pragma mark -

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    _pendingTasks = [[PendingTasks alloc] initWithLabel:@"Receipt Sends"];

    // We skip any sends to untrusted identities since we know they'll fail anyway. If an identity state changes
    // we should recheck our pendingReceipts to re-attempt a send to formerly untrusted recipients.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(process)
                                                 name:OWSIdentityManagerObjCBridge.identityStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(process)
                                                 name:SSKReachability.owsReachabilityDidChange
                                               object:nil];

    // Start processing.
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self process]; });

    return self;
}

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue
            = dispatch_queue_create("org.signal.outgoing-receipts", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
    });

    return _serialQueue;
}

// Schedules a processing pass, unless one is already scheduled.
- (void)process {
    [self processWithCompletion:nil];
}

// Schedules a processing pass, unless one is already scheduled.
- (void)processWithCompletion:(void (^_Nullable)(void))completion
{
    if (!AppReadiness.isAppReady && !CurrentAppContext().isRunningTests) {
        OWSFailDebug(@"Outgoing receipts require app is ready");
        if (completion) {
            completion();
        }
        return;
    }

    dispatch_async(self.serialQueue, ^{
        if (self.isProcessing) {
            if (completion) {
                completion();
            }
            [self logMemoryUsage];
            return;
        }

        OWSLogVerbose(@"Processing outbound receipts.");

        self.isProcessing = YES;

        if (!self.reachabilityManager.isReachable) {
            // No network availability; abort.
            self.isProcessing = NO;
            if (completion) {
                completion();
            }
            [self logMemoryUsage];
            return;
        }

        NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];
        [sendPromises addObjectsFromArray:[self sendReceiptsForReceiptType:OWSReceiptType_Delivery]];
        [sendPromises addObjectsFromArray:[self sendReceiptsForReceiptType:OWSReceiptType_Read]];
        [sendPromises addObjectsFromArray:[self sendReceiptsForReceiptType:OWSReceiptType_Viewed]];

        if (sendPromises.count < 1) {
            // No work to do; abort.
            self.isProcessing = NO;
            if (completion) {
                completion();
            }
            [self logMemoryUsage];
            return;
        }

        AnyPromise *completionPromise = [AnyPromise whenResolved:sendPromises];
        completionPromise.ensure(^() {
            if (completion) {
                completion();
            }
            // Wait N seconds before conducting another pass.
            // This allows time for a batch to accumulate.
            //
            // We want a value high enough to allow us to effectively de-duplicate
            // receipts without being so high that we incur so much latency that
            // the user notices.
            const CGFloat kProcessingFrequencySeconds = 3.f;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kProcessingFrequencySeconds * NSEC_PER_SEC)),
                self.serialQueue,
                ^{
                    self.isProcessing = NO;

                    [self process];
                });
        });
    });
}

- (void)logMemoryUsage {
    if (SSKDebugFlags.internalLogging) {
        OWSLogInfo(@"memoryUsage: %@", LocalDevice.memoryUsageString);
    }
}

- (NSArray<AnyPromise *> *)sendReceiptsForReceiptType:(OWSReceiptType)receiptType {
    __block NSDictionary<SignalServiceAddress *, MessageReceiptSet *> *queuedReceiptMap;
    [self.databaseStorage
        readWithBlock:^(SDSAnyReadTransaction *transaction) {
            NSMutableDictionary *receiptSetsToSend = [[self fetchAllReceiptSetsWithType:receiptType
                                                                            transaction:transaction] mutableCopy];
            NSArray *excludedAddresses = [receiptSetsToSend.allKeys filter:^BOOL(SignalServiceAddress *address) {
                return [self.blockingManager isAddressBlocked:address transaction:transaction] ||
                    [RecipientHidingManagerObjcBridge isHiddenAddress:address tx:transaction];
            }];

            for (SignalServiceAddress *address in excludedAddresses) {
                OWSLogWarn(@"Skipping send for excluded address: %@", address);
                // If an address is excluded, we don't bother sending a receipt.
                // We remove it from our fetched list, and dequeue it from our pending receipt set
                MessageReceiptSet *receiptSet = receiptSetsToSend[address];
                [self dequeueReceiptsFor:address receiptSet:receiptSet receiptType:receiptType];
                [receiptSetsToSend removeObjectForKey:address];
            }
            queuedReceiptMap = [receiptSetsToSend copy];
        }
                 file:__FILE__
             function:__FUNCTION__
                 line:__LINE__];

    NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];

    for (SignalServiceAddress *address in queuedReceiptMap) {
        if (!address.isValid) {
            OWSFailDebug(@"Unexpected identifier.");
            continue;
        }

        MessageReceiptSet *receiptSet = queuedReceiptMap[address];
        if (receiptSet.timestamps.count < 1) {
            OWSFailDebug(@"Missing timestamps.");
            continue;
        }

        if ([OWSIdentityManagerObjCBridge untrustedIdentityForSendingToAddress:address]) {
            OWSLogWarn(@"%@ is untrusted. Deferring sending of receipts.", address);
            continue;
        }

        TSThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:address];

        __block AnyPromise *sendPromise;
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            OWSReceiptsForSenderMessage *message;
            NSString *receiptName = NSStringForOWSReceiptType(receiptType);
            switch (receiptType) {
                case OWSReceiptType_Delivery:
                    message = [OWSReceiptsForSenderMessage deliveryReceiptsForSenderMessageWithThread:thread
                                                                                           receiptSet:receiptSet
                                                                                          transaction:transaction];
                    break;
                case OWSReceiptType_Read:
                    message = [OWSReceiptsForSenderMessage readReceiptsForSenderMessageWithThread:thread
                                                                                       receiptSet:receiptSet
                                                                                      transaction:transaction];
                    break;
                case OWSReceiptType_Viewed:
                    message = [OWSReceiptsForSenderMessage viewedReceiptsForSenderMessageWithThread:thread
                                                                                         receiptSet:receiptSet
                                                                                        transaction:transaction];
                    break;
            }

            sendPromise =
                [self.sskJobQueues.messageSenderJobQueue addPromiseWithMessage:message.asPreparer
                                                     removeMessageAfterSending:NO
                                                 limitToCurrentProcessLifetime:YES
                                                                isHighPriority:NO
                                                                   transaction:transaction]
                    .doneInBackground(^(id value) {
                        OWSLogInfo(@"Successfully sent %lu %@ receipts to sender.",
                            (unsigned long)receiptSet.timestamps.count,
                            receiptName);

                        // DURABLE CLEANUP - we could replace the custom durability logic in this class
                        // with a durable JobQueue.
                        [self dequeueReceiptsFor:address receiptSet:receiptSet receiptType:receiptType];
                    })
                    .catchInBackground(^(NSError *error) {
                        OWSLogError(@"Failed to send %@ receipts to sender with error: %@", receiptName, error);

                        if ([MessageSenderNoSuchSignalRecipientError isNoSuchSignalRecipientError:error]) {
                            [self dequeueReceiptsFor:address receiptSet:receiptSet receiptType:receiptType];
                        }
                    });
        });

        [sendPromises addObject:sendPromise];
    }

    return [sendPromises copy];
}

- (SDSKeyValueStore *)storeForReceiptType:(OWSReceiptType)receiptType
{
    switch (receiptType) {
        case OWSReceiptType_Delivery:
            return OWSOutgoingReceiptManager.deliveryReceiptStore;
        case OWSReceiptType_Read:
            return OWSOutgoingReceiptManager.readReceiptStore;
        case OWSReceiptType_Viewed:
            return OWSOutgoingReceiptManager.viewedReceiptStore;
    }
}

@end

NS_ASSUME_NONNULL_END
