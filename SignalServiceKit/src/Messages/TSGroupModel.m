//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"
#import "UIImage+OWS.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const int32_t kGroupIdLength = 16;

NSUInteger const TSGroupModelSchemaVersion = 1;

@interface TSGroupModel ()

@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@end

#pragma mark -

@implementation TSGroupModel

@synthesize groupName = _groupName;

#if TARGET_OS_IOS

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
                  groupsVersion:(GroupsVersion)groupsVersion
          groupSecretParamsData:(nullable NSData *)groupSecretParamsData
{
    OWSAssertDebug(members != nil);
    OWSAssertDebug(groupId.length == kGroupIdLength);
    if (groupsVersion == GroupsVersionV1) {
        OWSAssertDebug(groupSecretParamsData == nil);
    } else {
        OWSAssertDebug(groupSecretParamsData.length > 0);
    }

    self = [super init];
    if (!self) {
        return self;
    }

    _groupName = name;
    _groupMembers = [members copy];
    _groupAvatarData = avatarData;
    _groupId = groupId;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;
    _groupsVersion = groupsVersion;
    _groupSecretParamsData = groupSecretParamsData;

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

    if (self.groupAvatarData == nil) {
        UIImage *_Nullable groupImage = [coder decodeObjectForKey:@"groupImage"];
        if ([groupImage isKindOfClass:[UIImage class]]) {
            self.groupAvatarData = [TSGroupModel dataForGroupAvatar:groupImage];
        }
    }

    return self;
}

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image
{
    if (image == nil) {
        return nil;
    }
    const CGFloat kMaxDimension = 800;
    if (image.pixelWidth > kMaxDimension ||
        image.pixelHeight > kMaxDimension) {
        CGFloat thumbnailSizePixels = MIN(kMaxDimension, MIN(image.pixelWidth, image.pixelHeight));
        image = [image resizedImageToFillPixelSize:CGSizeMake(thumbnailSizePixels, thumbnailSizePixels)];

        if (image == nil ||
            image.pixelWidth > kMaxDimension ||
            image.pixelHeight > kMaxDimension) {
            OWSLogVerbose(@"Could not resize group avatar: %@",
                          NSStringFromCGSize(image.pixelSize));
            OWSFailDebug(@"Could not resize group avatar.");
            return nil;
        }
    }
    NSData *_Nullable data = UIImagePNGRepresentation(image);
    if (data.length < 1) {
        OWSFailDebug(@"Could not convert group avatar to PNG.");
        return nil;
    }
    // We should never hit this limit, given the max dimension above.
    const NSUInteger kMaxLength = 500 * 1000;
    if (data.length > kMaxLength) {
        OWSLogVerbose(@"Group avatar data length: %lu (%@)",
                      (unsigned long)data.length,
                      NSStringFromCGSize(image.pixelSize));
        OWSFailDebug(@"Group avatar data has invalid length.");
        return nil;
    }
    return data;
}

- (void)setGroupAvatarDataWithImage:(nullable UIImage *)image
{
    self.groupAvatarData = [TSGroupModel dataForGroupAvatar:image];
}

- (nullable UIImage *)groupAvatarImage
{
    return [UIImage imageWithData:self.groupAvatarData];
}

- (void)setGroupAvatarData:(nullable NSData *)groupAvatarData {
    if (_groupAvatarData.length > 0 && groupAvatarData.length < 1) {
        OWSFailDebug(@"We should never remove an avatar from a group with an avatar.");
        return;
    }
    _groupAvatarData = groupAvatarData;
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
    if (![NSObject isNullableObject:self.groupName equalTo:other.groupName]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupAvatarData equalTo:other.groupAvatarData]) {
        return NO;
    }
    NSSet<SignalServiceAddress *> *myGroupMembersSet = [NSSet setWithArray:_groupMembers];
    NSSet<SignalServiceAddress *> *otherGroupMembersSet = [NSSet setWithArray:other.groupMembers];
    if (![myGroupMembersSet isEqualToSet:otherGroupMembersSet]) {
        return NO;
    }
    if (_groupsVersion != other.groupsVersion) {
        return NO;
    }
    if (![NSObject isNullableObject:self.groupSecretParamsData equalTo:other.groupSecretParamsData]) {
        return NO;
    }
    return YES;
}

- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)newModel contactsManager:(id<ContactsManagerProtocol>)contactsManager {
    NSString *updatedGroupInfoString = @"";
    if (self == newModel) {
        return NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    if (![NSObject isNullableObject:_groupName equalTo:newModel.groupName] && newModel.groupName.length > 0) {
        updatedGroupInfoString = [updatedGroupInfoString
            stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_TITLE_CHANGED", @""),
                                              newModel.groupNameOrDefault]];
    }
    if (![NSObject isNullableObject:self.groupAvatarData equalTo:newModel.groupAvatarData]) {
        // Group avatar changed.
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

- (NSString *)groupNameOrDefault
{
    NSString *_Nullable groupName = self.groupName;
    return groupName.length > 0 ? groupName : TSGroupThread.defaultGroupName;
}

+ (NSData *)generateRandomGroupId
{
    return [Randomness generateRandomBytes:kGroupIdLength];
}

- (NSArray<SignalServiceAddress *> *)externalGroupMembers
{
    return [self.groupMembers filter:^(SignalServiceAddress *groupMemberId) {
        return !groupMemberId.isLocalAddress;
    }];
}

@end

NS_ASSUME_NONNULL_END
