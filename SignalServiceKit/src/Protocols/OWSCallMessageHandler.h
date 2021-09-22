//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SSKProtoCallMessage;
@class SSKProtoCallMessageAnswer;
@class SSKProtoCallMessageBusy;
@class SSKProtoCallMessageHangup;
@class SSKProtoCallMessageIceUpdate;
@class SSKProtoCallMessageOffer;
@class SSKProtoCallMessageOpaque;
@class SSKProtoDataMessageGroupCallUpdate;
@class SSKProtoEnvelope;
@class SignalServiceAddress;
@class TSGroupThread;

typedef NS_ENUM(NSUInteger, OWSCallMessageAction) {
    // This message should not be processed
    OWSCallMessageActionIgnore,
    // Process the message by deferring to -externallyHandleCallMessage...
    OWSCallMessageActionHandoff,
    // Process the message normally
    OWSCallMessageActionProcess,
};

@protocol OWSCallMessageHandler <NSObject>

/// Informs caller of how the handler would like to handle this message
- (OWSCallMessageAction)actionForEnvelope:(SSKProtoEnvelope *)envelope callMessage:(SSKProtoCallMessage *)message;

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer
                 fromCaller:(SignalServiceAddress *)caller
               sourceDevice:(uint32_t)device
            sentAtTimestamp:(uint64_t)sentAtTimestamp
    serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
          supportsMultiRing:(BOOL)supportsMultiRing NS_SWIFT_NAME(receivedOffer(_:from:sourceDevice:sentAtTimestamp:serverReceivedTimestamp:serverDeliveryTimestamp:supportsMultiRing:));

- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer
            fromCaller:(SignalServiceAddress *)caller
          sourceDevice:(uint32_t)device
     supportsMultiRing:(BOOL)supportsMultiRing NS_SWIFT_NAME(receivedAnswer(_:from:sourceDevice:supportsMultiRing:));

- (void)receivedIceUpdate:(NSArray<SSKProtoCallMessageIceUpdate *> *)iceUpdate
               fromCaller:(SignalServiceAddress *)caller
             sourceDevice:(uint32_t)device NS_SWIFT_NAME(receivedIceUpdate(_:from:sourceDevice:));

- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup
            fromCaller:(SignalServiceAddress *)caller
          sourceDevice:(uint32_t)device NS_SWIFT_NAME(receivedHangup(_:from:sourceDevice:));

- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy
          fromCaller:(SignalServiceAddress *)caller
        sourceDevice:(uint32_t)device NS_SWIFT_NAME(receivedBusy(_:from:sourceDevice:));

- (void)receivedOpaque:(SSKProtoCallMessageOpaque *)opaque
                 fromCaller:(SignalServiceAddress *)caller
               sourceDevice:(uint32_t)device
    serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(receivedOpaque(_:from:sourceDevice:serverReceivedTimestamp:serverDeliveryTimestamp:transaction:));

- (void)receivedGroupCallUpdateMessage:(SSKProtoDataMessageGroupCallUpdate *)update
                             forThread:(TSGroupThread *)groupThread
               serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
        NS_SWIFT_NAME(receivedGroupCallUpdateMessage(_:for:serverReceivedTimestamp:));

- (void)externallyHandleCallMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                  plaintextData:(NSData *)plaintextData
                                wasReceivedByUD:(BOOL)wasReceivedByUD
                        serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                                    transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(externallyHandleCallMessage(envelope:plaintextData:wasReceivedByUD:serverDeliveryTimestamp:transaction:));

@end

NS_ASSUME_NONNULL_END
