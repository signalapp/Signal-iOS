//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSGroupInfoRequestMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSGroupInfoRequestMessage ()

@property (nonatomic) NSData *groupId;

@end

#pragma mark -

@implementation OWSGroupInfoRequestMessage

- (instancetype)initWithThread:(TSThread *)thread
                       groupId:(NSData *)groupId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];
    if (!self) {
        return self;
    }

    OWSAssertDebug(groupId.length > 0);
    _groupId = groupId;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContext builderWithId:self.groupId];
    [groupContextBuilder setType:SSKProtoGroupContextTypeRequestInfo];

    NSError *error;
    SSKProtoGroupContext *_Nullable groupContextProto = [groupContextBuilder buildAndReturnError:&error];
    if (error || !groupContextProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [SSKProtoDataMessage builder];
    [builder setTimestamp:self.timestamp];
    [builder setGroup:groupContextProto];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
