//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SSKProtoEnvelope;
@class SignalServiceAddress;

@interface OWSOutgoingReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;
+ (instancetype)sharedManager;

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope;

- (void)enqueueReadReceiptForAddress:(SignalServiceAddress *)messageAuthorAddress timestamp:(uint64_t)timestamp;

@end

NS_ASSUME_NONNULL_END
