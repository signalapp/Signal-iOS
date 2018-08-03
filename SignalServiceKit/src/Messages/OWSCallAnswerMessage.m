//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCallAnswerMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

- (nullable SSKProtoCallMessageAnswer *)asProtobuf
{
    SSKProtoCallMessageAnswerBuilder *builder = [SSKProtoCallMessageAnswerBuilder new];

    builder.id = self.callId;
    builder.sessionDescription = self.sessionDescription;
    
    NSError *error;
    SSKProtoCallMessageAnswer *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
