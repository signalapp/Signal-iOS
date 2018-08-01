//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncGroupsMessage.h"
#import "NSDate+OWS.h"
#import "OWSGroupsOutputStream.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSSyncGroupsMessage

- (instancetype)init
{
    return [super init];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (SSKProtoSyncMessageBuilder *)syncMessageBuilder
{

    if (self.attachmentIds.count != 1) {
        DDLogError(@"expected sync groups message to have exactly one attachment, but found %lu",
            (unsigned long)self.attachmentIds.count);
    }
    SSKProtoAttachmentPointer *attachmentProto = [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject];

    SSKProtoSyncMessageGroupsBuilder *groupsBuilder =
        [SSKProtoSyncMessageGroupsBuilder new];

    [groupsBuilder setBlob:attachmentProto];

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessageBuilder new];
    [syncMessageBuilder setGroupsBuilder:groupsBuilder];

    return syncMessageBuilder;
}

- (NSData *)buildPlainTextAttachmentDataWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    // TODO use temp file stream to avoid loading everything into memory at once
    // First though, we need to re-engineer our attachment process to accept streams (encrypting with stream,
    // and uploading with streams).
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSGroupsOutputStream *groupsOutputStream = [OWSGroupsOutputStream streamWithOutputStream:dataOutputStream];

    [TSGroupThread
        enumerateCollectionObjectsWithTransaction:transaction
                                       usingBlock:^(id obj, BOOL *stop) {
                                           if (![obj isKindOfClass:[TSGroupThread class]]) {
                                               if (![obj isKindOfClass:[TSContactThread class]]) {
                                                   DDLogWarn(
                                                       @"Ignoring non group thread in thread collection: %@", obj);
                                               }
                                               return;
                                           }
                                           TSGroupThread *groupThread = (TSGroupThread *)obj;
                                           [groupsOutputStream writeGroup:groupThread transaction:transaction];
                                       }];

    [groupsOutputStream flush];
    [dataOutputStream close];

    return [dataOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
}

@end

NS_ASSUME_NONNULL_END
