//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGroupsOutputStream.h"
#import "MIMETypeUtil.h"
#import "OWSBlockingManager.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSGroupsOutputStream

- (void)writeGroup:(TSGroupThread *)groupThread transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(transaction);

    TSGroupModel *group = groupThread.groupModel;
    OWSAssertDebug(group);

    SSKProtoGroupDetailsBuilder *groupBuilder = [SSKProtoGroupDetails builderWithId:group.groupId];
    [groupBuilder setName:group.groupName];
    [groupBuilder setMembers:group.groupMemberIds];
    [groupBuilder setAdmins:group.groupAdminIds];

    if ([OWSBlockingManager.sharedManager isGroupIdBlocked:group.groupId]) {
        [groupBuilder setBlocked:YES];
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

    [self writeUInt32:groupDataLength];
    [self writeData:groupData];
}

@end

NS_ASSUME_NONNULL_END
