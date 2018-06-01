//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncGroupsMessage.h"
#import "NSDate+OWS.h"
#import "OWSGroupsOutputStream.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSSyncGroupsMessage

- (instancetype)init
{
    return [super init];
}

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{

    if (self.attachmentIds.count != 1) {
        DDLogError(@"expected sync groups message to have exactly one attachment, but found %lu",
            (unsigned long)self.attachmentIds.count);
    }
    OWSSignalServiceProtosAttachmentPointer *attachmentProto = [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject];

    OWSSignalServiceProtosSyncMessageGroupsBuilder *groupsBuilder =
        [OWSSignalServiceProtosSyncMessageGroupsBuilder new];

    [groupsBuilder setBlob:attachmentProto];

    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
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
                                               DDLogVerbose(@"Ignoring non group thread in thread collection: %@", obj);
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
