//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSSyncGroupsMessage.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSGroupsOutputStream.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSSyncGroupsMessage

- (instancetype)initWithThread:(TSThread *)thread
{
    return [super initWithThread:thread];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (self.attachmentIds.count != 1) {
        OWSLogError(@"expected sync groups message to have exactly one attachment, but found %lu",
            (unsigned long)self.attachmentIds.count);
    }

    SSKProtoAttachmentPointer *_Nullable attachmentProto =
        [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject transaction:transaction];
    if (!attachmentProto) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }

    SSKProtoSyncMessageGroupsBuilder *groupsBuilder = [SSKProtoSyncMessageGroups builder];
    [groupsBuilder setBlob:attachmentProto];

    NSError *error;
    SSKProtoSyncMessageGroups *_Nullable groupsProto = [groupsBuilder buildAndReturnError:&error];
    if (error || !groupsProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setGroups:groupsProto];

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
