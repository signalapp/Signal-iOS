//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingCallMessage.h"
#import "TSContactThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingCallMessage

- (instancetype)initWithThread:(TSThread *)thread
            overrideRecipients:(NSArray<AciObjC *> *)overrideRecipients
                   transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:overrideRecipients
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (!self) {
        return self;
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    SSKProtoCallMessageAnswer *answerMessage = self.answerMessage;
    if (answerMessage != nil) {
        [coder encodeObject:answerMessage forKey:@"answerMessage"];
    }
    SSKProtoCallMessageBusy *busyMessage = self.busyMessage;
    if (busyMessage != nil) {
        [coder encodeObject:busyMessage forKey:@"busyMessage"];
    }
    NSNumber *destinationDeviceId = self.destinationDeviceId;
    if (destinationDeviceId != nil) {
        [coder encodeObject:destinationDeviceId forKey:@"destinationDeviceId"];
    }
    SSKProtoCallMessageHangup *hangupMessage = self.hangupMessage;
    if (hangupMessage != nil) {
        [coder encodeObject:hangupMessage forKey:@"hangupMessage"];
    }
    NSArray *iceUpdateMessages = self.iceUpdateMessages;
    if (iceUpdateMessages != nil) {
        [coder encodeObject:iceUpdateMessages forKey:@"iceUpdateMessages"];
    }
    SSKProtoCallMessageOffer *offerMessage = self.offerMessage;
    if (offerMessage != nil) {
        [coder encodeObject:offerMessage forKey:@"offerMessage"];
    }
    SSKProtoCallMessageOpaque *opaqueMessage = self.opaqueMessage;
    if (opaqueMessage != nil) {
        [coder encodeObject:opaqueMessage forKey:@"opaqueMessage"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_answerMessage = [coder decodeObjectOfClass:[SSKProtoCallMessageAnswer class] forKey:@"answerMessage"];
    self->_busyMessage = [coder decodeObjectOfClass:[SSKProtoCallMessageBusy class] forKey:@"busyMessage"];
    self->_destinationDeviceId = [coder decodeObjectOfClass:[NSNumber class] forKey:@"destinationDeviceId"];
    self->_hangupMessage = [coder decodeObjectOfClass:[SSKProtoCallMessageHangup class] forKey:@"hangupMessage"];
    self->_iceUpdateMessages =
        [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [SSKProtoCallMessageIceUpdate class] ]]
                              forKey:@"iceUpdateMessages"];
    self->_offerMessage = [coder decodeObjectOfClass:[SSKProtoCallMessageOffer class] forKey:@"offerMessage"];
    self->_opaqueMessage = [coder decodeObjectOfClass:[SSKProtoCallMessageOpaque class] forKey:@"opaqueMessage"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.answerMessage.hash;
    result ^= self.busyMessage.hash;
    result ^= self.destinationDeviceId.hash;
    result ^= self.hangupMessage.hash;
    result ^= self.iceUpdateMessages.hash;
    result ^= self.offerMessage.hash;
    result ^= self.opaqueMessage.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSOutgoingCallMessage *typedOther = (OWSOutgoingCallMessage *)other;
    if (![NSObject isObject:self.answerMessage equalToObject:typedOther.answerMessage]) {
        return NO;
    }
    if (![NSObject isObject:self.busyMessage equalToObject:typedOther.busyMessage]) {
        return NO;
    }
    if (![NSObject isObject:self.destinationDeviceId equalToObject:typedOther.destinationDeviceId]) {
        return NO;
    }
    if (![NSObject isObject:self.hangupMessage equalToObject:typedOther.hangupMessage]) {
        return NO;
    }
    if (![NSObject isObject:self.iceUpdateMessages equalToObject:typedOther.iceUpdateMessages]) {
        return NO;
    }
    if (![NSObject isObject:self.offerMessage equalToObject:typedOther.offerMessage]) {
        return NO;
    }
    if (![NSObject isObject:self.opaqueMessage equalToObject:typedOther.opaqueMessage]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSOutgoingCallMessage *result = [super copyWithZone:zone];
    result->_answerMessage = self.answerMessage;
    result->_busyMessage = self.busyMessage;
    result->_destinationDeviceId = self.destinationDeviceId;
    result->_hangupMessage = self.hangupMessage;
    result->_iceUpdateMessages = self.iceUpdateMessages;
    result->_offerMessage = self.offerMessage;
    result->_opaqueMessage = self.opaqueMessage;
    return result;
}

- (instancetype)initWithThread:(TSThread *)thread
                  offerMessage:(SSKProtoCallMessageOffer *)offerMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(DBReadTransaction *)transaction
{
    self = [self initWithThread:thread overrideRecipients:@[] transaction:transaction];
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
                   transaction:(DBReadTransaction *)transaction
{
    self = [self initWithThread:thread overrideRecipients:@[] transaction:transaction];
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
                   transaction:(DBReadTransaction *)transaction
{
    self = [self initWithThread:thread overrideRecipients:@[] transaction:transaction];
    if (!self) {
        return self;
    }

    _iceUpdateMessages = iceUpdateMessages;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                 hangupMessage:(SSKProtoCallMessageHangup *)hangupMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
                   transaction:(DBReadTransaction *)transaction
{
    self = [self initWithThread:thread overrideRecipients:@[] transaction:transaction];
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
                   transaction:(DBReadTransaction *)transaction
{
    self = [self initWithThread:thread overrideRecipients:@[] transaction:transaction];
    if (!self) {
        return self;
    }

    _busyMessage = busyMessage;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                 opaqueMessage:(SSKProtoCallMessageOpaque *)opaqueMessage
            overrideRecipients:(nullable NSArray<AciObjC *> *)overrideRecipients
                   transaction:(DBReadTransaction *)transaction
{
    self = [self initWithThread:thread overrideRecipients:overrideRecipients transaction:transaction];
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
                                                  transaction:(DBReadTransaction *)transaction
{
    SSKProtoContentBuilder *builder = [SSKProtoContent builder];
    builder.callMessage = [self buildCallMessage:thread transaction:transaction];
    return builder;
}

- (nullable SSKProtoCallMessage *)buildCallMessage:(TSThread *)thread transaction:(DBReadTransaction *)transaction
{
    SSKProtoCallMessageBuilder *builder = [SSKProtoCallMessage builder];

    BOOL shouldHaveProfileKey = NO;

    if (self.offerMessage) {
        [builder setOffer:self.offerMessage];
        shouldHaveProfileKey = YES;
    }

    if (self.answerMessage) {
        [builder setAnswer:self.answerMessage];
        shouldHaveProfileKey = YES;
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

    if (self.opaqueMessage) {
        [builder setOpaque:self.opaqueMessage];
    }

    if (self.destinationDeviceId != nil) {
        [builder setDestinationDeviceID:self.destinationDeviceId.unsignedIntValue];
    }

    if (shouldHaveProfileKey) {
        [ProtoUtils addLocalProfileKeyIfNecessary:thread callMessageBuilder:builder transaction:transaction];
    }

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
    if (self.offerMessage != nil) {
        return YES;
    } else if (self.opaqueMessage != nil && self.opaqueMessage.hasUrgency) {
        switch (self.opaqueMessage.unwrappedUrgency) {
            case SSKProtoCallMessageOpaqueUrgencyHandleImmediately:
                return YES;
            case SSKProtoCallMessageOpaqueUrgencyDroppable:
                break;
        }
    }

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
        payload = [NSString stringWithFormat:@"iceUpdateMessages: %lu", (unsigned long)self.iceUpdateMessages.count];
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
