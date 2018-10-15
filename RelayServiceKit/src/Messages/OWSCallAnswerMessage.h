//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageAnswer;
@class OutgoingControlMessage;

/**
 * Sent by the call recipient upon accepting a CallOffer
 */
@interface OWSCallAnswerMessage : NSObject

- (instancetype)initWithPeerId:(NSString *)peerId sessionDescription:(NSString *)sessionDescription;

@property (nonatomic, readonly, copy) NSString *peerId;
@property (nonatomic, readonly, copy) NSString *sessionDescription;


//-(OutgoingControlMessage *)asOutgoingControlMessage;

// TODO: Convert to control message
- (OWSSignalServiceProtosCallMessageAnswer *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
