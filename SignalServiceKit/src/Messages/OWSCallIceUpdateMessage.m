//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCallIceUpdateMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

- (nullable SSKProtoCallMessageIceUpdate *)asProtobuf
{
    SSKProtoCallMessageIceUpdateBuilder *builder =
        [SSKProtoCallMessageIceUpdateBuilder new];

    [builder setId:self.callId];
    [builder setSdp:self.sdp];
    [builder setSdpMlineIndex:self.sdpMLineIndex];
    [builder setSdpMid:self.sdpMid];

    NSError *error;
    SSKProtoCallMessageIceUpdate *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return result;    
}

@end
