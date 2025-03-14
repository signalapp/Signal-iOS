//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncFetchLatestMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncFetchLatestMessage ()
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly) OWSSyncFetchType fetchType;

@end

@implementation OWSSyncFetchLatestMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                          fetchType:(OWSSyncFetchType)fetchType
                        transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];

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

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageFetchLatestBuilder *fetchLatestBuilder = [SSKProtoSyncMessageFetchLatest builder];
    fetchLatestBuilder.type = self.protoFetchType;

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    syncMessageBuilder.fetchLatest = [fetchLatestBuilder buildInfallibly];
    return syncMessageBuilder;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

@end

NS_ASSUME_NONNULL_END
