//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGroupsOutputStream.h"
#import "MIMETypeUtil.h"
#import "OWSBlockingManager.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSGroupsOutputStream

- (void)writeGroup:(TSGroupThread *)groupThread transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(transaction);

    TSGroupModel *group = groupThread.groupModel;
    OWSAssertDebug(group);

    SSKProtoGroupDetailsBuilder *groupBuilder = [SSKProtoGroupDetailsBuilder new];
    [groupBuilder setId:group.groupId];
    [groupBuilder setName:group.groupName];
    [groupBuilder setMembers:group.groupMemberIds];
    [groupBuilder setColor:groupThread.conversationColorName];

    if ([OWSBlockingManager.sharedManager isGroupIdBlocked:group.groupId]) {
        [groupBuilder setBlocked:YES];
    }

    NSData *avatarPng;
    if (group.groupImage) {
        SSKProtoGroupDetailsAvatarBuilder *avatarBuilder =
            [SSKProtoGroupDetailsAvatarBuilder new];

        [avatarBuilder setContentType:OWSMimeTypeImagePng];
        avatarPng = UIImagePNGRepresentation(group.groupImage);
        [avatarBuilder setLength:(uint32_t)avatarPng.length];

        NSError *error;
        SSKProtoGroupDetailsAvatar *_Nullable avatarProto = [avatarBuilder buildAndReturnError:&error];
        if (error || !avatarProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
        } else {
            [groupBuilder setAvatar:avatarProto];
        }
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

    NSError *error;
    NSData *_Nullable groupData = [groupBuilder buildSerializedDataAndReturnError:&error];
    if (error || !groupData) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return;
    }

    uint32_t groupDataLength = (uint32_t)groupData.length;

    [self writeVariableLengthUInt32:groupDataLength];
    [self writeData:groupData];

    if (avatarPng) {
        [self writeData:avatarPng];
    }
}

@end

NS_ASSUME_NONNULL_END
