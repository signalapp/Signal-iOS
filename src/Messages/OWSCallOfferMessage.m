//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallOfferMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallOfferMessage

- (instancetype)initWithCallId:(UInt64)callId sessionDescription:(NSString *)sessionDescription
{
    self = [super init];
    if (!self) {
        return self;
    }

    _callId = callId;
    _sessionDescription = sessionDescription;

    return self;
}

- (OWSSignalServiceProtosCallMessageOffer *)asProtobuf
{
    OWSSignalServiceProtosCallMessageOfferBuilder *builder = [OWSSignalServiceProtosCallMessageOfferBuilder new];

    builder.id = self.callId;
    builder.sessionDescription = self.sessionDescription;

    return [builder build];
}

@end

NS_ASSUME_NONNULL_END
