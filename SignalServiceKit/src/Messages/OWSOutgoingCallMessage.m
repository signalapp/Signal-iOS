//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingCallMessage.h"
#import "ProtoUtils.h"
#import "TSContactThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingCallMessage

- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
    if (!self) {
        return self;
    }

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                  offerMessage:(SSKProtoCallMessageOffer *)offerMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [self initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _offerMessage = offerMessage;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                 answerMessage:(SSKProtoCallMessageAnswer *)answerMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [self initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _answerMessage = answerMessage;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
             iceUpdateMessages:(NSArray<SSKProtoCallMessageIceUpdate *> *)iceUpdateMessages
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [self initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _iceUpdateMessages = iceUpdateMessages;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
           legacyHangupMessage:(SSKProtoCallMessageHangup *)legacyHangupMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [self initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _legacyHangupMessage = legacyHangupMessage;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                 hangupMessage:(SSKProtoCallMessageHangup *)hangupMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [self initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _hangupMessage = hangupMessage;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                   busyMessage:(SSKProtoCallMessageBusy *)busyMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [self initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _busyMessage = busyMessage;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                 opaqueMessage:(SSKProtoCallMessageOpaque *)opaqueMessage
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [self initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _opaqueMessage = opaqueMessage;

    return self;
}

#pragma mark - TSOutgoingMessage overrides

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoContentBuilder *builder = [SSKProtoContent builder];
    builder.callMessage = [self buildCallMessage:thread transaction:transaction];
    return builder;
}

- (nullable SSKProtoCallMessage *)buildCallMessage:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoCallMessageBuilder *builder = [SSKProtoCallMessage builder];

    if (self.offerMessage) {
        [builder setOffer:self.offerMessage];
    }

    if (self.answerMessage) {
        [builder setAnswer:self.answerMessage];
    }

    if (self.iceUpdateMessages.count > 0) {
        [builder setIceUpdate:self.iceUpdateMessages];
    }

    if (self.legacyHangupMessage) {
        [builder setLegacyHangup:self.legacyHangupMessage];
    }
    
    if (self.hangupMessage) {
        [builder setHangup:self.hangupMessage];
    }

    if (self.busyMessage) {
        [builder setBusy:self.busyMessage];
    }

    if (self.opaqueMessage) {
        [builder setOpaque:self.opaqueMessage];
    }

    if (self.destinationDeviceId) {
        [builder setDestinationDeviceID:self.destinationDeviceId.unsignedIntValue];
    }

    [ProtoUtils addLocalProfileKeyIfNecessary:thread
                           callMessageBuilder:builder
                                  transaction:transaction];

    // All call messages must indicate multi-ring capability.
    [builder setSupportsMultiRing:YES];

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

- (BOOL)isUrgent
{
    return self.offerMessage ? YES : NO;
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
        payload = [NSString stringWithFormat:@"iceUpdateMessages: %lu", (unsigned long)self.iceUpdateMessages.count];
    } else if (self.legacyHangupMessage) {
        payload = @"legacyHangupMessage";
    } else if (self.hangupMessage) {
        payload = @"hangupMessage";
    } else if (self.busyMessage) {
        payload = @"busyMessage";
    } else {
        payload = @"none";
    }

    return [NSString stringWithFormat:@"%@ with payload: %@", className, payload];
}

- (BOOL)shouldRecordSendLog
{
    return NO;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintDefault;
}

@end

NS_ASSUME_NONNULL_END
