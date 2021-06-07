//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSSyncFetchLatestMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncFetchLatestMessage ()

@property (nonatomic, readonly) OWSSyncFetchType fetchType;

@end

@implementation OWSSyncFetchLatestMessage

- (instancetype)initWithThread:(TSThread *)thread fetchType:(OWSSyncFetchType)fetchType
{
    self = [super initWithThread:thread];

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

@end

NS_ASSUME_NONNULL_END
