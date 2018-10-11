//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SSKProtoEnvelope;

@interface OWSOutgoingReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;
+ (instancetype)sharedManager;

- (void)enqueueDeliveryReceiptForEnvelope:(SSKProtoEnvelope *)envelope;

- (void)enqueueReadReceiptForEnvelope:(NSString *)messageAuthorId timestamp:(uint64_t)timestamp;

@end

NS_ASSUME_NONNULL_END
