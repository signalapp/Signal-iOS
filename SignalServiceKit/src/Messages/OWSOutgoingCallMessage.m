//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"
#import "NSDate+OWS.h"
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
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];
    if (!self) {
        return self;
    }

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread offerMessage:(SSKProtoCallMessageOffer *)offerMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _offerMessage = offerMessage;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread answerMessage:(SSKProtoCallMessageAnswer *)answerMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _answerMessage = answerMessage;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread iceUpdateMessage:(SSKProtoCallMessageIceUpdate *)iceUpdateMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _iceUpdateMessages = @[ iceUpdateMessage ];

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
             iceUpdateMessages:(NSArray<SSKProtoCallMessageIceUpdate *> *)iceUpdateMessages
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _iceUpdateMessages = iceUpdateMessages;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread hangupMessage:(SSKProtoCallMessageHangup *)hangupMessage
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _hangupMessage = hangupMessage;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread busyMessage:(SSKProtoCallMessageBusy *)busyMessage
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
    OWSAssertDebug(recipient);

    SSKProtoContentBuilder *builder = [SSKProtoContentBuilder new];
    [builder setCallMessage:[self buildCallMessage:recipient.recipientId]];
    
    NSError *error;
    NSData *_Nullable data = [builder buildSerializedDataAndReturnError:&error];
    if (error || !data) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return nil;
    }
    return data;
}

- (nullable SSKProtoCallMessage *)buildCallMessage:(NSString *)recipientId
{
    SSKProtoCallMessageBuilder *builder = [SSKProtoCallMessageBuilder new];

    if (self.offerMessage) {
        [builder setOffer:self.offerMessage];
    }

    if (self.answerMessage) {
        [builder setAnswer:self.answerMessage];
    }

    if (self.iceUpdateMessages.count > 0) {
        [builder setIceUpdate:self.iceUpdateMessages];
    }

    if (self.hangupMessage) {
        [builder setHangup:self.hangupMessage];
    }

    if (self.busyMessage) {
        [builder setBusy:self.busyMessage];
    }

    [ProtoUtils addLocalProfileKeyIfNecessary:self.thread recipientId:recipientId callMessageBuilder:builder];

    NSError *error;
    SSKProtoCallMessage *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFailDebug(@"could not build protobuf: %@", error);
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
