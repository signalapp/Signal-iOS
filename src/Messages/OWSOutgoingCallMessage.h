//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSCallOfferMessage;
@class OWSCallAnswerMessage;
@class OWSCallIceUpdateMessage;
@class OWSCallHangupMessage;
@class OWSCallBusyMessage;

@class TSThread;

/**
 * WebRTC call signaling sent out of band, via the Signal Service
 */
@interface OWSOutgoingCallMessage : TSOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread offerMessage:(OWSCallOfferMessage *)offerMessage;
- (instancetype)initWithThread:(TSThread *)thread answerMessage:(OWSCallAnswerMessage *)answerMessage;
- (instancetype)initWithThread:(TSThread *)thread iceUpdateMessage:(OWSCallIceUpdateMessage *)iceUpdateMessage;
- (instancetype)initWithThread:(TSThread *)thread
             iceUpdateMessages:(NSArray<OWSCallIceUpdateMessage *> *)iceUpdateMessage;
- (instancetype)initWithThread:(TSThread *)thread hangupMessage:(OWSCallHangupMessage *)hangupMessage;
- (instancetype)initWithThread:(TSThread *)thread busyMessage:(OWSCallBusyMessage *)busyMessage;

@property (nullable, nonatomic, readonly, strong) OWSCallOfferMessage *offerMessage;
@property (nullable, nonatomic, readonly, strong) OWSCallAnswerMessage *answerMessage;
@property (nullable, nonatomic, readonly, strong) NSArray<OWSCallIceUpdateMessage *> *iceUpdateMessages;
@property (nullable, nonatomic, readonly, strong) OWSCallHangupMessage *hangupMessage;
@property (nullable, nonatomic, readonly, strong) OWSCallBusyMessage *busyMessage;

@end

NS_ASSUME_NONNULL_END
