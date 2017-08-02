//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSCallAnswerMessage.h"
#import "OWSCallBusyMessage.h"
#import "OWSCallHangupMessage.h"
#import "OWSCallIceUpdateMessage.h"
#import "OWSCallOfferMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSContactThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingCallMessage

//@synthesize thread = _thread;

- (instancetype)initWithThread:(TSThread *)thread
{
    // These records aren't saved, but their timestamp is used in the event
    // of a failing message send to insert the error at the appropriate place.
    self = [super initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread];
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

//
///**
// * override thread accessor in superclass, since this model is never saved.
// * TODO review
// */
//- (TSThread *)thread
//{
//    return _thread;
//}

- (NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
    [contentBuilder setCallMessage:[self asProtobuf]];
    [self addLocalProfileKeyIfNecessary:contentBuilder recipient:recipient];
    return [[contentBuilder build] data];
}

- (OWSSignalServiceProtosCallMessage *)asProtobuf
{
    OWSSignalServiceProtosCallMessageBuilder *builder = [OWSSignalServiceProtosCallMessageBuilder new];

    if (self.offerMessage) {
        [builder setOffer:[self.offerMessage asProtobuf]];
    }

    if (self.answerMessage) {
        [builder setAnswer:[self.answerMessage asProtobuf]];
    }

    if (self.iceUpdateMessages) {
        for (OWSCallIceUpdateMessage *iceUpdateMessage in self.iceUpdateMessages) {
            [builder addIceUpdate:[iceUpdateMessage asProtobuf]];
        }
    }

    if (self.hangupMessage) {
        [builder setHangup:[self.hangupMessage asProtobuf]];
    }

    if (self.busyMessage) {
        [builder setBusy:[self.busyMessage asProtobuf]];
    }

    return [builder build];
}

#pragma mark - TSYapDatabaseObject overrides

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // override superclass with no-op.
    //
    // There's no need to save this message, since it's not displayed to the user.
    //
    // Should we find a need to save this in the future, we need to exclude any non-serializable properties.
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
