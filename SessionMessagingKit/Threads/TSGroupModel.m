//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SignalCoreKit/NSString+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const int32_t kGroupIdLength = 16;

@interface TSGroupModel ()

@property (nullable, nonatomic) NSString *groupName;

@end

#pragma mark -

@implementation TSGroupModel

#if TARGET_OS_IOS
- (instancetype)initWithTitle:(nullable NSString *)title
                    memberIds:(NSArray<NSString *> *)memberIds
                        image:(nullable UIImage *)image
                      groupId:(NSData *)groupId
                    groupType:(GroupType)groupType
                     adminIds:(NSArray<NSString *> *)adminIds
{
    _groupName              = title;
    _groupMemberIds         = [memberIds copy];
    _groupImage = image; // image is stored in DB
    _groupType              = groupType;
    _groupId                = groupId;
    _groupAdminIds          = [adminIds copy];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // Occasionally seeing this as nil in legacy data,
    // which causes crashes.
    if (_groupMemberIds == nil) {
        _groupMemberIds = [NSArray new];
    }
    
    if (_groupAdminIds == nil) {
        _groupAdminIds = [NSArray new];
    }
    
    if (_removedMembers == nil) {
        _removedMembers = [NSMutableSet new];
    }

    return self;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    return [self isEqualToGroupModel:other];
}

- (BOOL)isEqualToGroupModel:(TSGroupModel *)other {
    if (self == other)
        return YES;
    if (![_groupId isEqualToData:other.groupId]) {
        return NO;
    }
    if (![_groupName isEqual:other.groupName]) {
        return NO;
    }
    if (!(_groupImage != nil && other.groupImage != nil &&
          [UIImagePNGRepresentation(_groupImage) isEqualToData:UIImagePNGRepresentation(other.groupImage)])) {
        return NO;
    }
    if (_groupType != other.groupType) {
        return NO;
    }
    NSMutableArray *compareMyGroupMemberIds = [NSMutableArray arrayWithArray:_groupMemberIds];
    [compareMyGroupMemberIds removeObjectsInArray:other.groupMemberIds];
    if ([compareMyGroupMemberIds count] > 0) {
        return NO;
    }
    return YES;
}

- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)newModel {
    NSString *updatedGroupInfoString = @"";
    if (self == newModel) {
        return NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    if (![_groupName isEqual:newModel.groupName]) {
        if (newModel.groupName.length == 0) {
            updatedGroupInfoString = [updatedGroupInfoString stringByAppendingString:@"Closed group created"];
        } else {
            updatedGroupInfoString = [updatedGroupInfoString stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_TITLE_CHANGED", @""), newModel.groupName]];
        }
    }
    if (_groupImage != nil && newModel.groupImage != nil &&
        !([UIImagePNGRepresentation(_groupImage) isEqualToData:UIImagePNGRepresentation(newModel.groupImage)])) {
        updatedGroupInfoString =
            [updatedGroupInfoString stringByAppendingString:NSLocalizedString(@"GROUP_AVATAR_CHANGED", @"")];
    }
    NSSet *oldMembers = [NSSet setWithArray:_groupMemberIds];
    NSSet *newMembers = [NSSet setWithArray:newModel.groupMemberIds];

    NSMutableSet *membersWhoJoined = [NSMutableSet setWithSet:newMembers];
    [membersWhoJoined minusSet:oldMembers];

    NSMutableSet *membersWhoLeft = [NSMutableSet setWithSet:oldMembers];
    [membersWhoLeft minusSet:newMembers];
    [membersWhoLeft minusSet:newModel.removedMembers];


    if ([membersWhoLeft count] > 0) {
        NSArray *oldMembersNames = [[membersWhoLeft allObjects] map:^NSString*(NSString* item) {
            return [LKUserDisplayNameUtilities getPrivateChatDisplayNameAvoidWriteTransaction:item] ?: item;
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""),
                                                           [oldMembersNames componentsJoinedByString:@", "]]];
    }
    
    if (membersWhoJoined.count > 0) {
        NSArray *newMembersNames = [[membersWhoJoined allObjects] map:^NSString*(NSString* item) {
            return [LKUserDisplayNameUtilities getPrivateChatDisplayNameAvoidWriteTransaction:item] ?: item;
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_JOINED", @""),
                                                           [newMembersNames componentsJoinedByString:@", "]]];
    }
    
    if (newModel.removedMembers.count > 0) {
        if ([newModel.removedMembers containsObject:[SNGeneralUtilities getUserPublicKey]]) {
            updatedGroupInfoString = [updatedGroupInfoString
                                      stringByAppendingString:NSLocalizedString(@"YOU_WERE_REMOVED", @"")];
        } else {
            NSArray *removedMemberNames = [newModel.removedMembers.allObjects map:^NSString*(NSString* publicKey) {
                return [LKUserDisplayNameUtilities getPrivateChatDisplayNameAvoidWriteTransaction:publicKey] ?: publicKey;
            }];
            if ([removedMemberNames count] > 1) {
                updatedGroupInfoString = [updatedGroupInfoString
                                          stringByAppendingString:[NSString
                                                                   stringWithFormat:NSLocalizedString(@"GROUP_MEMBERS_REMOVED", @""),
                                                                   [removedMemberNames componentsJoinedByString:@", "]]];
            }
            else {
                updatedGroupInfoString = [updatedGroupInfoString
                                          stringByAppendingString:[NSString
                                                                   stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_REMOVED", @""),
                                                                   removedMemberNames[0]]];
            }
        }
    }
    if ([updatedGroupInfoString length] == 0) {
        updatedGroupInfoString = NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    return updatedGroupInfoString;
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

- (void)setRemovedMembers:(NSMutableSet<NSString *> *)removedMembers
{
    _removedMembers = removedMembers;
}

- (void)updateGroupId: (NSData *)newGroupId
{
    _groupId = newGroupId;
}

@end

NS_ASSUME_NONNULL_END
