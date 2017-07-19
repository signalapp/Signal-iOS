//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallAnswerMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallAnswerMessage

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

- (OWSSignalServiceProtosCallMessageAnswer *)asProtobuf
{
    OWSSignalServiceProtosCallMessageAnswerBuilder *builder = [OWSSignalServiceProtosCallMessageAnswerBuilder new];

    builder.id = self.callId;
    builder.sessionDescription = self.sessionDescription;

    return [builder build];
}

@end

NS_ASSUME_NONNULL_END
