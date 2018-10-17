//  Created by Michael Kirk on 12/8/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSCallHangupMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallHangupMessage

- (instancetype)initWithPeerId:(NSString *)peerId
{
    self = [super init];
    if (!self) {
        return self;
    }

    _peerId = peerId;

    return self;
}

- (OWSSignalServiceProtosCallMessageHangup *)asProtobuf
{
    // TODO: Convert to control message handler
//    OWSSignalServiceProtosCallMessageHangupBuilder *builder = [OWSSignalServiceProtosCallMessageHangupBuilder new];
//
//    builder.id = self.callId;
//
//    return [builder build];
    return [OWSSignalServiceProtosCallMessageHangup new];
}


@end

NS_ASSUME_NONNULL_END
