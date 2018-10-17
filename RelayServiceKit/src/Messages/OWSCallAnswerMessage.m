//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallAnswerMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import <RelayServiceKit/RelayServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallAnswerMessage

- (instancetype)initWithPeerId:(NSString *)peerId sessionDescription:(NSString *)sessionDescription
{
    self = [super init];
    if (!self) {
        return self;
    }

    _peerId = peerId;
    _sessionDescription = sessionDescription;

    return self;
}

//-(OutgoingControlMessage *)asOutgoingControlMessage
//{
//    
//    
//    return OutgoingControlMessage()
//}

- (OWSSignalServiceProtosCallMessageAnswer *)asProtobuf
{
//    OWSSignalServiceProtosCallMessageAnswerBuilder *builder = [OWSSignalServiceProtosCallMessageAnswerBuilder new];
//
//    builder.id = self.callId;
//    builder.sessionDescription = self.sessionDescription;
//
//    return [builder build];
    return [OWSSignalServiceProtosCallMessageAnswer new];
}

@end

NS_ASSUME_NONNULL_END
