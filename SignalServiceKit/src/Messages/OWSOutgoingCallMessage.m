//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"
#import "ProtoUtils.h"
#import "SignalRecipient.h"
#import "TSContactThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingCallMessage

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (instancetype)initWithThread:(TSThread *)thread
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder];
    if (!self) {
        return self;
    }

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread
                  offerMessage:(SSKProtoCallMessageOffer *)offerMessage
           destinationDeviceId:(nullable NSNumber *)destinationDeviceId
{
    self = [self initWithThread:thread];
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
{
    self = [self initWithThread:thread];
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
{
    self = [self initWithThread:thread];
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
{
    self = [self initWithThread:thread];
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
{
    self = [self initWithThread:thread];
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
{
    self = [self initWithThread:thread];
    if (!self) {
        return self;
    }

    _busyMessage = busyMessage;
    _destinationDeviceId = destinationDeviceId;

    return self;
}

- (instancetype)initWithThread:(TSThread *)thread opaqueMessage:(SSKProtoCallMessageOpaque *)opaqueMessage
{
    self = [self initWithThread:thread];
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

- (BOOL)isSilent
{
    // Avoid "phantom messages" for "outgoing call messages".

    return YES;
}

- (nullable NSData *)buildPlainTextData:(SignalServiceAddress *)address
                                 thread:(TSThread *)thread
                            transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    SSKProtoContentBuilder *builder = [SSKProtoContent builder];
    builder.callMessage = [self buildCallMessage:address thread:thread transaction:transaction];

    NSError *error;
    NSData *_Nullable data = [builder buildSerializedDataAndReturnError:&error];
    if (error || !data) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return nil;
    }
    return data;
}

- (nullable SSKProtoCallMessage *)buildCallMessage:(SignalServiceAddress *)address
                                            thread:(TSThread *)thread
                                       transaction:(SDSAnyReadTransaction *)transaction
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
                                      address:address
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

@end

NS_ASSUME_NONNULL_END
