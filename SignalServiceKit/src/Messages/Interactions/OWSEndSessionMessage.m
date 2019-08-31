//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSEndSessionMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSEndSessionMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread
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
                                      contactShare:nil
                                       linkPreview:nil
                                    messageSticker:nil
                                 isViewOnceMessage:NO];
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoDataMessageBuilder *_Nullable builder = [super dataMessageBuilderWithTransaction:transaction];
    if (!builder) {
        return nil;
    }
    [builder setTimestamp:self.timestamp];
    [builder setFlags:SSKProtoDataMessageFlagsEndSession];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
