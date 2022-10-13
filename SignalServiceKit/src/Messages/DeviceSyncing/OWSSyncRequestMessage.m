//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncRequestMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncRequestMessage ()

@property (nonatomic, readonly) SSKProtoSyncMessageRequestType requestType;

@end

@implementation OWSSyncRequestMessage

- (instancetype)initWithThread:(TSThread *)thread
                   requestType:(SSKProtoSyncMessageRequestType)requestType
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];

    _requestType = requestType;

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageRequestBuilder *requestBuilder = [SSKProtoSyncMessageRequest builder];
    requestBuilder.type = self.requestType;

    NSError *error;
    SSKProtoSyncMessageRequest *_Nullable messageRequest = [requestBuilder buildAndReturnError:&error];
    if (error || !messageRequest) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.request = messageRequest;
    return builder;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

@end

NS_ASSUME_NONNULL_END
