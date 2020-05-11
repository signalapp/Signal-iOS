//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingDeleteMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingDeleteMessage ()

@property (nonatomic, readonly) uint64_t messageTimestamp;

@end

#pragma mark -

@implementation TSOutgoingDeleteMessage

- (instancetype)initWithThread:(TSThread *)thread message:(TSMessage *)message
{
    OWSAssertDebug([thread.uniqueId isEqualToString:message.uniqueThreadId]);

    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder];
    if (!self) {
        return self;
    }

    _messageTimestamp = message.timestamp;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoDataMessageDeleteBuilder *deleteBuilder =
        [SSKProtoDataMessageDelete builderWithTargetSentTimestamp:self.messageTimestamp];

    NSError *error;
    SSKProtoDataMessageDelete *_Nullable deleteProto = [deleteBuilder buildAndReturnError:&error];
    if (error || !deleteProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [super dataMessageBuilderWithThread:thread transaction:transaction];
    [builder setTimestamp:self.timestamp];
    [builder setDelete:deleteProto];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
