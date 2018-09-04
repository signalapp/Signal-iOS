//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSEndSessionMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSEndSessionMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread
{
    return [super initOutgoingMessageWithTimestamp:timestamp
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    SSKProtoDataMessageBuilder *_Nullable builder = [super dataMessageBuilder];
    if (!builder) {
        return nil;
    }
    [builder setTimestamp:self.timestamp];
    [builder setFlags:SSKProtoDataMessageFlagsEndSession];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
