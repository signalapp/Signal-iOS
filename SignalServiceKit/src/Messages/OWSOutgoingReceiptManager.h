//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSKeyValueStore;
@class SSKProtoEnvelope;
@class SignalServiceAddress;

@interface OWSOutgoingReceiptManager : NSObject

+ (SDSKeyValueStore *)deliveryReceiptStore;
+ (SDSKeyValueStore *)readReceiptStore;

+ (instancetype)sharedManager;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope;

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)messageAuthorAddress timestamp:(uint64_t)timestamp;

@end

NS_ASSUME_NONNULL_END
