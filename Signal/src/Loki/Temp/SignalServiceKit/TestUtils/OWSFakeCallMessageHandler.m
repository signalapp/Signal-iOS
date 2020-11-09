//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeCallMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation OWSFakeCallMessageHandler

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer fromCallerId:(NSString *)callerId
{
    OWSLogInfo(@"");
}

- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer fromCallerId:(NSString *)callerId
{
    OWSLogInfo(@"");
}

- (void)receivedIceUpdate:(SSKProtoCallMessageIceUpdate *)iceUpdate fromCallerId:(NSString *)callerId
{
    OWSLogInfo(@"");
}

- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup fromCallerId:(NSString *)callerId
{
    OWSLogInfo(@"");
}

- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy fromCallerId:(NSString *)callerId
{
    OWSLogInfo(@"");
}

@end

#endif

NS_ASSUME_NONNULL_END
