//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageOffer;
@class OutgoingControlMessage;

/**
 * Sent by the call initiator to Signal their intention to set up a call with the recipient.
 */
@interface OWSCallOfferMessage : NSObject

- (instancetype)initWithPeerId:(NSString *)peerId sessionDescription:(NSString *)sessionDescription;

@property (nonatomic, readonly, copy) NSString *peerId;
@property (nonatomic, readonly, copy) NSString *sessionDescription;

- (OWSSignalServiceProtosCallMessageOffer *)asProtobuf;

-(OutgoingControlMessage *)asOutgoingControlMessasge;

@end

NS_ASSUME_NONNULL_END
