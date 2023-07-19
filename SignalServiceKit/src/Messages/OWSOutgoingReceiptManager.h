//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@protocol RecipientHidingManager;

@class PendingTasks;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SSKProtoEnvelope;
@class SignalServiceAddress;

typedef NS_ENUM(NSUInteger, OWSReceiptType) {
    OWSReceiptType_Delivery,
    OWSReceiptType_Read,
    OWSReceiptType_Viewed,
};

@interface OWSOutgoingReceiptManager : NSObject

+ (SDSKeyValueStore *)deliveryReceiptStore;
+ (SDSKeyValueStore *)readReceiptStore;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithRecipientHidingManager:(id<RecipientHidingManager>)recipientHidingManager
    NS_DESIGNATED_INITIALIZER;

// TODO: Make this private.
@property (nonatomic, readonly) PendingTasks *pendingTasks;

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope
                          messageUniqueId:(nullable NSString *)messageUniqueId
                              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)messageAuthorAddress
                           timestamp:(uint64_t)timestamp
                     messageUniqueId:(nullable NSString *)messageUniqueId
                         transaction:(SDSAnyWriteTransaction *)transaction;

- (void)enqueueViewedReceiptForAddress:(SignalServiceAddress *)messageAuthorAddress
                             timestamp:(uint64_t)timestamp
                       messageUniqueId:(nullable NSString *)messageUniqueId
                           transaction:(SDSAnyWriteTransaction *)transaction;

@end

@interface OWSOutgoingReceiptManager (SwiftAvailability)
- (SDSKeyValueStore *)storeForReceiptType:(OWSReceiptType)receiptType;
@end

NS_ASSUME_NONNULL_END
