//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageOffer;

/**
 * Sent by the call initiator to Signal their intention to set up a call with the recipient.
 */
@interface OWSCallOfferMessage : NSObject

- (instancetype)initWithCallId:(UInt64)callId sessionDescription:(NSString *)sessionDescription;

@property (nonatomic, readonly) UInt64 callId;
@property (nonatomic, readonly, copy) NSString *sessionDescription;

- (OWSSignalServiceProtosCallMessageOffer *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
