//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallBusyMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallBusyMessage

- (instancetype)initWithPeerId:(NSString *)peerId
{
    self = [super init];
    if (!self) {
        return self;
    }

    _peerId = peerId;

    return self;
}

// TODO: Convert to control message
- (OWSSignalServiceProtosCallMessageBusy *)asProtobuf
{
//    OWSSignalServiceProtosCallMessageBusyBuilder *builder = [OWSSignalServiceProtosCallMessageBusyBuilder new];
//
//    builder.id = self.peerId;
//
//    return [builder build];
    
    return [OWSSignalServiceProtosCallMessageBusy new];
}

@end

NS_ASSUME_NONNULL_END
