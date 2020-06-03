//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSEndSessionMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSEndSessionMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithThread:(TSThread *)thread
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    return [super initOutgoingMessageWithBuilder:messageBuilder];
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoDataMessageBuilder *_Nullable builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    if (!builder) {
        return nil;
    }
    [builder setTimestamp:self.timestamp];
    [builder setFlags:SSKProtoDataMessageFlagsEndSession];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
