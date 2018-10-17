//  Created by Michael Kirk on 12/6/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSCallIceUpdateMessage.h"
#import "OWSSignalServiceProtos.pb.h"

@implementation OWSCallIceUpdateMessage

- (instancetype)initWithPeerId:(NSString *)peerId
                           sdp:(NSString *)sdp
                 sdpMLineIndex:(SInt32)sdpMLineIndex
                        sdpMid:(nullable NSString *)sdpMid
{
    self = [super init];
    if (!self) {
        return self;
    }

    _peerId = peerId;
    _sdp = sdp;
    _sdpMLineIndex = sdpMLineIndex;
    _sdpMid = sdpMid;

    return self;
}

- (OWSSignalServiceProtosCallMessageIceUpdate *)asProtobuf
{
    //  TODO: Replace with control message handling
//    OWSSignalServiceProtosCallMessageIceUpdateBuilder *builder =
//        [OWSSignalServiceProtosCallMessageIceUpdateBuilder new];
//
//    [builder setId:self.peerId];
//    [builder setSdp:self.sdp];
//    [builder setSdpMlineIndex:self.sdpMLineIndex];
//    [builder setSdpMid:self.sdpMid];
//
//    return [builder build];
    return [OWSSignalServiceProtosCallMessageIceUpdate new];
}

@end
