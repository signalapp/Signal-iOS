//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGroupsOutputStream.h"
#import "MIMETypeUtil.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import <ProtocolBuffers/CodedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSGroupsOutputStream

- (void)writeGroup:(TSGroupModel *)group
{
    OWSSignalServiceProtosGroupDetailsBuilder *groupBuilder = [OWSSignalServiceProtosGroupDetailsBuilder new];
    [groupBuilder setId:group.groupId];
    [groupBuilder setName:group.groupName];
    [groupBuilder setMembersArray:group.groupMemberIds];

    NSData *avatarPng;
    if (group.groupImage) {
        OWSSignalServiceProtosGroupDetailsAvatarBuilder *avatarBuilder =
            [OWSSignalServiceProtosGroupDetailsAvatarBuilder new];

        [avatarBuilder setContentType:OWSMimeTypeImagePng];
        avatarPng = UIImagePNGRepresentation(group.groupImage);
        [avatarBuilder setLength:(uint32_t)avatarPng.length];
        [groupBuilder setAvatarBuilder:avatarBuilder];
    }

    NSData *groupData = [[groupBuilder build] data];
    uint32_t groupDataLength = (uint32_t)groupData.length;
    [self.delegateStream writeRawVarint32:groupDataLength];
    [self.delegateStream writeRawData:groupData];

    TSGroupThread *_Nullable groupThread = [TSGroupThread threadWithGroupId:group.groupId];
    if (groupThread) {
        OWSDisappearingMessagesConfiguration *_Nullable disappearingMessagesConfiguration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:groupThread.uniqueId];

        if (disappearingMessagesConfiguration && disappearingMessagesConfiguration.isEnabled) {
            [groupBuilder setExpireTimer:disappearingMessagesConfiguration.durationSeconds];
        }
    }

    if (avatarPng) {
        [self.delegateStream writeRawData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
