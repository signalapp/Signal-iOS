//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSCallBusyMessage;
@class OWSCallHangupMessage;
@class SSKProtoCallMessageAnswer;
@class SSKProtoCallMessageIceUpdate;
@class SSKProtoCallMessageOffer;
@class TSThread;

/**
 * WebRTC call signaling sent out of band, via the Signal Service
 */
@interface OWSOutgoingCallMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithTimestamp:(uint64_t)timestamp
                                        inThread:(nullable TSThread *)thread
                                     messageBody:(nullable NSString *)body
                                   attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                                expiresInSeconds:(uint32_t)expiresInSeconds
                                 expireStartedAt:(uint64_t)expireStartedAt
                                  isVoiceMessage:(BOOL)isVoiceMessage
                                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread offerMessage:(SSKProtoCallMessageOffer *)offerMessage;
- (instancetype)initWithThread:(TSThread *)thread answerMessage:(SSKProtoCallMessageAnswer *)answerMessage;
- (instancetype)initWithThread:(TSThread *)thread iceUpdateMessage:(SSKProtoCallMessageIceUpdate *)iceUpdateMessage;
- (instancetype)initWithThread:(TSThread *)thread
             iceUpdateMessages:(NSArray<SSKProtoCallMessageIceUpdate *> *)iceUpdateMessage;
- (instancetype)initWithThread:(TSThread *)thread hangupMessage:(OWSCallHangupMessage *)hangupMessage;
- (instancetype)initWithThread:(TSThread *)thread busyMessage:(OWSCallBusyMessage *)busyMessage;

@property (nullable, nonatomic, readonly) SSKProtoCallMessageOffer *offerMessage;
@property (nullable, nonatomic, readonly) SSKProtoCallMessageAnswer *answerMessage;
@property (nullable, nonatomic, readonly) NSArray<SSKProtoCallMessageIceUpdate *> *iceUpdateMessages;
@property (nullable, nonatomic, readonly) OWSCallHangupMessage *hangupMessage;
@property (nullable, nonatomic, readonly) OWSCallBusyMessage *busyMessage;

@end

NS_ASSUME_NONNULL_END
