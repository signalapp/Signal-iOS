//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncMessageRequestResponseMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncMessageRequestResponseMessage ()

@property (nonatomic, readonly) OWSSyncMessageRequestResponseType responseType;

@end

#pragma mark -

@implementation OWSSyncMessageRequestResponseMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithThread:(TSThread *)thread responseType:(OWSSyncMessageRequestResponseType)responseType
{
    self = [super initWithThread:thread];

    _responseType = responseType;

    return self;
}

- (SSKProtoSyncMessageMessageRequestResponseType)protoResponseType
{
    switch (self.responseType) {
        case OWSSyncMessageRequestResponseType_Accept:
            return SSKProtoSyncMessageMessageRequestResponseTypeAccept;
        case OWSSyncMessageRequestResponseType_Delete:
            return SSKProtoSyncMessageMessageRequestResponseTypeDelete;
        case OWSSyncMessageRequestResponseType_Block:
            return SSKProtoSyncMessageMessageRequestResponseTypeBlock;
        case OWSSyncMessageRequestResponseType_BlockAndDelete:
            return SSKProtoSyncMessageMessageRequestResponseTypeBlockAndDelete;
    }
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction;
{
    SSKProtoSyncMessageMessageRequestResponseBuilder *messageRequestResponseBuilder =
        [SSKProtoSyncMessageMessageRequestResponse builder];
    messageRequestResponseBuilder.type = self.protoResponseType;

    TSThread *_Nullable thread = [self threadWithTransaction:transaction];
    if (!thread) {
        OWSFailDebug(@"Missing thread for message request response");
        return nil;
    }

    if (thread.isGroupThread) {
        OWSAssertDebug([thread isKindOfClass:[TSGroupThread class]]);
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        messageRequestResponseBuilder.groupID = groupThread.groupModel.groupId;
    } else {
        OWSAssertDebug([thread isKindOfClass:[TSContactThread class]]);
        TSContactThread *contactThread = (TSContactThread *)thread;
        messageRequestResponseBuilder.threadUuid = contactThread.contactAddress.uuidString;
        messageRequestResponseBuilder.threadE164 = contactThread.contactAddress.phoneNumber;
    }

    NSError *error;
    SSKProtoSyncMessageMessageRequestResponse *_Nullable messageRequestResponse =
        [messageRequestResponseBuilder buildAndReturnError:&error];
    if (error || !messageRequestResponse) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.messageRequestResponse = messageRequestResponse;
    return builder;
}

@end

NS_ASSUME_NONNULL_END
