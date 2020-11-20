//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingGroupCallMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation OWSOutgoingGroupCallMessage

- (instancetype)initWithThread:(TSGroupThread *)thread
{
    OWSAssertDebug(thread);

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
    OWSAssertDebug(thread.isGroupThread);

    NSError *_Nullable error = nil;
    SSKProtoDataMessageGroupCallUpdateBuilder *updateBuilder = [SSKProtoDataMessageGroupCallUpdate builder];
    SSKProtoDataMessageGroupCallUpdate *_Nullable updateMessage = [updateBuilder buildAndReturnError:&error];
    if (error || !updateMessage) {
        OWSFailDebug(@"Couldn't build GroupCallUpdate message");
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    [builder setGroupCallUpdate:updateMessage];
    return builder;
}

@end
