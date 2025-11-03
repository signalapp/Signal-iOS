//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncMessageRequestResponseMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncMessageRequestResponseMessage ()

// v0: The sending thread is also the acted-upon thread.
// v1: (skipped to avoid ambiguity)
// v2: The acted-upon thread is stored in groupId/threadAci.
@property (nonatomic, readonly) NSUInteger version;

@property (nonatomic, readonly, nullable) NSData *groupId;
@property (nonatomic, readonly, nullable) NSString *threadAci;
@property (nonatomic, readonly) OWSSyncMessageRequestResponseType responseType;

@end

#pragma mark -

@implementation OWSSyncMessageRequestResponseMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
               messageRequestThread:(TSThread *)thread
                       responseType:(OWSSyncMessageRequestResponseType)responseType
                        transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];

    _version = 2;

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        _groupId = [[(TSGroupThread *)thread groupId] copy];
    } else if ([thread isKindOfClass:[TSContactThread class]]) {
        _threadAci = [[[(TSContactThread *)thread contactAddress] aciString] copy];
        OWSAssertDebug(_threadAci != nil); /* Must have an ACI when responding to a message request. */
    } else {
        OWSFailDebug(@"Can't respond to thread type.");
    }

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
        case OWSSyncMessageRequestResponseType_Spam:
            return SSKProtoSyncMessageMessageRequestResponseTypeSpam;
        case OWSSyncMessageRequestResponseType_BlockAndSpam:
            return SSKProtoSyncMessageMessageRequestResponseTypeBlockAndSpam;
    }
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageMessageRequestResponseBuilder *messageRequestResponseBuilder =
        [SSKProtoSyncMessageMessageRequestResponse builder];
    messageRequestResponseBuilder.type = self.protoResponseType;

    if (self.groupId != nil) {
        messageRequestResponseBuilder.groupID = self.groupId;
    } else if (self.threadAci != nil) {
        if (BuildFlagsObjC.serviceIdStrings) {
            messageRequestResponseBuilder.threadAci = self.threadAci;
        }
        if (BuildFlagsObjC.serviceIdBinaryConstantOverhead) {
            messageRequestResponseBuilder.threadAciBinary =
                [[AciObjC alloc] initWithAciString:self.threadAci].serviceIdBinary;
        }
    } else if (self.version < 2) {
        // Fallback behavior. Messages of this version are no longer created.
        // Eventually, all enqueued messages of this type should be resolved
        // (either because they have been sent or because they ran out of retries).
        TSThread *_Nullable thread = [self threadWithTx:transaction];
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
            ServiceIdObjC *threadAci = contactThread.contactAddress.serviceIdObjC;
            if ([threadAci isKindOfClass:[AciObjC class]]) {
                if (BuildFlagsObjC.serviceIdStrings) {
                    messageRequestResponseBuilder.threadAci = threadAci.serviceIdString;
                }
                if (BuildFlagsObjC.serviceIdBinaryConstantOverhead) {
                    messageRequestResponseBuilder.threadAciBinary = threadAci.serviceIdBinary;
                }
            }
        }
    }

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.messageRequestResponse = [messageRequestResponseBuilder buildInfallibly];
    return builder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
