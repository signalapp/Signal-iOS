//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSSyncGroupsMessage.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachment.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSSyncGroupsMessage

- (instancetype)init
{
    return [super initWithTimestamp:[NSDate ows_millisecondTimeStamp]];
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // no-op

    // There's no need to save this message, since it's not displayed to the user.
    // Furthermore if we did save it, we probably don't want to save the conctactsManager property.
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{

    if (self.attachmentIds.count != 1) {
        DDLogError(@"expected sync groups message to have exactly one attachment, but found %lu",
            (unsigned long)self.attachmentIds.count);
    }
    OWSSignalServiceProtosAttachmentPointer *attachmentProto =
        [self buildAttachmentProtoForAttachmentId:self.attachmentIds[0]];

    OWSSignalServiceProtosSyncMessageGroupsBuilder *groupsBuilder =
        [OWSSignalServiceProtosSyncMessageGroupsBuilder new];

    [groupsBuilder setBlob:attachmentProto];

    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    [syncMessageBuilder setGroupsBuilder:groupsBuilder];

    return [syncMessageBuilder build];
}

- (NSData *)buildPlainTextAttachmentData
{
    NSString *fileName =
        [NSString stringWithFormat:@"%@_%@", [[NSProcessInfo processInfo] globallyUniqueString], @"contacts.dat"];
    NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    NSOutputStream *fileOutputStream = [NSOutputStream outputStreamWithURL:fileURL append:NO];
    [fileOutputStream open];

    PBCodedOutputStream *outputStream = [PBCodedOutputStream streamWithOutputStream:fileOutputStream];
    DDLogInfo(@"Writing groups data to %@", fileURL);
    [TSGroupThread enumerateCollectionObjectsUsingBlock:^(id obj, BOOL *stop) {
        if (![obj isKindOfClass:[TSGroupThread class]]) {
            DDLogError(@"Unexpected class in group collection: %@", obj);
            return;
        }
        TSGroupModel *group = ((TSGroupThread *)obj).groupModel;
        OWSSignalServiceProtosGroupDetailsBuilder *groupBuilder = [OWSSignalServiceProtosGroupDetailsBuilder new];
        [groupBuilder setId:group.groupId];
        [groupBuilder setName:group.groupName];
        [groupBuilder setMembersArray:group.groupMemberIds];

        NSData *avatarPng;
        if (group.groupImage) {
            OWSSignalServiceProtosGroupDetailsAvatarBuilder *avatarBuilder =
                [OWSSignalServiceProtosGroupDetailsAvatarBuilder new];

            [avatarBuilder setContentType:@"image/png"];
            avatarPng = UIImagePNGRepresentation(group.groupImage);
            [avatarBuilder setLength:(uint32_t)avatarPng.length];
            [groupBuilder setAvatarBuilder:avatarBuilder];
        }

        NSData *groupData = [[groupBuilder build] data];
        uint32_t groupDataLength = (uint32_t)groupData.length;
        [outputStream writeRawVarint32:groupDataLength];
        [outputStream writeRawData:groupData];

        if (avatarPng) {
            [outputStream writeRawData:avatarPng];
        }
    }];

    [outputStream flush];
    [fileOutputStream close];

    // TODO pass stream to builder rather than data as a singular hulk.
    [NSInputStream inputStreamWithURL:fileURL];
    NSError *error;
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:&error];
    if (error) {
        DDLogError(@"Failed to read back contact data after writing it to %@ with error:%@", fileURL, error);
    }
    return data;

    //    TODO delete contacts file.
    //    NSError *error;
    //    NSFileManager *manager = [NSFileManager defaultManager];
    //    [manager removeItemAtURL:fileURL error:&error];
    //    if (error) {
    //        DDLogError(@"Failed removing temp file at url:%@ with error:%@", fileURL, error);
    //    }
}

@end

NS_ASSUME_NONNULL_END
