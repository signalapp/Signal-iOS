//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCallOfferMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

- (nullable SSKProtoCallMessageOffer *)asProtobuf
{
    SSKProtoCallMessageOfferBuilder *builder = [SSKProtoCallMessageOfferBuilder new];

    builder.id = self.callId;
    builder.sessionDescription = self.sessionDescription;
    
    NSError *error;
    SSKProtoCallMessageOffer *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
