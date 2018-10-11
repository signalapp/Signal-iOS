//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDeliveryReceiptManager.h"
#import "AppReadiness.h"
#import "OWSMessageSender.h"
#import "OWSPrimaryStorage.h"
#import "OWSReceiptsForSenderMessage.h"
#import "SSKEnvironment.h"
#import "TSContactThread.h"
#import "TSYapDatabaseObject.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kDeliveryReceiptManagerCollection = @"kDeliveryReceiptManagerCollection";

@interface OWSDeliveryReceiptManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

// Should only be accessed on the serialQueue.
@property (nonatomic) BOOL isProcessing;

// A map of "recipient id"-to-"timestamp list" for delivery receipts that
// we will send to senders.
//
// Should only be accessed on the serialQueue.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSMutableSet<NSNumber *> *> *deliveryReceiptMap;

@end

#pragma mark -

@implementation OWSDeliveryReceiptManager

+ (instancetype)sharedManager {
    OWSAssert(SSKEnvironment.shared.deliveryReceiptManager);

    return SSKEnvironment.shared.deliveryReceiptManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage {
    self = [super init];

    if (!self) {
        return self;
    }

    _dbConnection = primaryStorage.newDatabaseConnection;

    _deliveryReceiptMap = [NSMutableDictionary new];

    OWSSingletonAssert();

    // Start processing.
    [AppReadiness runNowOrWhenAppIsReady:^{
        [self scheduleProcessing];
    }];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (OWSMessageSender *)messageSender {
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

#pragma mark -

- (dispatch_queue_t)serialQueue {
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue = dispatch_queue_create("org.whispersystems.deliveryReceipts", DISPATCH_QUEUE_SERIAL);
    });

    return _serialQueue;
}

// Schedules a processing pass, unless one is already scheduled.
- (void)scheduleProcessing {
    OWSAssertDebug(AppReadiness.isAppReady);

    dispatch_async(self.serialQueue, ^{
        if (self.isProcessing) {
            return;
        }

        self.isProcessing = YES;

        [self process];
    });
}

- (void)process {
    OWSLogVerbose(@"Processing outbound delivery receipts.");

    NSMutableDictionary<NSString *, NSSet<NSNumber *> *> *deliveryReceiptMap = [NSMutableDictionary new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [transaction enumerateKeysAndObjectsInCollection:kDeliveryReceiptManagerCollection
                                              usingBlock:^(NSString *key, id object, BOOL *stop) {
                                                  NSString *recipientId = key;
                                                  NSSet<NSNumber *> *timestamps = object;
                                                  deliveryReceiptMap[recipientId] = timestamps;
                                              }];
    }];

    BOOL didWork = NO;

    for (NSString *recipientId in deliveryReceiptMap) {
        NSSet<NSNumber *> *timestamps = deliveryReceiptMap[recipientId];
        if (timestamps.count < 1) {
            OWSFailDebug(@"Missing timestamps.");
            continue;
        }

        TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
        OWSReceiptsForSenderMessage *message =
            [OWSReceiptsForSenderMessage deliveryReceiptsForSenderMessageWithThread:thread
                                                                  messageTimestamps:timestamps.allObjects];

        [self.messageSender enqueueMessage:message
            success:^{
                OWSLogInfo(@"Successfully sent %lu delivery receipts to sender.", (unsigned long)timestamps.count);
            }
            failure:^(NSError *error) {
                OWSLogError(@"Failed to send delivery receipts to sender with error: %@", error);
            }];

        didWork = YES;
    }

    // Now that they've been processed, remove all enqueued delivery receipts.
    //
    // NOTE: we don't need to worry about race conditions; this
    // collection will only be mutated on serialQueue.
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:kDeliveryReceiptManagerCollection];
    }];

    if (!didWork) {
        self.isProcessing = NO;
        return;
    }

    // Wait N seconds before processing delivery receipts again.
    // This allows time for a batch to accumulate.
    //
    // We want a value high enough to allow us to effectively de-duplicate,
    // delivery receipts without being so high that we risk not sending delivery
    // receipts due to app exit.
    const CGFloat kProcessingFrequencySeconds = 3.f;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kProcessingFrequencySeconds * NSEC_PER_SEC)), self.serialQueue, ^{
            [self process];
        });
}

- (void)envelopeWasReceived:(SSKProtoEnvelope *)envelope {
    OWSLogVerbose(@"");

    [self enqueueDeliveryReceiptWithRecipientId:envelope.source timestamp:envelope.timestamp];
}

- (void)enqueueDeliveryReceiptWithRecipientId:(NSString *)recipientId timestamp:(uint64_t)timestamp {
    OWSLogVerbose(@"");

    if (recipientId.length < 1) {
        OWSFailDebug(@"Invalid recipient id.");
        return;
    }
    if (timestamp < 1) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }
    dispatch_async(self.serialQueue, ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            NSSet<NSNumber *> *_Nullable oldTimestamps = [transaction objectForKey:recipientId
                                                                      inCollection:kDeliveryReceiptManagerCollection];
            NSMutableSet<NSNumber *> *newTimestamps
                = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
            [newTimestamps addObject:@(timestamp)];

            [transaction setObject:newTimestamps forKey:recipientId inCollection:kDeliveryReceiptManagerCollection];
        }];

        [self scheduleProcessing];
    });
}

- (void)dequeueDeliveryReceiptsWithRecipientId:(NSString *)recipientId timestamps:(NSSet<NSNumber *> *)timestamps {
    if (recipientId.length < 1) {
        OWSFailDebug(@"Invalid recipient id.");
        return;
    }
    if (timestamps.count < 1) {
        OWSFailDebug(@"Invalid timestamps.");
        return;
    }
    dispatch_async(self.serialQueue, ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            NSSet<NSNumber *> *_Nullable oldTimestamps = [transaction objectForKey:recipientId
                                                                      inCollection:kDeliveryReceiptManagerCollection];
            NSMutableSet<NSNumber *> *newTimestamps
                = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
            [newTimestamps minusSet:timestamps];

            if (newTimestamps.count > 0) {
                [transaction setObject:newTimestamps forKey:recipientId inCollection:kDeliveryReceiptManagerCollection];
            } else {
                [transaction removeObjectForKey:recipientId inCollection:kDeliveryReceiptManagerCollection];
            }
        }];
    });
}

@end

NS_ASSUME_NONNULL_END
