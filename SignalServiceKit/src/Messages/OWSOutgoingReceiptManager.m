//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingReceiptManager.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSReceiptsForSenderMessage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:SSKReachability.owsReachabilityDidChange
                                               object:nil];

    // Start processing.
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self process]; });

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue = dispatch_queue_create("org.whispersystems.outgoingReceipts", DISPATCH_QUEUE_SERIAL);
    });

    return _serialQueue;
}

// Schedules a processing pass, unless one is already scheduled.
- (void)process {
    OWSAssertDebug(AppReadiness.isAppReady);

    dispatch_async(self.serialQueue, ^{
        if (self.isProcessing) {
            return;
        }

        OWSLogVerbose(@"Processing outbound receipts.");

        self.isProcessing = YES;

        if (!self.reachabilityManager.isReachable) {
            // No network availability; abort.
            self.isProcessing = NO;
            return;
        }

        NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];
        [sendPromises addObjectsFromArray:[self sendReceiptsForReceiptType:OWSReceiptType_Delivery]];
        [sendPromises addObjectsFromArray:[self sendReceiptsForReceiptType:OWSReceiptType_Read]];
        [sendPromises addObjectsFromArray:[self sendReceiptsForReceiptType:OWSReceiptType_Viewed]];

        if (sendPromises.count < 1) {
            // No work to do; abort.
            self.isProcessing = NO;
            return;
        }

        AnyPromise *completionPromise = PMKJoin(sendPromises);
        completionPromise.ensure(^() {
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

- (NSArray<AnyPromise *> *)sendReceiptsForReceiptType:(OWSReceiptType)receiptType {
    __block NSDictionary<SignalServiceAddress *, MessageReceiptSet *> *queuedReceiptMap;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        queuedReceiptMap = [self fetchAllReceiptSetsWithType:receiptType transaction:transaction];
    }];

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

        if ([self.blockingManager isAddressBlocked:address]) {
            OWSLogWarn(@"Skipping send for blocked address: %@", address);
            [self dequeueReceiptsForAddress:address receiptSet:receiptSet receiptType:receiptType];
            continue;
        }

        TSThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:address];
        OWSReceiptsForSenderMessage *message;
        NSString *receiptName;
        switch (receiptType) {
            case OWSReceiptType_Delivery:
                message = [OWSReceiptsForSenderMessage deliveryReceiptsForSenderMessageWithThread:thread
                                                                                       receiptSet:receiptSet];
                receiptName = @"Delivery";
                break;
            case OWSReceiptType_Read:
                message = [OWSReceiptsForSenderMessage readReceiptsForSenderMessageWithThread:thread
                                                                                   receiptSet:receiptSet];
                receiptName = @"Read";
                break;
            case OWSReceiptType_Viewed:
                message = [OWSReceiptsForSenderMessage viewedReceiptsForSenderMessageWithThread:thread
                                                                                     receiptSet:receiptSet];
                receiptName = @"Viewed";
                break;
        }

        AnyPromise *sendPromise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            [self.messageSender sendMessage:message.asPreparer
                success:^{
                    OWSLogInfo(@"Successfully sent %lu %@ receipts to sender.",
                        (unsigned long)receiptSet.timestamps.count,
                        receiptName);

                    // DURABLE CLEANUP - we could replace the custom durability logic in this class
                    // with a durable JobQueue.
                    [self dequeueReceiptsForAddress:address receiptSet:receiptSet receiptType:receiptType];

                    // The value doesn't matter, we just need any non-NSError value.
                    resolve(@(1));
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Failed to send %@ receipts to sender with error: %@", receiptName, error);

                    if (error.domain == OWSSignalServiceKitErrorDomain
                        && error.code == OWSErrorCodeNoSuchSignalRecipient) {
                        [self dequeueReceiptsForAddress:address receiptSet:receiptSet receiptType:receiptType];
                    }

                    resolve(error);
                }];
        }];
        [sendPromises addObject:sendPromise];
    }

    return [sendPromises copy];
}

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope
                          messageUniqueId:(nullable NSString *)messageUniqueId
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    [self enqueueReceiptForAddress:envelope.sourceAddress
                         timestamp:envelope.timestamp
                   messageUniqueId:messageUniqueId
                       receiptType:OWSReceiptType_Delivery
                       transaction:transaction];
}

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)address
                           timestamp:(uint64_t)timestamp
                     messageUniqueId:(nullable NSString *)messageUniqueId
                         transaction:(SDSAnyWriteTransaction *)transaction
{
    [self enqueueReceiptForAddress:address
                         timestamp:timestamp
                   messageUniqueId:messageUniqueId
                       receiptType:OWSReceiptType_Read
                       transaction:transaction];
}

- (void)enqueueViewedReceiptForAddress:(SignalServiceAddress *)address
                             timestamp:(uint64_t)timestamp
                       messageUniqueId:(nullable NSString *)messageUniqueId
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    [self enqueueReceiptForAddress:address
                         timestamp:timestamp
                   messageUniqueId:messageUniqueId
                       receiptType:OWSReceiptType_Viewed
                       transaction:transaction];
}

- (void)enqueueReceiptForAddress:(SignalServiceAddress *)address
                       timestamp:(uint64_t)timestamp
                 messageUniqueId:(nullable NSString *)messageUniqueId
                     receiptType:(OWSReceiptType)receiptType
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    if (receiptType == OWSReceiptType_Viewed && !RemoteConfig.viewedReceiptSending) {
        return;
    }
    OWSAssertDebug(address.isValid);
    if (timestamp < 1) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }

    MessageReceiptSet *persistedSet = [self fetchReceiptSetWithType:receiptType
                                                            address:address
                                                        transaction:transaction];
    [persistedSet insertWithTimestamp:timestamp messageUniqueId:messageUniqueId];
    [self storeReceiptSet:persistedSet type:receiptType address:address transaction:transaction];
    [transaction addAsyncCompletionWithQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                                       block:^{
                                           [self process];
                                       }];
}

- (void)dequeueReceiptsForAddress:(SignalServiceAddress *)address
                       receiptSet:(MessageReceiptSet *)dequeueSet
                      receiptType:(OWSReceiptType)receiptType
{
    OWSAssertDebug(address.isValid);
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        MessageReceiptSet *persistedSet = [self fetchReceiptSetWithType:receiptType
                                                                address:address
                                                            transaction:transaction];
        [persistedSet subtract:dequeueSet];
        [self storeReceiptSet:persistedSet type:receiptType address:address transaction:transaction];
    });
}

- (void)reachabilityChanged
{
    OWSAssertIsOnMainThread();

    [self process];
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
