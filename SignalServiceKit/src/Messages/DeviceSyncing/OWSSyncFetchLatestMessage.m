//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncFetchLatestMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncFetchLatestMessage ()

@property (nonatomic, readonly) OWSSyncFetchType fetchType;

@end

@implementation OWSSyncFetchLatestMessage

- (instancetype)initWithThread:(TSThread *)thread
                     fetchType:(OWSSyncFetchType)fetchType
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];

    _fetchType = fetchType;

    return self;
}

- (SSKProtoSyncMessageFetchLatestType)protoFetchType
{
    switch (self.fetchType) {
        case OWSSyncFetchType_Unknown:
            return SSKProtoSyncMessageFetchLatestTypeUnknown;
        case OWSSyncFetchType_LocalProfile:
            return SSKProtoSyncMessageFetchLatestTypeLocalProfile;
        case OWSSyncFetchType_StorageManifest:
            return SSKProtoSyncMessageFetchLatestTypeStorageManifest;
        case OWSSyncFetchType_SubscriptionStatus:
            return SSKProtoSyncMessageFetchLatestTypeSubscriptionStatus;
    }
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageFetchLatestBuilder *fetchLatestBuilder = [SSKProtoSyncMessageFetchLatest builder];
    fetchLatestBuilder.type = self.protoFetchType;

    NSError *error;
    SSKProtoSyncMessageFetchLatest *_Nullable fetchLatest = [fetchLatestBuilder buildAndReturnError:&error];
    if (error || !fetchLatest) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    syncMessageBuilder.fetchLatest = fetchLatest;
    return syncMessageBuilder;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

@end

NS_ASSUME_NONNULL_END
