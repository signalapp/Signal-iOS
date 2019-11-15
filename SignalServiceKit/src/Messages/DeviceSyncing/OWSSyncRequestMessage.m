//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncRequestMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncRequestMessage ()

@property (nonatomic, readonly) OWSSyncRequestType requestType;

@end

@implementation OWSSyncRequestMessage

- (instancetype)initWithThread:(TSThread *)thread requestType:(OWSSyncRequestType)requestType
{
    self = [super initWithThread:thread];

    _requestType = requestType;

    return self;
}

- (SSKProtoSyncMessageRequestType)protoRequestType
{
    switch (self.requestType) {
        case OWSSyncRequestType_Unknown:
            return SSKProtoSyncMessageRequestTypeUnknown;
        case OWSSyncRequestType_Contacts:
            return SSKProtoSyncMessageRequestTypeContacts;
        case OWSSyncRequestType_Groups:
            return SSKProtoSyncMessageRequestTypeGroups;
        case OWSSyncRequestType_Blocked:
            return SSKProtoSyncMessageRequestTypeBlocked;
        case OWSSyncRequestType_Configuration:
            return SSKProtoSyncMessageRequestTypeConfiguration;
        case OWSSyncRequestType_Keys:
            return SSKProtoSyncMessageRequestTypeKeys;
    }
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction;
{
    SSKProtoSyncMessageRequestBuilder *requestBuilder = [SSKProtoSyncMessageRequest builder];
    requestBuilder.type = self.protoRequestType;

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

@end

NS_ASSUME_NONNULL_END
