//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileKeyMessage.h"
#import "ProfileManagerProtocol.h"
#import "ProtoUtils.h"
#import "SSKEnvironment.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSProfileKeyMessage

- (instancetype)initWithThread:(TSThread *)thread
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    return [super initOutgoingMessageWithBuilder:messageBuilder];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable SSKProtoDataMessage *)buildDataMessage:(SignalServiceAddress *_Nullable)address
                                            thread:(TSThread *)thread
                                       transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread != nil);

    SSKProtoDataMessageBuilder *_Nullable builder = [self dataMessageBuilderWithThread:thread transaction:transaction];
    if (!builder) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }
    [builder setTimestamp:self.timestamp];
    [ProtoUtils addLocalProfileKeyToDataMessageBuilder:builder];
    [builder setFlags:SSKProtoDataMessageFlagsProfileKeyUpdate];

    NSError *error;
    SSKProtoDataMessage *_Nullable dataProto = [builder buildAndReturnError:&error];
    if (error || !dataProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    return dataProto;
}

@end

NS_ASSUME_NONNULL_END
