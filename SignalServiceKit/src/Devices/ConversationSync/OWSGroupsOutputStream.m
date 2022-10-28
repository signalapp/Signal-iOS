//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSGroupsOutputStream.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
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

    ThreadAssociatedData *associatedData = [ThreadAssociatedData fetchOrDefaultForThread:groupThread
                                                                             transaction:transaction];
    TSGroupModel *group = groupThread.groupModel;
    OWSAssertDebug(group);

    SSKProtoGroupDetailsBuilder *groupBuilder = [SSKProtoGroupDetails builderWithId:group.groupId];
    [groupBuilder setName:group.groupName];

    NSMutableArray *membersE164 = [NSMutableArray new];
    NSMutableArray *members = [NSMutableArray new];

    for (SignalServiceAddress *address in [GroupMembership normalize:group.groupMembers]) {
        if (address.phoneNumber) {
            [membersE164 addObject:address.phoneNumber];

            // Newer desktops only know how to handle the "pairing"
            // fields that we rolled back when implementing UUID
            // trust. We need to continue populating them with
            // phone number only to make sure desktop can see
            // group membership.
            SSKProtoGroupDetailsMemberBuilder *memberBuilder = [SSKProtoGroupDetailsMember builder];
            memberBuilder.e164 = address.phoneNumber;

            NSError *error;
            SSKProtoGroupDetailsMember *_Nullable member = [memberBuilder buildAndReturnError:&error];
            if (error || !member) {
                OWSFailDebug(@"could not build members protobuf: %@", error);
            } else {
                [members addObject:member];
            }
        } else {
            OWSFailDebug(@"Unexpectedly have a UUID only member in a v1 group, ignoring %@", address);
        }
    }

    [groupBuilder setMembersE164:membersE164];
    [groupBuilder setMembers:members];

    if ([BlockingManager.shared isGroupIdBlocked:group.groupId transaction:transaction]) {
        [groupBuilder setBlocked:YES];
    }

    [groupBuilder setArchived:associatedData.isArchived];
    NSNumber *_Nullable sortIndex = [[AnyThreadFinder new] sortIndexObjcWithThread:groupThread transaction:transaction];
    if (sortIndex != nil) {
        [groupBuilder setInboxPosition:sortIndex.unsignedIntValue];
    }

    // TODO setActive based on soft delete?

    NSData *_Nullable avatarData = nil;
    if (group.avatarData.length > 0) {
        SSKProtoGroupDetailsAvatarBuilder *avatarBuilder = [SSKProtoGroupDetailsAvatar builder];

        OWSAssertDebug([TSGroupModel isValidGroupAvatarData:group.avatarData]);
        ImageFormat format = [group.avatarData imageMetadataWithPath:nil mimeType:nil].imageFormat;
        NSString *mimeType = (format == ImageFormat_Png) ? OWSMimeTypeImagePng : OWSMimeTypeImageJpeg;

        [avatarBuilder setContentType:mimeType];
        avatarData = group.avatarData;
        [avatarBuilder setLength:(uint32_t)avatarData.length];

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
        // Rather than *not* set the field, we explicitly set it to 0 so desktop
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

    if (avatarData) {
        [self writeData:avatarData];
    }
}

@end

NS_ASSUME_NONNULL_END
