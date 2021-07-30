//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

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

- (instancetype)init NS_DESIGNATED_INITIALIZER;

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
