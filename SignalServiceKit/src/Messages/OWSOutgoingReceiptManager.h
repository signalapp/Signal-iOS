//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SSKProtoEnvelope;
@class SignalServiceAddress;

@interface OWSOutgoingReceiptManager : NSObject

+ (SDSKeyValueStore *)deliveryReceiptStore;
+ (SDSKeyValueStore *)readReceiptStore;

+ (instancetype)shared;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope
                              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)messageAuthorAddress
                           timestamp:(uint64_t)timestamp
                         transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
