//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncGroupsMessage.h"
#import "OWSGroupsOutputStream.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

- (nullable NSData *)buildPlainTextAttachmentDataWithTransaction:(SDSAnyReadTransaction *)transaction
{
    // TODO use temp file stream to avoid loading everything into memory at once
    // First though, we need to re-engineer our attachment process to accept streams (encrypting with stream,
    // and uploading with streams).
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSGroupsOutputStream *groupsOutputStream = [[OWSGroupsOutputStream alloc] initWithOutputStream:dataOutputStream];

    [TSGroupThread
        anyEnumerateWithTransaction:transaction
                            batched:YES
                              block:^(TSThread *thread, BOOL *stop) {
                                  if (![thread isKindOfClass:[TSGroupThread class]]) {
                                      if (![thread isKindOfClass:[TSContactThread class]]) {
                                          OWSLogWarn(@"Ignoring non group thread in thread collection: %@", thread);
                                      }
                                      return;
                                  }
                                  TSGroupThread *groupThread = (TSGroupThread *)thread;
                                  // We only sync v1 groups via group sync messages.
                                  if (groupThread.isGroupV2Thread) {
                                      return;
                                  }

                                  [groupsOutputStream writeGroup:groupThread transaction:transaction];
                              }];

    [dataOutputStream close];

    if (groupsOutputStream.hasError) {
        OWSFailDebug(@"Could not write groups sync stream.");
        return nil;
    }

    return [dataOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
}

@end

NS_ASSUME_NONNULL_END
