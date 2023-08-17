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

NSString *NSStringForOWSReceiptType(OWSReceiptType receiptType);

@interface OWSOutgoingReceiptManager : NSObject

+ (SDSKeyValueStore *)deliveryReceiptStore;
+ (SDSKeyValueStore *)readReceiptStore;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)processWithCompletion:(void (^_Nullable)(void))completion;

// TODO: Make this private.
@property (nonatomic, readonly) PendingTasks *pendingTasks;

@end

@interface OWSOutgoingReceiptManager (SwiftAvailability)
- (SDSKeyValueStore *)storeForReceiptType:(OWSReceiptType)receiptType;
@end

NS_ASSUME_NONNULL_END
