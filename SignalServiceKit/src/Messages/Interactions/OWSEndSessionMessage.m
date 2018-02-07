//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSEndSessionMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSEndSessionMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread
{
    return [super initOutgoingMessageWithTimestamp:timestamp
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMessageNone
                                     quotedMessage:nil];
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    OWSSignalServiceProtosDataMessageBuilder *builder = [super dataMessageBuilder];
    [builder setTimestamp:self.timestamp];
    [builder setFlags:OWSSignalServiceProtosDataMessageFlagsEndSession];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
