//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingReceiptManager.h"
#import "AppReadiness.h"
#import "MessageSender.h"
#import "OWSError.h"
#import "OWSReceiptsForSenderMessage.h"
#import "SSKEnvironment.h"
#import "TSContactThread.h"
#import "TSYapDatabaseObject.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSReceiptType) {
    OWSReceiptType_Delivery,
    OWSReceiptType_Read,
};

@interface OWSOutgoingReceiptManager ()

// This property should only be accessed on the serialQueue.
@property (nonatomic) BOOL isProcessing;

@end

#pragma mark -

@implementation OWSOutgoingReceiptManager

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

+ (SDSKeyValueStore *)deliveryReceiptStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kOutgoingDeliveryReceiptManagerCollection"];
}

+ (SDSKeyValueStore *)readReceiptStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kOutgoingReadReceiptManagerCollection"];
}

#pragma mark -

+ (instancetype)shared
{
    OWSAssert(SSKEnvironment.shared.outgoingReceiptManager);

    return SSKEnvironment.shared.outgoingReceiptManager;
}

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
    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        [self process];
    }];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (MessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (id<SSKReachabilityManager>)reachabilityManager
{
    return SSKEnvironment.shared.reachabilityManager;
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

- (SignalServiceAddress *)addressForIdentifier:(NSString *)identifier
{
    // The identifier could be either a UUID or a phone number,
    // check if it's a valid UUID. If not, assume it's a phone number.

    NSUUID *_Nullable uuid = [[NSUUID alloc] initWithUUIDString:identifier];
    if (uuid) {
        return [[SignalServiceAddress alloc] initWithUuid:uuid phoneNumber:nil];
    } else {
        return [[SignalServiceAddress alloc] initWithPhoneNumber:identifier];
    }
}

- (NSArray<AnyPromise *> *)sendReceiptsForReceiptType:(OWSReceiptType)receiptType {
    SDSKeyValueStore *store = [self storeForReceiptType:receiptType];

    NSMutableDictionary<NSString *, NSSet<NSNumber *> *> *queuedReceiptMap = [NSMutableDictionary new];
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        [store enumerateKeysAndObjectsWithTransaction:transaction
                                                block:^(NSString *key, id object, BOOL *stop) {
                                                    NSString *recipientId = key;
                                                    NSSet<NSNumber *> *timestamps = object;
                                                    queuedReceiptMap[recipientId] = [timestamps copy];
                                                }];
    }];

    NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];

    for (NSString *identifier in queuedReceiptMap) {
        // The identifier could be either a UUID or a phone number,
        // check if it's a valid UUID. If not, assume it's a phone number.

        SignalServiceAddress *address = [self addressForIdentifier:identifier];

        if (!address.isValid) {
            OWSFailDebug(@"Unexpected identifier.");
            continue;
        }

        NSSet<NSNumber *> *timestamps = queuedReceiptMap[identifier];
        if (timestamps.count < 1) {
            OWSFailDebug(@"Missing timestamps.");
            continue;
        }

        TSThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:address];
        OWSReceiptsForSenderMessage *message;
        NSString *receiptName;
        switch (receiptType) {
            case OWSReceiptType_Delivery:
                message =
                    [OWSReceiptsForSenderMessage deliveryReceiptsForSenderMessageWithThread:thread
                                                                          messageTimestamps:timestamps.allObjects];
                receiptName = @"Delivery";
                break;
            case OWSReceiptType_Read:
                message = [OWSReceiptsForSenderMessage readReceiptsForSenderMessageWithThread:thread
                                                                            messageTimestamps:timestamps.allObjects];
                receiptName = @"Read";
                break;
        }

        AnyPromise *sendPromise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            [self.messageSender sendMessage:message.asPreparer
                success:^{
                    OWSLogInfo(
                        @"Successfully sent %lu %@ receipts to sender.", (unsigned long)timestamps.count, receiptName);

                    // DURABLE CLEANUP - we could replace the custom durability logic in this class
                    // with a durable JobQueue.
                    [self dequeueReceiptsForAddress:address timestamps:timestamps receiptType:receiptType];

                    // The value doesn't matter, we just need any non-NSError value.
                    resolve(@(1));
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Failed to send %@ receipts to sender with error: %@", receiptName, error);

                    if (error.domain == OWSSignalServiceKitErrorDomain
                        && error.code == OWSErrorCodeNoSuchSignalRecipient) {
                        [self dequeueReceiptsForAddress:address timestamps:timestamps receiptType:receiptType];
                    }

                    resolve(error);
                }];
        }];
        [sendPromises addObject:sendPromise];
    }

    return [sendPromises copy];
}

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope transaction:(SDSAnyWriteTransaction *)transaction
{
    [self enqueueReceiptForAddress:envelope.sourceAddress
                         timestamp:envelope.timestamp
                       receiptType:OWSReceiptType_Delivery
                       transaction:transaction];
}

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)address
                           timestamp:(uint64_t)timestamp
                         transaction:(SDSAnyWriteTransaction *)transaction
{
    [self enqueueReceiptForAddress:address timestamp:timestamp receiptType:OWSReceiptType_Read transaction:transaction];
}

- (void)enqueueReceiptForAddress:(SignalServiceAddress *)address
                       timestamp:(uint64_t)timestamp
                     receiptType:(OWSReceiptType)receiptType
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    SDSKeyValueStore *store = [self storeForReceiptType:receiptType];

    OWSAssertDebug(address.isValid);
    if (timestamp < 1) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }

    NSString *identifier = address.uuidString ?: address.phoneNumber;

    NSSet<NSNumber *> *_Nullable oldUUIDTimestamps;
    if (address.uuidString) {
        oldUUIDTimestamps = [store getObjectForKey:address.uuidString transaction:transaction];
    }

    NSSet<NSNumber *> *_Nullable oldPhoneNumberTimestamps;
    if (address.phoneNumber) {
        oldPhoneNumberTimestamps = [store getObjectForKey:address.phoneNumber transaction:transaction];
    }

    NSSet<NSNumber *> *_Nullable oldTimestamps;

    // Unexpectedly have entries both on phone number and UUID, defer to UUID
    if (oldUUIDTimestamps && oldPhoneNumberTimestamps) {
        oldTimestamps = [oldUUIDTimestamps setByAddingObjectsFromSet:oldPhoneNumberTimestamps];
        [store removeValueForKey:address.phoneNumber transaction:transaction];

        // If we have timestamps only under phone number, but know the UUID, migrate them lazily
    } else if (oldPhoneNumberTimestamps && address.uuidString) {
        oldTimestamps = oldPhoneNumberTimestamps;
        [store removeValueForKey:address.phoneNumber transaction:transaction];
    } else {
        oldTimestamps = oldUUIDTimestamps ?: oldPhoneNumberTimestamps;
    }

    NSMutableSet<NSNumber *> *newTimestamps = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
    [newTimestamps addObject:@(timestamp)];

    [store setObject:newTimestamps key:identifier transaction:transaction];

    [transaction addAsyncCompletionWithQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                                       block:^{
                                           [self process];
                                       }];
}

- (void)dequeueReceiptsForAddress:(SignalServiceAddress *)address
                       timestamps:(NSSet<NSNumber *> *)timestamps
                      receiptType:(OWSReceiptType)receiptType
{
    SDSKeyValueStore *store = [self storeForReceiptType:receiptType];

    OWSAssertDebug(address.isValid);
    if (timestamps.count < 1) {
        OWSFailDebug(@"Invalid timestamps.");
        return;
    }
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSString *identifier = address.uuidString ?: address.phoneNumber;

        NSSet<NSNumber *> *_Nullable oldUUIDTimestamps;
        if (address.uuidString) {
            oldUUIDTimestamps = [store getObjectForKey:address.uuidString transaction:transaction];
        }

        NSSet<NSNumber *> *_Nullable oldPhoneNumberTimestamps;
        if (address.phoneNumber) {
            oldPhoneNumberTimestamps = [store getObjectForKey:address.phoneNumber transaction:transaction];
        }

        NSSet<NSNumber *> *_Nullable oldTimestamps = oldUUIDTimestamps;

        // Unexpectedly have entries both on phone number and UUID, defer to UUID
        if (oldUUIDTimestamps && oldPhoneNumberTimestamps) {
            [store removeValueForKey:address.phoneNumber transaction:transaction];

            // If we have timestamps only under phone number, but know the UUID, migrate them lazily
        } else if (oldPhoneNumberTimestamps && address.uuidString) {
            oldTimestamps = oldPhoneNumberTimestamps;
            [store removeValueForKey:address.phoneNumber transaction:transaction];

            // We don't know the UUID, just use the phone number timestamps.
        } else if (oldPhoneNumberTimestamps) {
            oldTimestamps = oldPhoneNumberTimestamps;
        }

        NSMutableSet<NSNumber *> *newTimestamps = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
        [newTimestamps minusSet:timestamps];

        if (newTimestamps.count > 0) {
            [store setObject:newTimestamps key:identifier transaction:transaction];
        } else {
            [store removeValueForKey:identifier transaction:transaction];
        }
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
    }
}

@end

NS_ASSUME_NONNULL_END
