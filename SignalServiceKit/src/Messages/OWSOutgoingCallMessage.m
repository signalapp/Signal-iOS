//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"
#import "NSDate+OWS.h"
#import "OWSCallAnswerMessage.h"
#import "OWSCallBusyMessage.h"
#import "OWSCallHangupMessage.h"
#import "OWSCallIceUpdateMessage.h"
#import "OWSCallOfferMessage.h"
#import "ProtoUtils.h"
#import "SignalRecipient.h"
#import "TSContactThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingCallMessage

- (instancetype)initWithThread:(TSThread *)thread
{
    // These records aren't saved, but their timestamp is used in the event
    // of a failing message send to insert the error at the appropriate place.
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];
    if (!self) {
        return self;
    }

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread offerMessage:(OWSCallOfferMessage *)offerMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _offerMessage = offerMessage;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread answerMessage:(OWSCallAnswerMessage *)answerMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _answerMessage = answerMessage;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread iceUpdateMessage:(OWSCallIceUpdateMessage *)iceUpdateMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _iceUpdateMessages = @[ iceUpdateMessage ];

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
             iceUpdateMessages:(NSArray<OWSCallIceUpdateMessage *> *)iceUpdateMessages
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _iceUpdateMessages = iceUpdateMessages;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread hangupMessage:(OWSCallHangupMessage *)hangupMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _hangupMessage = hangupMessage;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread busyMessage:(OWSCallBusyMessage *)busyMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _busyMessage = busyMessage;

    return self;
}

#pragma mark - TSOutgoingMessage overrides

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)isSilent
{
    // Avoid "phantom messages" for "outgoing call messages".

    return YES;
}

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    OWSAssert(recipient);

    SSKProtoContentBuilder *builder = [SSKProtoContentBuilder new];
    [builder setCallMessage:[self buildCallMessage:recipient.recipientId]];
    
    NSError *error;
    SSKProtoContent *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    NSData *_Nullable data = [result serializedDataAndReturnError:&error];
    if (error || !data) {
        OWSFail(@"%@ could not serialize protobuf: %@", self.logTag, error);
        return nil;
    }
    return data;
}

- (nullable SSKProtoCallMessage *)buildCallMessage:(NSString *)recipientId
{
    SSKProtoCallMessageBuilder *builder = [SSKProtoCallMessageBuilder new];

    if (self.offerMessage) {
        SSKProtoCallMessageOffer *_Nullable proto = [self.offerMessage asProtobuf];
        if (!proto) {
            return nil;
        }
        [builder setOffer:proto];
    }

    if (self.answerMessage) {
        SSKProtoCallMessageAnswer *_Nullable proto = [self.answerMessage asProtobuf];
        if (!proto) {
            return nil;
        }
        [builder setAnswer:proto];
    }

    if (self.iceUpdateMessages) {
        for (OWSCallIceUpdateMessage *iceUpdateMessage in self.iceUpdateMessages) {
            SSKProtoCallMessageIceUpdate *_Nullable proto = [iceUpdateMessage asProtobuf];
            if (!proto) {
                return nil;
            }
            [builder addIceUpdate:proto];
        }
    }

    if (self.hangupMessage) {
        SSKProtoCallMessageHangup *_Nullable proto = [self.hangupMessage asProtobuf];
        if (!proto) {
            return nil;
        }
        [builder setHangup:proto];
    }

    if (self.busyMessage) {
        SSKProtoCallMessageBusy *_Nullable proto = [self.busyMessage asProtobuf];
        if (!proto) {
            return nil;
        }
        [builder setBusy:proto];
    }

    [ProtoUtils addLocalProfileKeyIfNecessary:self.thread recipientId:recipientId callMessageBuilder:builder];

    NSError *error;
    SSKProtoCallMessage *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return result;
}

#pragma mark - TSYapDatabaseObject overrides

- (BOOL)shouldBeSaved
{
    return NO;
}

- (NSString *)debugDescription
{
    NSString *className = NSStringFromClass([self class]);

    NSString *payload;
    if (self.offerMessage) {
        payload = @"offerMessage";
    } else if (self.answerMessage) {
        payload = @"answerMessage";
    } else if (self.iceUpdateMessages.count > 0) {
        payload = @"iceUpdateMessage";
    } else if (self.hangupMessage) {
        payload = @"hangupMessage";
    } else if (self.busyMessage) {
        payload = @"busyMessage";
    } else {
        payload = @"none";
    }

    return [NSString stringWithFormat:@"%@ with payload: %@", className, payload];
}

@end

NS_ASSUME_NONNULL_END
