//  Created by Michael Kirk on 12/18/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFakeCallMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFakeCallMessageHandler

- (void)receivedOffer:(OWSSignalServiceProtosCallMessageOffer *)offer fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedAnswer:(OWSSignalServiceProtosCallMessageAnswer *)answer fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedIceUpdate:(OWSSignalServiceProtosCallMessageIceUpdate *)iceUpdate fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedHangup:(OWSSignalServiceProtosCallMessageHangup *)hangup fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)receivedBusy:(OWSSignalServiceProtosCallMessageBusy *)busy fromCallerId:(NSString *)callerId
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

@end

NS_ASSUME_NONNULL_END
