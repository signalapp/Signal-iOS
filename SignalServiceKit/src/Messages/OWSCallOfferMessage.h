//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageOffer;

/**
 * Sent by the call initiator to Signal their intention to set up a call with the recipient.
 */
@interface OWSCallOfferMessage : NSObject

- (instancetype)initWithCallId:(UInt64)callId sessionDescription:(NSString *)sessionDescription;

@property (nonatomic, readonly) UInt64 callId;
@property (nonatomic, readonly, copy) NSString *sessionDescription;

- (nullable SSKProtoCallMessageOffer *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
