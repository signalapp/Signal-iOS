//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeCallMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@implementation OWSFakeCallMessageHandler

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer
                 fromCaller:(SignalServiceAddress *)caller
               sourceDevice:(uint32_t)device
            sentAtTimestamp:(uint64_t)sentAtTimestamp
    serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
          supportsMultiRing:(BOOL)supportsMultiRing
{
    OWSLogInfo(@"");
}

- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer
            fromCaller:(SignalServiceAddress *)caller
          sourceDevice:(uint32_t)device
     supportsMultiRing:(BOOL)supportsMultiRing
{
    OWSLogInfo(@"");
}

- (void)receivedIceUpdate:(SSKProtoCallMessageIceUpdate *)iceUpdate
               fromCaller:(SignalServiceAddress *)caller
             sourceDevice:(uint32_t)device
{
    OWSLogInfo(@"");
}

- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup
            fromCaller:(SignalServiceAddress *)caller
          sourceDevice:(uint32_t)device
{
    OWSLogInfo(@"");
}

- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy
          fromCaller:(SignalServiceAddress *)caller
        sourceDevice:(uint32_t)device
{
    OWSLogInfo(@"");
}

- (void)receivedOpaque:(SSKProtoCallMessageOpaque *)opaque
                 fromCaller:(SignalServiceAddress *)caller
               sourceDevice:(uint32_t)device
    serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
{
    OWSLogInfo(@"");
}

- (void)receivedGroupCallUpdateMessage:(SSKProtoDataMessageGroupCallUpdate *)update
                             forThread:(TSGroupThread *)groupThread
               serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
{
    OWSLogInfo(@"");
}

@end

#endif

NS_ASSUME_NONNULL_END
