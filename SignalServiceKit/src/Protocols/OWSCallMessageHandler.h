//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageAnswer;
@class SSKProtoCallMessageBusy;
@class SSKProtoCallMessageHangup;
@class SSKProtoCallMessageIceUpdate;
@class SSKProtoCallMessageOffer;
@class SSKProtoCallMessageOpaque;
@class SSKProtoDataMessageGroupCallUpdate;
@class SignalServiceAddress;
@class TSGroupThread;

@protocol OWSCallMessageHandler <NSObject>

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
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp NS_SWIFT_NAME(receivedOpaque(_:from:sourceDevice:serverReceivedTimestamp:serverDeliveryTimestamp:));

- (void)receivedGroupCallUpdateMessage:(SSKProtoDataMessageGroupCallUpdate *)update
                             forThread:(TSGroupThread *)groupThread
               serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
        NS_SWIFT_NAME(receivedGroupCallUpdateMessage(_:for:serverReceivedTimestamp:));

@end

NS_ASSUME_NONNULL_END
