//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SSKProtoEnvelope;

@interface OWSDeliveryReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;
+ (instancetype)sharedManager;

- (void)envelopeWasReceived:(SSKProtoEnvelope *)envelope;

@end

NS_ASSUME_NONNULL_END
