//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingReceiptManager.h"
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import "SSKEnvironment.h"
#import "AppReadiness.h"
#import "OWSPrimaryStorage.h"
#import "TSContactThread.h"
#import "TSYapDatabaseObject.h"
#import <PromiseKit/PromiseKit.h>
#import <YapDatabase/YapDatabase.h>
#import <Reachability/Reachability.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSReceiptType) {
    OWSReceiptType_Delivery,
    OWSReceiptType_Read,
};

NSString *const kOutgoingDeliveryReceiptManagerCollection = @"kOutgoingDeliveryReceiptManagerCollection";
NSString *const kOutgoingReadReceiptManagerCollection = @"kOutgoingReadReceiptManagerCollection";

@interface OWSOutgoingReceiptManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (nonatomic) Reachability *reachability;

// This property should only be accessed on the serialQueue.
@property (nonatomic) BOOL isProcessing;

@end

#pragma mark -

@implementation OWSOutgoingReceiptManager

+ (instancetype)sharedManager
{
    return SSKEnvironment.shared.outgoingReceiptManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    self.reachability = [Reachability reachabilityForInternetConnection];

    _dbConnection = primaryStorage.newDatabaseConnection;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:kReachabilityChangedNotification
                                               object:nil];

    // Start processing.
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self process];
    }];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -

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
    dispatch_async(self.serialQueue, ^{
        if (self.isProcessing) {
            return;
        }

        self.isProcessing = YES;

        if (!self.reachability.isReachable) {
            // No network availability; abort.
            self.isProcessing = NO;
            return;
        }

        NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];
        [sendPromises addObjectsFromArray:[self sendReceiptsForReceiptType:OWSReceiptType_Read]];

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
        [completionPromise retainUntilComplete];
    });
}

- (NSArray<AnyPromise *> *)sendReceiptsForReceiptType:(OWSReceiptType)receiptType {
    if (receiptType == OWSReceiptType_Delivery) { return @[]; } // Don't send delivery receipts

    NSString *collection = [self collectionForReceiptType:receiptType];

    NSMutableDictionary<NSString *, NSSet<NSNumber *> *> *queuedReceiptMap = [NSMutableDictionary new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [transaction enumerateKeysAndObjectsInCollection:collection
                                              usingBlock:^(NSString *key, id object, BOOL *stop) {
                                                  NSString *recipientId = key;
                                                  NSSet<NSNumber *> *timestamps = object;
                                                  queuedReceiptMap[recipientId] = [timestamps copy];
                                              }];
    }];

    NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];

    for (NSString *recipientId in queuedReceiptMap) {
        NSSet<NSNumber *> *timestampsAsSet = queuedReceiptMap[recipientId];
        if (timestampsAsSet.count < 1) {
            continue;
        }

        TSThread *thread = [TSContactThread getOrCreateThreadWithContactSessionID:recipientId];

        if (thread.isGroupThread) { // Don't send receipts in group threads
            continue;
        }

        SNReadReceipt *readReceipt = [SNReadReceipt new];
        NSMutableArray<NSNumber *> *timestamps = [NSMutableArray new];
        for (NSNumber *timestamp in timestampsAsSet) {
            [timestamps addObject:timestamp];
        }
        readReceipt.timestamps = timestamps;
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            AnyPromise *promise = [SNMessageSender sendNonDurably:readReceipt inThread:thread usingTransaction:transaction]
            .thenOn(self.serialQueue, ^(id object) {
                [self dequeueReceiptsWithRecipientId:recipientId timestamps:timestampsAsSet receiptType:OWSReceiptType_Read];
            });
            [sendPromises addObject:promise];
        }];
    }

    return [sendPromises copy];
}

- (void)enqueueDeliveryReceiptForEnvelope:(SNProtoEnvelope *)envelope
{
    [self enqueueReceiptWithRecipientId:envelope.source
                              timestamp:envelope.timestamp
                            receiptType:OWSReceiptType_Delivery];
}

- (void)enqueueReadReceiptForEnvelope:(NSString *)messageAuthorId timestamp:(uint64_t)timestamp {
    [self enqueueReceiptWithRecipientId:messageAuthorId timestamp:timestamp receiptType:OWSReceiptType_Read];
}

- (void)enqueueReceiptWithRecipientId:(NSString *)recipientId
                            timestamp:(uint64_t)timestamp
                          receiptType:(OWSReceiptType)receiptType {
    NSString *collection = [self collectionForReceiptType:receiptType];

    if (recipientId.length < 1) {
        return;
    }
    if (timestamp < 1) {
        return;
    }
    dispatch_async(self.serialQueue, ^{
        [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            NSSet<NSNumber *> *_Nullable oldTimestamps = [transaction objectForKey:recipientId inCollection:collection];
            NSMutableSet<NSNumber *> *newTimestamps
                = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
            [newTimestamps addObject:@(timestamp)];

            [transaction setObject:newTimestamps forKey:recipientId inCollection:collection];
        }];

        [self process];
    });
}

- (void)dequeueReceiptsWithRecipientId:(NSString *)recipientId
                            timestamps:(NSSet<NSNumber *> *)timestamps
                           receiptType:(OWSReceiptType)receiptType {
    NSString *collection = [self collectionForReceiptType:receiptType];

    if (recipientId.length < 1) {
        return;
    }
    if (timestamps.count < 1) {
        return;
    }
    dispatch_async(self.serialQueue, ^{
        [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            NSSet<NSNumber *> *_Nullable oldTimestamps = [transaction objectForKey:recipientId inCollection:collection];
            NSMutableSet<NSNumber *> *newTimestamps
                = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
            [newTimestamps minusSet:timestamps];

            if (newTimestamps.count > 0) {
                [transaction setObject:newTimestamps forKey:recipientId inCollection:collection];
            } else {
                [transaction removeObjectForKey:recipientId inCollection:collection];
            }
        }];
    });
}

- (void)reachabilityChanged
{
    [self process];
}

- (NSString *)collectionForReceiptType:(OWSReceiptType)receiptType {
    switch (receiptType) {
        case OWSReceiptType_Delivery:
            return kOutgoingDeliveryReceiptManagerCollection;
        case OWSReceiptType_Read:
            return kOutgoingReadReceiptManagerCollection;
    }
}

@end

NS_ASSUME_NONNULL_END
