//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"
#import "NSString+SSK.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const int32_t kGroupIdLength = 16;
NSUInteger const TSGroupModelSchemaVersion = 1;

@interface TSGroupModel ()

@property (nullable, nonatomic) NSString *groupName;
@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@end

#pragma mark -

@implementation TSGroupModel

#if TARGET_OS_IOS
- (instancetype)initWithTitle:(nullable NSString *)title
                      members:(NSArray<SignalServiceAddress *> *)members
                        image:(nullable UIImage *)image
                      groupId:(NSData *)groupId
{
    OWSAssertDebug(members);
    OWSAssertDebug(groupId.length == kGroupIdLength);

    self = [super init];
    if (!self) {
        return self;
    }

    _groupName = title;
    _groupMembers = [members copy];
    _groupImage = image; // image is stored in DB
    _groupId = groupId;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    return self;
}

- (instancetype)initWithGroupId:(NSData *)groupId
                   groupMembers:(NSArray<SignalServiceAddress *> *)groupMembers
                      groupName:(nullable NSString *)groupName
{
    OWSAssertDebug(groupMembers);
    OWSAssertDebug(groupId.length == kGroupIdLength);

    self = [super init];
    if (!self) {
        return self;
    }

    _groupId = groupId;
    _groupMembers = [groupMembers copy];
    _groupName = groupName;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    OWSAssertDebug(self.groupId.length == kGroupIdLength);

    if (_groupModelSchemaVersion < 1) {
        NSArray<NSString *> *_Nullable memberE164s = [coder decodeObjectForKey:@"groupMemberIds"];
        if (memberE164s) {
            NSMutableArray<SignalServiceAddress *> *memberAddresses = [NSMutableArray new];
            for (NSString *phoneNumber in memberE164s) {
                [memberAddresses addObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
            }
            _groupMembers = [memberAddresses copy];
        } else {
            _groupMembers = @[];
        }
    }

    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    return self;
}

- (NSArray<NSString *> *)transitional_groupMemberPhoneNumbers
{
    NSMutableArray *groupMemberPhoneNumbers = [NSMutableArray new];
    for (SignalServiceAddress *address in self.groupMembers) {
        [groupMemberPhoneNumbers addObject:address.transitional_phoneNumber];
    }
    return [groupMemberPhoneNumbers copy];
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
    NSMutableArray *compareMyGroupMembers = [NSMutableArray arrayWithArray:_groupMembers];
    for (SignalServiceAddress *address in other.groupMembers) {
        [compareMyGroupMembers removeObject:address];
    }
    if ([compareMyGroupMembers count] > 0) {
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
    NSSet *oldMembers = [NSSet setWithArray:_groupMembers];
    NSSet *newMembers = [NSSet setWithArray:newModel.groupMembers];

    NSMutableSet *membersWhoJoined = [NSMutableSet setWithSet:newMembers];
    [membersWhoJoined minusSet:oldMembers];

    NSMutableSet *membersWhoLeft = [NSMutableSet setWithSet:oldMembers];
    [membersWhoLeft minusSet:newMembers];


    if ([membersWhoLeft count] > 0) {
        NSArray *oldMembersNames = [[membersWhoLeft allObjects] map:^NSString *(SignalServiceAddress *item) {
            return [contactsManager displayNameForAddress:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""),
                                                           [oldMembersNames componentsJoinedByString:@", "]]];
    }
    
    if ([membersWhoJoined count] > 0) {
        NSArray *newMembersNames = [[membersWhoJoined allObjects] map:^NSString *(SignalServiceAddress *item) {
            return [contactsManager displayNameForAddress:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_JOINED", @""),
                                                           [newMembersNames componentsJoinedByString:@", "]]];
    }

    return updatedGroupInfoString;
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

@end

NS_ASSUME_NONNULL_END
