//  Created by Michael Kirk on 12/6/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSCallIceUpdateMessage.h"
#import "OWSSignalServiceProtos.pb.h"

@implementation OWSCallIceUpdateMessage

- (instancetype)initWithCallId:(UInt64)callId
                           sdp:(NSString *)sdp
                 sdpMLineIndex:(SInt32)sdpMLineIndex
                        sdpMid:(nullable NSString *)sdpMid
{
    self = [super init];
    if (!self) {
        return self;
    }

    _callId = callId;
    _sdp = sdp;
    _sdpMLineIndex = sdpMLineIndex;
    _sdpMid = sdpMid;

    return self;
}

- (OWSSignalServiceProtosCallMessageIceUpdate *)asProtobuf
{
    OWSSignalServiceProtosCallMessageIceUpdateBuilder *builder =
        [OWSSignalServiceProtosCallMessageIceUpdateBuilder new];

    [builder setId:self.callId];
    [builder setSdp:self.sdp];
    [builder setSdpMlineIndex:self.sdpMLineIndex];
    [builder setSdpMid:self.sdpMid];

    return [builder build];
}

@end
