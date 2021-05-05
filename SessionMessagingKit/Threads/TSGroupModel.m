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

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

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
    _groupImage             = image;
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
    // This is only invoked for group * changes *, i.e. not when a group is created.
    NSString *userPublicKey = [SNGeneralUtilities getUserPublicKey];
    NSString *updatedGroupInfoString = @"";
    if (self == newModel) {
        return NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    // Name change
    if (![_groupName isEqual:newModel.groupName]) {
        updatedGroupInfoString = [updatedGroupInfoString stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_TITLE_CHANGED", @""), newModel.groupName]];
    }
    // Added & removed members
    NSSet *oldMembers = [NSSet setWithArray:_groupMemberIds];
    NSSet *newMembers = [NSSet setWithArray:newModel.groupMemberIds];

    NSMutableSet *addedMembers = newMembers.mutableCopy;
    [addedMembers minusSet:oldMembers];

    NSMutableSet *removedMembers = oldMembers.mutableCopy;
    [removedMembers minusSet:newMembers];

    NSMutableSet *removedMembersMinusSelf = removedMembers.mutableCopy;
    [removedMembersMinusSelf minusSet:[NSSet setWithObject:userPublicKey]];

    if (removedMembersMinusSelf.count > 0) {
        NSArray *removedMemberNames = [removedMembers.allObjects map:^NSString *(NSString *publicKey) {
            SNContact *contact = [LKStorage.shared getContactWithSessionID:publicKey];
            return [contact displayNameFor:SNContactContextRegular] ?: publicKey;
        }];
        NSString *format = removedMembers.count > 1 ? NSLocalizedString(@"GROUP_MEMBERS_REMOVED", @"") : NSLocalizedString(@"GROUP_MEMBER_REMOVED", @"");
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat: format,
                                                           [removedMemberNames componentsJoinedByString:@", "]]];
    }
    
    if (addedMembers.count > 0) {
        NSArray *addedMemberNames = [[addedMembers allObjects] map:^NSString*(NSString* publicKey) {
            SNContact *contact = [LKStorage.shared getContactWithSessionID:publicKey];
            return [contact displayNameFor:SNContactContextRegular] ?: publicKey;
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_JOINED", @""),
                                                           [addedMemberNames componentsJoinedByString:@", "]]];
    }

    if ([removedMembers containsObject:userPublicKey]) {
        updatedGroupInfoString = [updatedGroupInfoString stringByAppendingString:NSLocalizedString(@"YOU_WERE_REMOVED", @"")];
    }
    // Return
    if ([updatedGroupInfoString length] == 0) {
        updatedGroupInfoString = NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    return updatedGroupInfoString;
}

#endif

@end

NS_ASSUME_NONNULL_END
