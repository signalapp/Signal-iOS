//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"

@implementation TSGroupModel

#if TARGET_OS_IOS
- (instancetype)initWithTitle:(NSString *)title
                    memberIds:(NSArray<NSString *> *)memberIds
                        image:(UIImage *)image
                      groupId:(NSData *)groupId
{
    _groupName              = title;
    _groupMemberIds         = [memberIds copy];
    _groupImage = image; // image is stored in DB
    _groupId                = groupId;

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
    NSMutableArray *compareMyGroupMemberIds = [NSMutableArray arrayWithArray:_groupMemberIds];
    [compareMyGroupMemberIds removeObjectsInArray:other.groupMemberIds];
    if ([compareMyGroupMemberIds count] > 0) {
        return NO;
    }
    return YES;
}

- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)newModel contactsManager:(id<ContactsManagerProtocol>)contactsManager {
    NSString *updatedGroupInfoString = @"";
    if (self == newModel) {
        return NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    if (![_groupName isEqual:newModel.groupName]) {
        updatedGroupInfoString = [updatedGroupInfoString
            stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_TITLE_CHANGED", @""),
                                                               newModel.groupName]];
    }
    if (_groupImage != nil && newModel.groupImage != nil &&
        !([UIImagePNGRepresentation(_groupImage) isEqualToData:UIImagePNGRepresentation(newModel.groupImage)])) {
        updatedGroupInfoString =
            [updatedGroupInfoString stringByAppendingString:NSLocalizedString(@"GROUP_AVATAR_CHANGED", @"")];
    }
    if ([updatedGroupInfoString length] == 0) {
        updatedGroupInfoString = NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    NSSet *oldMembers = [NSSet setWithArray:_groupMemberIds];
    NSSet *newMembers = [NSSet setWithArray:newModel.groupMemberIds];

    NSMutableSet *membersWhoJoined = [NSMutableSet setWithSet:newMembers];
    [membersWhoJoined minusSet:oldMembers];

    NSMutableSet *membersWhoLeft = [NSMutableSet setWithSet:oldMembers];
    [membersWhoLeft minusSet:newMembers];


    if ([membersWhoLeft count] > 0) {
        NSArray *oldMembersNames = [[membersWhoLeft allObjects] map:^NSString*(NSString* item) {
            return [contactsManager displayNameForPhoneIdentifier:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""),
                                                           [oldMembersNames componentsJoinedByString:@", "]]];
    }
    
    if ([membersWhoJoined count] > 0) {
        NSArray *newMembersNames = [[membersWhoJoined allObjects] map:^NSString*(NSString* item) {
            return [contactsManager displayNameForPhoneIdentifier:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_JOINED", @""),
                                                           [newMembersNames componentsJoinedByString:@", "]]];
    }

    return updatedGroupInfoString;
}


#endif

@end
