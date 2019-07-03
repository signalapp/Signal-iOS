//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingReceiptManager.h"
#import "AppReadiness.h"
#import "OWSError.h"
#import "OWSMessageSender.h"
#import "OWSPrimaryStorage.h"
#import "OWSReceiptsForSenderMessage.h"
#import "SSKEnvironment.h"
#import "TSContactThread.h"
#import "TSYapDatabaseObject.h"
#import <Reachability/Reachability.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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
    OWSAssert(SSKEnvironment.shared.outgoingReceiptManager);

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

    OWSSingletonAssert();

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

#pragma mark - Dependencies

- (OWSMessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
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

        if (!self.reachability.isReachable) {
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
        [completionPromise retainUntilComplete];
    });
}

- (NSArray<AnyPromise *> *)sendReceiptsForReceiptType:(OWSReceiptType)receiptType {
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

    for (NSString *identifier in queuedReceiptMap) {
        // The identifier could be either a UUID or a phone number,
        // check if it's a valid UUID. If not, assume it's a phone number.

        SignalServiceAddress *address;
        NSUUID *_Nullable uuid = [[NSUUID alloc] initWithUUIDString:identifier];
        if (uuid) {
            address = [[SignalServiceAddress alloc] initWithUuid:uuid phoneNumber:nil];
        } else {
            address = [[SignalServiceAddress alloc] initWithPhoneNumber:identifier];
        }

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
            [self.messageSender sendMessage:message
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

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope
{
    [self enqueueReadReceiptForAddress:envelope.sourceAddress
                             timestamp:envelope.timestamp
                           receiptType:OWSReceiptType_Delivery];
}

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)address timestamp:(uint64_t)timestamp
{
    [self enqueueReadReceiptForAddress:address timestamp:timestamp receiptType:OWSReceiptType_Read];
}

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)address
                           timestamp:(uint64_t)timestamp
                         receiptType:(OWSReceiptType)receiptType
{
    NSString *collection = [self collectionForReceiptType:receiptType];

    OWSAssertDebug(address.isValid);
    if (timestamp < 1) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }

    dispatch_async(self.serialQueue, ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            NSString *identifier = address.uuidString ?: address.phoneNumber;

            NSSet<NSNumber *> *_Nullable oldUUIDTimestamps;
            if (address.uuidString) {
                oldUUIDTimestamps = [transaction objectForKey:address.uuidString inCollection:collection];
            }

            NSSet<NSNumber *> *_Nullable oldPhoneNumberTimestamps;
            if (address.phoneNumber) {
                oldPhoneNumberTimestamps = [transaction objectForKey:address.phoneNumber inCollection:collection];
            }

            NSSet<NSNumber *> *_Nullable oldTimestamps;

            // Unexpectedly have entries both on phone number and UUID, defer to UUID
            if (oldUUIDTimestamps && oldPhoneNumberTimestamps) {
                [transaction removeObjectForKey:address.phoneNumber inCollection:collection];

                // If we have timestamps only under phone number, but know the UUID, migrate them lazily
            } else if (oldPhoneNumberTimestamps && address.uuidString) {
                [transaction removeObjectForKey:address.phoneNumber inCollection:collection];
            }

            NSMutableSet<NSNumber *> *newTimestamps
                = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
            [newTimestamps addObject:@(timestamp)];

            [transaction setObject:newTimestamps forKey:identifier inCollection:collection];
        }];

        [self process];
    });
}

- (void)dequeueReceiptsForAddress:(SignalServiceAddress *)address
                       timestamps:(NSSet<NSNumber *> *)timestamps
                      receiptType:(OWSReceiptType)receiptType
{
    NSString *collection = [self collectionForReceiptType:receiptType];

    OWSAssertDebug(address.isValid);
    if (timestamps.count < 1) {
        OWSFailDebug(@"Invalid timestamps.");
        return;
    }
    dispatch_async(self.serialQueue, ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            NSString *identifier = address.uuidString ?: address.phoneNumber;

            NSSet<NSNumber *> *_Nullable oldUUIDTimestamps;
            if (address.uuidString) {
                oldUUIDTimestamps = [transaction objectForKey:address.uuidString inCollection:collection];
            }

            NSSet<NSNumber *> *_Nullable oldPhoneNumberTimestamps;
            if (address.phoneNumber) {
                oldPhoneNumberTimestamps = [transaction objectForKey:address.phoneNumber inCollection:collection];
            }

            NSSet<NSNumber *> *_Nullable oldTimestamps = oldUUIDTimestamps;

            // Unexpectedly have entries both on phone number and UUID, defer to UUID
            if (oldUUIDTimestamps && oldPhoneNumberTimestamps) {
                [transaction removeObjectForKey:address.phoneNumber inCollection:collection];

                // If we have timestamps only under phone number, but know the UUID, migrate them lazily
            } else if (oldPhoneNumberTimestamps && address.uuidString) {
                oldTimestamps = oldPhoneNumberTimestamps;
                [transaction removeObjectForKey:address.phoneNumber inCollection:collection];

                // We don't know the UUID, just use the phone number timestamps.
            } else if (oldPhoneNumberTimestamps) {
                oldTimestamps = oldPhoneNumberTimestamps;
            }

            NSMutableSet<NSNumber *> *newTimestamps
                = (oldTimestamps ? [oldTimestamps mutableCopy] : [NSMutableSet new]);
            [newTimestamps minusSet:timestamps];

            if (newTimestamps.count > 0) {
                [transaction setObject:newTimestamps forKey:identifier inCollection:collection];
            } else {
                [transaction removeObjectForKey:identifier inCollection:collection];
            }
        }];
    });
}

- (void)reachabilityChanged
{
    OWSAssertIsOnMainThread();

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
