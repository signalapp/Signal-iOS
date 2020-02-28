//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

- (void)writeGroup:(TSGroupThread *)groupThread transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupThread);
    OWSAssertDebug(transaction);
    if (groupThread.isGroupV2Thread) {
        OWSFailDebug(@"Invalid group.");
        return;
    }

    TSGroupModel *group = groupThread.groupModel;
    OWSAssertDebug(group);

    SSKProtoGroupDetailsBuilder *groupBuilder = [SSKProtoGroupDetails builderWithId:group.groupId];
    [groupBuilder setName:group.groupName];

    NSMutableArray *membersE164 = [NSMutableArray new];
    NSMutableArray *members = [NSMutableArray new];

    for (SignalServiceAddress *address in [GroupMembership normalize:group.groupMembers]) {
        // We currently include an independent group member list
        // of just the phone numbers to support older pre-UUID
        // clients. Eventually we probably want to remove this.
        if (address.phoneNumber) {
            [membersE164 addObject:address.phoneNumber];
        }

        SSKProtoGroupDetailsMemberBuilder *memberBuilder = [SSKProtoGroupDetailsMember builder];
        memberBuilder.uuid = address.uuidString;
        memberBuilder.e164 = address.phoneNumber;

        NSError *error;
        SSKProtoGroupDetailsMember *_Nullable member = [memberBuilder buildAndReturnError:&error];
        if (error || !member) {
            OWSFailDebug(@"could not build members protobuf: %@", error);
        } else {
            [members addObject:member];
        }
    }

    [groupBuilder setMembersE164:membersE164];
    [groupBuilder setMembers:members];

    [groupBuilder setColor:groupThread.conversationColorName];

    if ([OWSBlockingManager.sharedManager isGroupIdBlocked:group.groupId]) {
        [groupBuilder setBlocked:YES];
    }

    [groupBuilder setArchived:groupThread.isArchived];
    NSNumber *_Nullable sortIndex = [[AnyThreadFinder new] sortIndexObjcWithThread:groupThread transaction:transaction];
    if (sortIndex != nil) {
        [groupBuilder setInboxPosition:sortIndex.intValue];
    }

    // TODO setActive based on soft delete?

    NSData *_Nullable groupAvatarData = nil;
    if (group.groupAvatarData.length > 0) {
        SSKProtoGroupDetailsAvatarBuilder *avatarBuilder = [SSKProtoGroupDetailsAvatar builder];

        [avatarBuilder setContentType:OWSMimeTypeImagePng];
        groupAvatarData = group.groupAvatarData;
        [avatarBuilder setLength:(uint32_t)groupAvatarData.length];

        NSError *error;
        SSKProtoGroupDetailsAvatar *_Nullable avatarProto = [avatarBuilder buildAndReturnError:&error];
        if (error || !avatarProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
        } else {
            [groupBuilder setAvatar:avatarProto];
        }
    }

    OWSDisappearingMessagesConfiguration *_Nullable disappearingMessagesConfiguration =
        [groupThread disappearingMessagesConfigurationWithTransaction:transaction];

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

    if (groupAvatarData) {
        [self writeData:groupAvatarData];
    }
}

@end

NS_ASSUME_NONNULL_END
