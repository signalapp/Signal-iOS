//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeCallMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@implementation OWSFakeCallMessageHandler

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer
           fromCaller:(SignalServiceAddress *)caller
      sentAtTimestamp:(uint64_t)sentAtTimestamp
{
    OWSLogInfo(@"");
}

- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer fromCaller:(SignalServiceAddress *)caller
{
    OWSLogInfo(@"");
}

- (void)receivedIceUpdate:(SSKProtoCallMessageIceUpdate *)iceUpdate fromCaller:(SignalServiceAddress *)caller
{
    OWSLogInfo(@"");
}

- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup fromCaller:(SignalServiceAddress *)caller
{
    OWSLogInfo(@"");
}

- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy fromCaller:(SignalServiceAddress *)caller
{
    OWSLogInfo(@"");
}

@end

#endif

NS_ASSUME_NONNULL_END
