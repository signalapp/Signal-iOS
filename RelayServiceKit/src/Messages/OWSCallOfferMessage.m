//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallOfferMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import <RelayServiceKit/RelayServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallOfferMessage

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

-(OutgoingControlMessage *)asOutgoingControlMessasge
{
    // TODO: Make this useful
    return [OutgoingControlMessage new];
}

- (OWSSignalServiceProtosCallMessageOffer *)asProtobuf
{
//    OWSSignalServiceProtosCallMessageOfferBuilder *builder = [OWSSignalServiceProtosCallMessageOfferBuilder new];
//
//    builder.id = self.peerId;
//    builder.sessionDescription = self.sessionDescription;
//
//    return [builder build];
    return [OWSSignalServiceProtosCallMessageOffer new];
}

@end

NS_ASSUME_NONNULL_END
