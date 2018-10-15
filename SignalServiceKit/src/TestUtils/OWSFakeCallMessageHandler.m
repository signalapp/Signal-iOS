//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeCallMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation OWSFakeCallMessageHandler

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedIceUpdate:(SSKProtoCallMessageIceUpdate *)iceUpdate fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

@end

#endif

NS_ASSUME_NONNULL_END
