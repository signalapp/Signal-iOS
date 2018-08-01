//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGroupsOutputStream.h"
#import "MIMETypeUtil.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import <ProtocolBuffers/CodedOutputStream.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSGroupsOutputStream

- (void)writeGroup:(TSGroupThread *)groupThread transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(groupThread);
    OWSAssert(transaction);

    TSGroupModel *group = groupThread.groupModel;
    OWSAssert(group);

    SSKProtoGroupDetailsBuilder *groupBuilder = [SSKProtoGroupDetailsBuilder new];
    [groupBuilder setId:group.groupId];
    [groupBuilder setName:group.groupName];
    [groupBuilder setMembersArray:group.groupMemberIds];
#ifdef CONVERSATION_COLORS_ENABLED
    [groupBuilder setColor:groupThread.conversationColorName];
#endif

    NSData *avatarPng;
    if (group.groupImage) {
        SSKProtoGroupDetailsAvatarBuilder *avatarBuilder =
            [SSKProtoGroupDetailsAvatarBuilder new];

        [avatarBuilder setContentType:OWSMimeTypeImagePng];
        avatarPng = UIImagePNGRepresentation(group.groupImage);
        [avatarBuilder setLength:(uint32_t)avatarPng.length];
        [groupBuilder setAvatarBuilder:avatarBuilder];
    }

    OWSDisappearingMessagesConfiguration *_Nullable disappearingMessagesConfiguration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:groupThread.uniqueId transaction:transaction];

    if (disappearingMessagesConfiguration && disappearingMessagesConfiguration.isEnabled) {
        [groupBuilder setExpireTimer:disappearingMessagesConfiguration.durationSeconds];
    } else {
        // Rather than *not* set the field, we expicitly set it to 0 so desktop
        // can easily distinguish between a modern client declaring "off" vs a
        // legacy client "not specifying".
        [groupBuilder setExpireTimer:0];
    }

    NSData *groupData = [[groupBuilder build] data];
    uint32_t groupDataLength = (uint32_t)groupData.length;

    [self.delegateStream writeRawVarint32:groupDataLength];
    [self.delegateStream writeRawData:groupData];

    if (avatarPng) {
        [self.delegateStream writeRawData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
